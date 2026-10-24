import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../core/security/memory.dart';
import '../transfer/transfer_document.dart';
import 'btc_account.dart';
import 'btc_send.dart';

/// Uma saída como o assinador frio a enxerga.
final class BtcReviewOutput {
  const BtcReviewOutput({
    required this.address,
    required this.amount,
    required this.isChange,
  });

  final String address;
  final BigInt amount;

  /// Endereço de troco conferido contra a seed (volta para você).
  final bool isChange;
}

/// O que vai ser assinado, recalculado a partir do próprio PSBT.
final class BtcReview {
  const BtcReview({
    required this.inputsTotal,
    required this.outputs,
    required this.fee,
    required this.vsize,
  });

  /// Acima disso a taxa é considerada anormal (o recorde histórico de taxa
  /// "normal" fica bem abaixo).
  static const int alarmingFeeRate = 300;

  final BigInt inputsTotal;
  final List<BtcReviewOutput> outputs;
  final BigInt fee;
  final int vsize;

  /// Alertas para o usuário confirmar explicitamente antes de assinar.
  List<String> get warnings => [
    if (feeRate > alarmingFeeRate)
      'Taxa anormalmente alta: ~${feeRate.toStringAsFixed(0)} sat/vB.',
    if (sending > BigInt.zero && fee * BigInt.from(10) > sending)
      'A taxa passa de 10% do valor enviado.',
    if (sending == BigInt.zero)
      'Nada vai para terceiros: tudo volta para você (só paga taxa).',
  ];

  BigInt get sending => outputs
      .where((o) => !o.isChange)
      .fold(BigInt.zero, (sum, o) => sum + o.amount);

  double get feeRate => fee.toDouble() / vsize;
}

/// Lado frio: confere e assina PSBTs. Nunca acessa a rede.
abstract final class BtcSigner {
  /// Valida que todas as entradas são desta carteira e calcula valores,
  /// destino, troco e taxa sem confiar em nada além do PSBT e da seed.
  static BtcReview review(BtcSignRequest request, SecureKey seed) {
    final psbt = _parse(request);
    final network = BtcAccount.btcNetworkFor(request.network);
    return seed.runUnlockedSync((bytes) {
      var inputsTotal = BigInt.zero;
      for (var i = 0; i < request.inputPaths.length; i++) {
        final input = psbt.psbtInput(i);
        _checkSighash(input, i);
        _checkOwnership(input.scriptPubKey, bytes, request, i);
        inputsTotal += _inputAmount(input);
      }

      final changeScript = request.changePath == null
          ? null
          : _scriptFor(bytes, request, request.changePath!);
      final txOutputs = psbt.txOutputs();
      final outputs = [
        for (final (i, out) in txOutputs.indexed)
          BtcReviewOutput(
            address: _outputAddress(out.scriptPubKey, network, i),
            amount: out.amount,
            isChange:
                changeScript != null &&
                out.scriptPubKey.toHex() == changeScript.toHex(),
          ),
      ];
      final outputsTotal = outputs.fold(BigInt.zero, (s, o) => s + o.amount);
      final fee = inputsTotal - outputsTotal;
      if (fee.isNegative) {
        throw const BtcSendException('Saídas maiores que as entradas.');
      }
      return BtcReview(
        inputsTotal: inputsTotal,
        outputs: outputs,
        fee: fee,
        vsize: BtcSend.estimateVsize(request.inputPaths.length, outputs.length),
      );
    });
  }

  /// Assina todas as entradas e devolve a transação final pronta para
  /// transmitir.
  static BtcSignedTransaction sign(BtcSignRequest request, SecureKey seed) {
    final psbt = _parse(request);
    final tx = seed.runUnlockedSync((bytes) {
      final signers = <String, PsbtDefaultSigner>{};
      final rawKeys = <List<int>>[];
      try {
        for (var i = 0; i < request.inputPaths.length; i++) {
          final input = psbt.psbtInput(i);
          _checkSighash(input, i);
          _checkOwnership(input.scriptPubKey, bytes, request, i);
          final path = request.inputPaths[i];
          final raw = BtcAccount.privateKeyFromSeed(
            bytes,
            request.network,
            path.chain,
            path.index,
          );
          rawKeys.add(raw);
          signers[input.scriptPubKey.toHex()] = PsbtDefaultSigner(
            ECPrivate.fromBytes(raw),
          );
        }
        psbt.signAllInput(
          (param) => PsbtSignerResponse(
            // Nunca herdar o tipo do PSBT: com SIGHASH_NONE/SINGLE/
            // ANYONECANPAY a assinatura deixa de proteger as saídas e quem
            // transmite pode redirecionar os fundos.
            sighash: BitcoinOpCodeConst.sighashAll,
            signers: [signers[param.scriptPubKey.toHex()]!],
          ),
        );
        final tx = psbt.finalizeAll();
        _checkFinalWitnesses(tx, [
          for (final s in signers.values) s.signerPublicKey.toHex(),
        ]);
        return tx;
      } finally {
        rawKeys.forEach(wipeBytes);
      }
    });
    return BtcSignedTransaction(
      network: request.network,
      txHex: tx.serialize(),
      txid: tx.txId(),
    );
  }

  /// Só aceita SIGHASH_ALL (ou ausente, que vira ALL).
  static void _checkSighash(PsbtTransactionInput input, int index) {
    final declared = input.sigHashType?.sighash;
    if (declared != null && declared != BitcoinOpCodeConst.sighashAll) {
      throw BtcSendException(
        'A entrada nº ${index + 1} pede um tipo de assinatura inseguro '
        '(SIGHASH 0x${declared.toRadixString(16)}). Recusado: com ele, quem '
        'transmite poderia trocar o destino depois da assinatura.',
      );
    }
  }

  /// Defesa em profundidade: cada entrada final precisa ter exatamente
  /// [assinatura SIGHASH_ALL, chave pública desta carteira].
  static void _checkFinalWitnesses(BtcTransaction tx, List<String> ownKeys) {
    for (final (i, witness) in tx.witnesses.indexed) {
      final stack = witness.stack;
      final valid =
          stack.length == 2 &&
          BytesUtils.fromHexString(stack[0]).last ==
              BitcoinOpCodeConst.sighashAll &&
          ownKeys.contains(stack[1].toLowerCase());
      if (!valid) {
        throw BtcSendException(
          'A assinatura final da entrada nº ${i + 1} não confere. Recusado.',
        );
      }
    }
  }

  static String _outputAddress(Script script, BitcoinNetwork network, int i) {
    try {
      return BitcoinScriptUtils.generateAddressFromScriptPubKey(
        script,
      ).toAddress(network);
    } on Object {
      throw BtcSendException(
        'A saída nº ${i + 1} não é um endereço padrão (ex.: OP_RETURN). '
        'Recusado.',
      );
    }
  }

  static PsbtBuilderV0 _parse(BtcSignRequest request) {
    final PsbtBuilderV0 psbt;
    try {
      psbt = PsbtBuilder.fromBase64<PsbtBuilderV0>(request.psbtBase64);
    } on Exception {
      throw const BtcSendException('PSBT inválido.');
    }
    if (psbt.txInputs().length != request.inputPaths.length) {
      throw const BtcSendException(
        'O número de entradas não confere com os caminhos informados.',
      );
    }
    return psbt;
  }

  static Script _scriptFor(
    List<int> seed,
    BtcSignRequest request,
    BtcPath path,
  ) {
    final raw = BtcAccount.privateKeyFromSeed(
      seed,
      request.network,
      path.chain,
      path.index,
    );
    try {
      return ECPrivate.fromBytes(
        raw,
      ).getPublic().toSegwitAddress().toScriptPubKey();
    } finally {
      wipeBytes(raw);
    }
  }

  static void _checkOwnership(
    Script scriptPubKey,
    List<int> seed,
    BtcSignRequest request,
    int index,
  ) {
    final expected = _scriptFor(seed, request, request.inputPaths[index]);
    if (expected.toHex() != scriptPubKey.toHex()) {
      throw BtcSendException(
        'A entrada nº ${index + 1} não pertence a esta carteira '
        '(seed, respostas ou rede diferentes).',
      );
    }
  }

  /// Valor da entrada lido da transação de origem completa; se também houver
  /// witness UTXO, os dois precisam bater.
  static BigInt _inputAmount(PsbtTransactionInput input) {
    final previous = input.nonWitnessUtxo?.transaction;
    final witness = input.witnessUtxo?.amount;
    if (previous == null) {
      if (witness == null) {
        throw const BtcSendException('Entrada sem valor informado.');
      }
      return witness;
    }
    if (previous.txId() != input.txInput.txId) {
      throw const BtcSendException('Transação de origem não confere.');
    }
    final amount = previous.outputs[input.txInput.txIndex].amount;
    if (witness != null && witness != amount) {
      throw const BtcSendException('Valores da entrada divergentes.');
    }
    return amount;
  }
}
