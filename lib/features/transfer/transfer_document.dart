import 'dart:convert';

import '../network/wallet_network.dart';

/// Arquivo trocado entre a carteira online e o assinador frio (pendrive),
/// como no Electrum. Só contém dados que podem cair em mãos erradas sem
/// permitir roubo: transação não assinada → transação assinada.
///
/// O assinador NUNCA confia nos metadados para mostrar o que vai assinar:
/// destino, valores e taxa são recalculados a partir da própria transação.
sealed class TransferDocument {
  const TransferDocument(this.network);

  static const String format = 'brainw4llet-transfer';
  static const int version = 1;

  final WalletNetwork network;

  String get kind;

  /// Nome sugerido para o arquivo.
  String get suggestedFileName;

  Map<String, Object?> payload();

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'format': format,
    'version': version,
    'kind': kind,
    'network': network.name,
    ...payload(),
  });

  static TransferDocument decode(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException('O arquivo não é um JSON válido.');
    }
    if (decoded is! Map<String, Object?> || decoded['format'] != format) {
      throw const FormatException(
        'Não é um arquivo de transferência BrainW4llet.',
      );
    }
    final json = decoded;
    if (json['version'] != version) {
      throw const FormatException('Versão do arquivo não suportada.');
    }
    final network = WalletNetwork.parse(json['network']);
    String str(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Campo "$key" ausente.');
      }
      return value;
    }

    return switch (json['kind']) {
      BtcSignRequest.kindName => BtcSignRequest(
        network: network,
        psbtBase64: str('psbt'),
        inputPaths: _paths(json['inputPaths']),
        changePath: json['changePath'] == null
            ? null
            : _path(json['changePath']),
      ),
      BtcSignedTransaction.kindName => BtcSignedTransaction(
        network: network,
        txHex: str('txHex'),
        txid: str('txid'),
      ),
      EvmSignRequest.kindName => EvmSignRequest(
        network: network,
        unsignedTxHex: str('unsignedTx'),
        from: str('from'),
      ),
      EvmSignedTransaction.kindName => EvmSignedTransaction(
        network: network,
        signedTxHex: str('signedTx'),
        txHash: str('txHash'),
      ),
      SolSignRequest.kindName => SolSignRequest(
        network: network,
        messageBase64: str('message'),
        from: str('from'),
      ),
      SolSignedTransaction.kindName => SolSignedTransaction(
        network: network,
        txBase64: str('tx'),
        signature: str('signature'),
      ),
      _ => throw const FormatException('Tipo de arquivo desconhecido.'),
    };
  }

  static List<BtcPath> _paths(Object? value) {
    if (value is! List) throw const FormatException('inputPaths inválido.');
    return [for (final p in value) _path(p)];
  }

  static BtcPath _path(Object? value) {
    if (value is List &&
        value.length == 2 &&
        value[0] is int &&
        value[1] is int &&
        (value[0] == 0 || value[0] == 1) &&
        (value[1] as int) >= 0) {
      return (chain: value[0] as int, index: value[1] as int);
    }
    throw const FormatException('Caminho de derivação inválido.');
  }
}

/// Cadeia (0 = receber, 1 = troco) e índice dentro da conta BIP-84.
typedef BtcPath = ({int chain, int index});

final class BtcSignRequest extends TransferDocument {
  const BtcSignRequest({
    required WalletNetwork network,
    required this.psbtBase64,
    required this.inputPaths,
    this.changePath,
  }) : super(network);

  static const String kindName = 'btc-sign-request';

  /// PSBT (BIP-174), o mesmo formato do Electrum/Sparrow.
  final String psbtBase64;

  /// Caminho de cada entrada, na ordem das entradas do PSBT.
  final List<BtcPath> inputPaths;

  /// Caminho do troco, se houver; o assinador confere que é mesmo seu.
  final BtcPath? changePath;

  @override
  String get kind => kindName;

  @override
  String get suggestedFileName => 'btc-para-assinar.json';

  @override
  Map<String, Object?> payload() => {
    'psbt': psbtBase64,
    'inputPaths': [
      for (final p in inputPaths) [p.chain, p.index],
    ],
    'changePath': changePath == null
        ? null
        : [changePath!.chain, changePath!.index],
  };
}

final class BtcSignedTransaction extends TransferDocument {
  const BtcSignedTransaction({
    required WalletNetwork network,
    required this.txHex,
    required this.txid,
  }) : super(network);

  static const String kindName = 'btc-signed';

  final String txHex;
  final String txid;

  @override
  String get kind => kindName;

  @override
  String get suggestedFileName => 'btc-assinada.json';

  @override
  Map<String, Object?> payload() => {'txHex': txHex, 'txid': txid};
}

final class EvmSignRequest extends TransferDocument {
  const EvmSignRequest({
    required WalletNetwork network,
    required this.unsignedTxHex,
    required this.from,
  }) : super(network);

  static const String kindName = 'evm-sign-request';

  /// Transação EIP-1559 serializada sem assinatura (inclui o chainId).
  final String unsignedTxHex;
  final String from;

  @override
  String get kind => kindName;

  @override
  String get suggestedFileName => 'eth-para-assinar.json';

  @override
  Map<String, Object?> payload() => {'unsignedTx': unsignedTxHex, 'from': from};
}

final class EvmSignedTransaction extends TransferDocument {
  const EvmSignedTransaction({
    required WalletNetwork network,
    required this.signedTxHex,
    required this.txHash,
  }) : super(network);

  static const String kindName = 'evm-signed';

  final String signedTxHex;
  final String txHash;

  @override
  String get kind => kindName;

  @override
  String get suggestedFileName => 'eth-assinada.json';

  @override
  Map<String, Object?> payload() => {'signedTx': signedTxHex, 'txHash': txHash};
}

final class SolSignRequest extends TransferDocument {
  const SolSignRequest({
    required WalletNetwork network,
    required this.messageBase64,
    required this.from,
  }) : super(network);

  static const String kindName = 'sol-sign-request';

  /// Mensagem da transação (inclui o blockhash recente, válido ~1 minuto).
  final String messageBase64;
  final String from;

  @override
  String get kind => kindName;

  @override
  String get suggestedFileName => 'sol-para-assinar.json';

  @override
  Map<String, Object?> payload() => {'message': messageBase64, 'from': from};
}

final class SolSignedTransaction extends TransferDocument {
  const SolSignedTransaction({
    required WalletNetwork network,
    required this.txBase64,
    required this.signature,
  }) : super(network);

  static const String kindName = 'sol-signed';

  final String txBase64;
  final String signature;

  @override
  String get kind => kindName;

  @override
  String get suggestedFileName => 'sol-assinada.json';

  @override
  Map<String, Object?> payload() => {'tx': txBase64, 'signature': signature};
}
