import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:monero_dart/monero_dart.dart';
import 'package:sodium/sodium_sumo.dart';

import '../network/wallet_network.dart';
import '../transfer/transfer_document.dart';
import 'xmr_keys.dart';

/// Erro de validação, com mensagem pronta para o usuário.
final class XmrSignException implements Exception {
  const XmrSignException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// O que o assinador mostra antes de assinar.
final class XmrReview {
  const XmrReview({
    required this.destination,
    required this.amount,
    required this.fee,
    required this.change,
    required this.inputsTotal,
    required this.inputs,
  });

  /// 1 XMR = 10^12 piconeros.
  static final BigInt _xmr = BigInt.from(10).pow(12);

  final String destination;
  final BigInt amount;
  final BigInt fee;
  final BigInt change;
  final BigInt inputsTotal;
  final int inputs;

  List<String> get warnings => [
    if (fee * BigInt.from(10) > amount) 'A taxa passa de 10% do valor enviado.',
    if (fee * BigInt.from(100) > _xmr) 'Taxa anormalmente alta (> 0,01 XMR).',
  ];
}

/// Lado frio do Monero: destrava só as saídas desta seed, calcula a taxa
/// exata, assina (CLSAG + Bulletproofs+), confere a assinatura e devolve as
/// key images. Nunca acessa a rede.
abstract final class XmrSigner {
  static XmrReview review(XmrSignRequest request, SecureKey seed) =>
      _prepare(request, seed, build: false).$1;

  static XmrSignedTransaction sign(XmrSignRequest request, SecureKey seed) {
    final (_, builder, keyImages) = _prepare(request, seed, build: true);
    final tx = builder!.transaction;
    return XmrSignedTransaction(
      network: request.network,
      txHex: BytesUtils.toHexString(tx.serialize()),
      txHash: tx.getTxHash(),
      keyImages: keyImages,
    );
  }

  /// Só as key images (para a carteira online descobrir o que foi gasto).
  static XmrKeyImages keyImages(XmrKeyImageRequest request, SecureKey seed) =>
      seed.runUnlockedSync((bytes) {
        final keys = XmrKeys.keys(
          XmrKeys.fullAccount(bytes, request.network),
          request.network,
        );
        return XmrKeyImages(
          network: request.network,
          keyImages: _keyImagesOf(request.knownOutputs, keys),
        );
      });

  static (XmrReview, MoneroRctTxBuilder?, Map<String, String>) _prepare(
    XmrSignRequest request,
    SecureKey seed, {
    required bool build,
  }) => seed.runUnlockedSync((bytes) {
    final network = request.network;
    final account = XmrKeys.fullAccount(bytes, network);
    final keys = XmrKeys.keys(account, network);

    // Entradas: cada uma precisa ser desta seed; o anel vem da online.
    final sources = <SpendablePayment<MoneroUnLockedPayment>>[];
    final seenKeyImages = <String>{};
    for (final (i, hex) in request.sources.indexed) {
      final spendable = _decodeSpendable(hex, i);
      final locked = spendable.payment;
      if (locked is! MoneroLockedPayment) {
        throw XmrSignException('Entrada nº ${i + 1} em formato inesperado.');
      }
      _checkRing(spendable, locked, i);
      final unlocked = _owns(keys, locked.output)
          ? MoneroTransactionHelper.toUnlockPayment(
              account: keys,
              lockedOut: locked,
            )
          : null;
      if (unlocked == null) {
        throw XmrSignException(
          'A entrada nº ${i + 1} não pertence a esta carteira '
          '(seed, respostas ou rede diferentes).',
        );
      }
      final real = spendable.outs[spendable.realOutIndex].key.dest;
      if (BytesUtils.toHexString(real) !=
          BytesUtils.toHexString(unlocked.output.ephemeralPublicKey)) {
        throw XmrSignException(
          'O anel da entrada nº ${i + 1} não contém a sua saída.',
        );
      }
      if (!seenKeyImages.add(
        BytesUtils.toHexString(unlocked.output.keyImage.keyImage),
      )) {
        throw const XmrSignException('Entrada repetida. Recusado.');
      }
      sources.add(
        SpendablePayment(
          payment: unlocked,
          outs: spendable.outs,
          realOutIndex: spendable.realOutIndex,
        ),
      );
    }
    if (sources.isEmpty) throw const XmrSignException('Nenhuma entrada.');

    if (request.destinations.length != 1) {
      throw const XmrSignException('Só um destino por envio nesta versão.');
    }
    final destinationAddress = _address(
      request.destinations.single.address,
      network,
    );
    final changeAddress = MoneroAddress(account.primaryAddress);
    final inputsTotal = sources.fold(
      BigInt.zero,
      (s, p) => s + p.payment.output.amount,
    );
    final requested = request.destinations.single.amount;
    final sweep = requested == BigInt.zero;
    final DaemonGetEstimateFeeResponse baseFee;
    try {
      baseFee = DaemonGetEstimateFeeResponse.fromJson(request.feeEstimate);
    } on Object {
      throw const XmrSignException('Estimativa de taxa inválida.');
    }

    // 1ª montagem "fake" só para medir o peso → taxa exata.
    MoneroRctTxBuilder assemble(BigInt fee, {required bool fake}) {
      final amount = sweep ? inputsTotal - fee : requested;
      final change = inputsTotal - amount - fee;
      if (amount <= BigInt.zero || change.isNegative) {
        throw const XmrSignException('Saldo das entradas insuficiente.');
      }
      return MoneroRctTxBuilder(
        account: keys,
        destinations: [
          MoneroTxDestination(amount: amount, address: destinationAddress),
        ],
        sources: sources,
        fee: fee,
        change: MoneroTxDestination(amount: change, address: changeAddress),
        fast: true,
        fakeTx: fake,
      );
    }

    final provisional = MoneroFeePrority.defaultPriority.getBaseFee(baseFee);
    final weight = assemble(provisional, fake: true).weight();
    final fee = MoneroFeePrority.defaultPriority.calcuateFee(
      weight: weight,
      baseFee: baseFee,
    );
    final amount = sweep ? inputsTotal - fee : requested;
    final review = XmrReview(
      destination: destinationAddress.address,
      amount: amount,
      fee: fee,
      change: inputsTotal - amount - fee,
      inputsTotal: inputsTotal,
      inputs: sources.length,
    );
    if (!build) return (review, null, const <String, String>{});

    final builder = assemble(fee, fake: false);
    _verify(builder);
    return (review, builder, _keyImagesOf(request.knownOutputs, keys));
  });

  /// Confere a assinatura RingCT (CLSAG + Bulletproofs+) antes de salvar,
  /// com a mesma verificação que os nós fazem.
  static void _verify(MoneroRctTxBuilder builder) {
    bool ok;
    try {
      ok = RCTGeneratorUtils.verRctSimple(
        builder.transaction.signature.cast<RCTSignature>(),
      );
    } on Object {
      ok = false;
    }
    if (!ok) {
      throw const XmrSignException(
        'A assinatura gerada não passou na verificação. Nada foi salvo.',
      );
    }
  }

  static Map<String, String> _keyImagesOf(
    List<String> knownOutputs,
    MoneroAccountKeys keys,
  ) {
    final result = <String, String>{};
    for (final hex in knownOutputs) {
      final MoneroLockedPayment locked;
      try {
        locked = MoneroLockedPayment.deserialize(BytesUtils.fromHexString(hex));
      } on Object {
        continue;
      }
      if (!_owns(keys, locked.output)) continue; // não é nossa: ignora
      final unlocked = MoneroTransactionHelper.toUnlockPayment(
        account: keys,
        lockedOut: locked,
      );
      if (unlocked == null) continue;
      result[BytesUtils.toHexString(locked.output.outputPublicKey)] =
          BytesUtils.toHexString(unlocked.output.keyImage.keyImage);
    }
    return result;
  }

  /// Tamanho do anel exigido pelo consenso desde 2022 (hard fork v15).
  static const int ringSize = 16;

  /// A saída é desta seed? Confere P = Hs(derivação‖i)·G + B antes de
  /// derivar a chave secreta (o `monero_dart` só confere num `assert`).
  static bool _owns(MoneroAccountKeys keys, MoneroLockedOutput out) {
    try {
      final expected = MoneroCrypto.derivePublicKeyBytesVar(
        derivation: out.derivation,
        outIndex: out.realIndex,
        basePublicKey: keys.getSpendPublicKey(out.accountIndex),
      );
      return BytesUtils.bytesEqual(expected, out.outputPublicKey);
    } on Object {
      return false;
    }
  }

  /// Regras do anel que os nós aplicam, conferidas aqui para recusar um
  /// pedido adulterado com uma mensagem clara: 16 membros em ordem crescente
  /// de índice global, a saída real no seu índice e com o commitment que
  /// corresponde ao valor declarado (senão a revisão mostraria valores
  /// falsos).
  static void _checkRing(
    SpendablePayment<MoneroPayment> spendable,
    MoneroLockedPayment locked,
    int i,
  ) {
    final outs = spendable.outs;
    final n = i + 1;
    if (outs.length != ringSize) {
      throw XmrSignException(
        'O anel da entrada nº $n tem ${outs.length} membros (deveria ter '
        '$ringSize).',
      );
    }
    for (var k = 1; k < outs.length; k++) {
      if (outs[k].index <= outs[k - 1].index) {
        throw XmrSignException('O anel da entrada nº $n está fora de ordem.');
      }
    }
    final real = spendable.realOutIndex;
    if (real >= outs.length || outs[real].index != locked.globalIndex) {
      throw XmrSignException(
        'O anel da entrada nº $n não aponta para a sua saída.',
      );
    }
    final commitment = RCT.commit(
      xmrAmount: locked.output.amount,
      mask: locked.output.mask,
    );
    if (!BytesUtils.bytesEqual(commitment, outs[real].key.mask)) {
      throw XmrSignException(
        'O valor declarado da entrada nº $n não confere com o anel. Recusado.',
      );
    }
  }

  static SpendablePayment<MoneroPayment> _decodeSpendable(String hex, int i) {
    try {
      return SpendablePayment.deserialize(BytesUtils.fromHexString(hex));
    } on Object {
      throw XmrSignException('Entrada nº ${i + 1} ilegível.');
    }
  }

  static MoneroAddress _address(String text, WalletNetwork network) {
    final MoneroAddress address;
    try {
      address = MoneroAddress(text);
    } on Object {
      throw const XmrSignException('Endereço Monero de destino inválido.');
    }
    if (address.network != XmrKeys.networkFor(network)) {
      throw const XmrSignException('Endereço Monero de outra rede.');
    }
    return address;
  }
}
