import 'dart:convert';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:on_chain/solana/solana.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../core/security/memory.dart';
import '../network/wallet_network.dart';
import '../transfer/transfer_document.dart';
import 'sol_client.dart';

/// Erro de validação, com mensagem pronta para o usuário.
final class SolSendException implements Exception {
  const SolSendException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// O que o assinador frio mostra antes de assinar.
final class SolReview {
  const SolReview({
    required this.from,
    required this.to,
    required this.lamports,
    required this.fee,
  });

  final String from;
  final String to;
  final BigInt lamports;
  final BigInt fee;
}

/// Envio de SOL nativo (fase 1: sem tokens SPL).
abstract final class SolSend {
  /// Taxa base da rede: 5000 lamports por assinatura.
  static final BigInt baseFee = BigInt.from(5000);

  static SolAddress parseAddress(String text) {
    try {
      return SolAddress(text.trim());
    } on Exception {
      throw const SolSendException('Endereço Solana inválido.');
    }
  }

  /// Lado online: monta a mensagem (legacy) com o blockhash mais recente.
  /// [amount] nulo = enviar tudo menos a taxa.
  static Future<SolSignRequest> buildRequest({
    required WalletNetwork network,
    required String from,
    required String to,
    required BigInt? amount,
    required SolClient client,
  }) async {
    final destination = parseAddress(to);
    final owner = parseAddress(from);
    final balance = await client.balance(from);
    final lamports = amount ?? balance - baseFee;
    if (lamports <= BigInt.zero || lamports + baseFee > balance) {
      throw const SolSendException('Saldo insuficiente (valor + taxa).');
    }
    final remaining = balance - lamports - baseFee;
    final rentMinimum = await client.rentExemptMinimum();
    if (remaining > BigInt.zero && remaining < rentMinimum) {
      throw SolSendException(
        'Deixe 0 ou pelo menos ${rentMinimum.toString()} lamports na conta '
        '(mínimo exigido pela rede). Use "enviar tudo".',
      );
    }
    final blockhash = await client.latestBlockhash();
    return SolSignRequest(
      network: network,
      messageBase64: base64Encode(
        transferMessage(
          from: owner,
          to: destination,
          lamports: lamports,
          blockhash: blockhash.blockhash,
        ),
      ),
      from: from,
    );
  }

  /// Mensagem "legacy" de uma transferência do System Program.
  static List<int> transferMessage({
    required SolAddress from,
    required SolAddress to,
    required BigInt lamports,
    required String blockhash,
  }) => SolanaTransaction(
    instructions: [
      SystemProgram.transfer(
        from: from,
        to: to,
        layout: SystemTransferLayout(lamports: lamports),
      ),
    ],
    recentBlockhash: SolAddress(blockhash),
    payerKey: from,
    type: TransactionType.legacy,
  ).serializeMessage();

  /// Lado frio: decodifica a mensagem legacy byte a byte e só aceita uma
  /// transferência simples do System Program, paga pela sua conta.
  static SolReview review(SolSignRequest request) {
    final message = _decode(request.messageBase64);
    final reader = _Reader(message);
    final requiredSignatures = reader.byte();
    if (requiredSignatures & 0x80 != 0) {
      throw const SolSendException('Só transações "legacy" são aceitas.');
    }
    reader.byte(); // readonly assinadas
    reader.byte(); // readonly não assinadas
    final keys = [
      for (var i = reader.shortVec(); i > 0; i--)
        Base58Encoder.encode(reader.take(32)),
    ];
    reader.take(32); // blockhash recente
    if (requiredSignatures != 1 || keys.isEmpty || keys[0] != request.from) {
      throw const SolSendException(
        'A transação precisa ter uma única assinatura: a sua conta.',
      );
    }
    if (reader.shortVec() != 1) {
      throw const SolSendException('Só transferências simples são aceitas.');
    }
    final programIndex = reader.byte();
    final accounts = [
      for (var i = reader.shortVec(); i > 0; i--) reader.byte(),
    ];
    if (programIndex >= keys.length || accounts.any((a) => a >= keys.length)) {
      throw const SolSendException('Mensagem Solana inválida.');
    }
    final program = keys[programIndex];
    final data = reader.take(reader.shortVec());
    if (!reader.done) {
      throw const SolSendException('Mensagem com dados extras.');
    }

    final transferTag =
        data.length == 12 &&
        ByteData.sublistView(
              Uint8List.fromList(data),
            ).getUint32(0, Endian.little) ==
            2;
    if (program != SystemProgramConst.programId.address ||
        !transferTag ||
        accounts.length != 2 ||
        accounts[0] != 0) {
      throw const SolSendException(
        'Por segurança, esta versão só assina transferências simples de SOL.',
      );
    }
    final lamports = BigInt.from(
      ByteData.sublistView(
        Uint8List.fromList(data),
      ).getUint64(4, Endian.little),
    );
    return SolReview(
      from: keys[0],
      to: keys[accounts[1]],
      lamports: lamports,
      fee: baseFee,
    );
  }

  /// Lado frio: assina com a chave de m/44'/501'/0'/0' e monta a transação
  /// final: [1 assinatura] + assinatura + mensagem.
  static SolSignedTransaction sign(SolSignRequest request, SecureKey seed) {
    review(request);
    final message = _decode(request.messageBase64);
    final signature = seed.runUnlockedSync((bytes) {
      final raw = Bip44.fromSeed(
        bytes,
        Bip44Coins.solana,
      ).purpose.coin.account(0).change(Bip44Changes.chainExt).privateKey.raw;
      try {
        final key = SolanaPrivateKey.fromSeed(raw);
        if (key.publicKey().toAddress().address != request.from) {
          throw const SolSendException(
            'O remetente não é desta carteira (seed, respostas ou rede '
            'diferentes).',
          );
        }
        return key.sign(message);
      } finally {
        wipeBytes(raw);
      }
    });
    final tx = <int>[1, ...signature, ...message];
    return SolSignedTransaction(
      network: request.network,
      txBase64: base64Encode(tx),
      signature: Base58Encoder.encode(signature),
    );
  }

  static List<int> _decode(String base64Text) {
    try {
      return base64Decode(base64Text);
    } on FormatException {
      throw const SolSendException('Mensagem Solana inválida.');
    }
  }
}

final class _Reader {
  _Reader(this._bytes);

  final List<int> _bytes;
  int _offset = 0;

  bool get done => _offset == _bytes.length;

  int byte() => take(1).first;

  List<int> take(int n) {
    if (_offset + n > _bytes.length) {
      throw const SolSendException('Mensagem Solana truncada.');
    }
    return _bytes.sublist(_offset, _offset += n);
  }

  /// Inteiro "compact-u16" do formato de transação Solana.
  int shortVec() {
    var value = 0;
    for (var shift = 0; shift < 21; shift += 7) {
      final b = byte();
      value |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) return value;
    }
    throw const SolSendException('Mensagem Solana inválida.');
  }
}
