import 'dart:convert';

import '../btc/btc_account.dart';
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
      final String kind when UtxoSignRequest.coinOfKind(kind) != null =>
        UtxoSignRequest(
          coin: UtxoSignRequest.coinOfKind(kind)!,
          network: network,
          psbtBase64: str('psbt'),
          inputPaths: _paths(json['inputPaths']),
          changePath: json['changePath'] == null
              ? null
              : _path(json['changePath']),
        ),
      final String kind when UtxoSignedTransaction.coinOfKind(kind) != null =>
        UtxoSignedTransaction(
          coin: UtxoSignedTransaction.coinOfKind(kind)!,
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
      XmrSignRequest.kindName => XmrSignRequest(
        network: network,
        sources: _strings(json['sources']),
        knownOutputs: _strings(json['knownOutputs']),
        destinations: _destinations(json['destinations']),
        feeEstimate: _object(json['feeEstimate']),
      ),
      XmrSignedTransaction.kindName => XmrSignedTransaction(
        network: network,
        txHex: str('txHex'),
        txHash: str('txHash'),
        keyImages: _stringMap(json['keyImages']),
      ),
      XmrKeyImageRequest.kindName => XmrKeyImageRequest(
        network: network,
        knownOutputs: _strings(json['knownOutputs']),
      ),
      XmrKeyImages.kindName => XmrKeyImages(
        network: network,
        keyImages: _stringMap(json['keyImages']),
      ),
      _ => throw const FormatException('Tipo de arquivo desconhecido.'),
    };
  }

  static List<String> _strings(Object? value) {
    if (value is List && value.every((e) => e is String)) {
      return value.cast<String>();
    }
    throw const FormatException('Lista inválida no arquivo.');
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is Map && value.values.every((e) => e is String)) {
      return value.map((k, v) => MapEntry('$k', v as String));
    }
    throw const FormatException('Mapa inválido no arquivo.');
  }

  static Map<String, Object?> _object(Object? value) {
    if (value is Map<String, Object?>) return value;
    throw const FormatException('Objeto inválido no arquivo.');
  }

  static List<XmrDestination> _destinations(Object? value) {
    if (value is! List || value.isEmpty) {
      throw const FormatException('Destinos ausentes.');
    }
    return [
      for (final d in value)
        if (d is Map &&
            d['address'] is String &&
            BigInt.tryParse('${d['amount']}') != null)
          (
            address: d['address'] as String,
            amount: BigInt.parse('${d['amount']}'),
          )
        else
          throw const FormatException('Destino inválido.'),
    ];
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

final class UtxoSignRequest extends TransferDocument {
  const UtxoSignRequest({
    this.coin = UtxoCoin.bitcoin,
    required WalletNetwork network,
    required this.psbtBase64,
    required this.inputPaths,
    this.changePath,
  }) : super(network);

  static String kindFor(UtxoCoin coin) => '${coin.fileTag}-sign-request';

  static UtxoCoin? coinOfKind(String kind) =>
      UtxoCoin.values.where((c) => kindFor(c) == kind).firstOrNull;

  final UtxoCoin coin;

  /// PSBT (BIP-174), o mesmo formato do Electrum/Sparrow.
  final String psbtBase64;

  /// Caminho de cada entrada, na ordem das entradas do PSBT.
  final List<BtcPath> inputPaths;

  /// Caminho do troco, se houver; o assinador confere que é mesmo seu.
  final BtcPath? changePath;

  @override
  String get kind => kindFor(coin);

  @override
  String get suggestedFileName => '${coin.fileTag}-para-assinar.json';

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

final class UtxoSignedTransaction extends TransferDocument {
  const UtxoSignedTransaction({
    this.coin = UtxoCoin.bitcoin,
    required WalletNetwork network,
    required this.txHex,
    required this.txid,
  }) : super(network);

  static String kindFor(UtxoCoin coin) => '${coin.fileTag}-signed';

  static UtxoCoin? coinOfKind(String kind) =>
      UtxoCoin.values.where((c) => kindFor(c) == kind).firstOrNull;

  final UtxoCoin coin;
  final String txHex;
  final String txid;

  @override
  String get kind => kindFor(coin);

  @override
  String get suggestedFileName => '${coin.fileTag}-assinada.json';

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

/// Destino de um envio Monero (valor em piconeros).
typedef XmrDestination = ({String address, BigInt amount});

/// Pedido de assinatura Monero: as entradas já vêm com o anel de decoys
/// escolhido pela carteira online (que não tem a chave de gasto).
final class XmrSignRequest extends TransferDocument {
  const XmrSignRequest({
    required WalletNetwork network,
    required this.sources,
    required this.knownOutputs,
    required this.destinations,
    required this.feeEstimate,
  }) : super(network);

  static const String kindName = 'xmr-sign-request';

  /// `SpendablePayment<MoneroLockedPayment>` serializados (hex): saída real
  /// + anel de decoys.
  final List<String> sources;

  /// Todas as saídas conhecidas da carteira (`MoneroLockedPayment` em hex),
  /// para o assinador devolver as key images e a online saber o que gastou.
  final List<String> knownOutputs;

  final List<XmrDestination> destinations;

  /// Resposta de `get_fee_estimate` do nó (taxa por byte e máscara).
  final Map<String, Object?> feeEstimate;

  @override
  String get kind => kindName;

  @override
  String get suggestedFileName => 'xmr-para-assinar.json';

  @override
  Map<String, Object?> payload() => {
    'sources': sources,
    'knownOutputs': knownOutputs,
    'destinations': [
      for (final d in destinations)
        {'address': d.address, 'amount': d.amount.toString()},
    ],
    'feeEstimate': feeEstimate,
  };
}

final class XmrSignedTransaction extends TransferDocument {
  const XmrSignedTransaction({
    required WalletNetwork network,
    required this.txHex,
    required this.txHash,
    required this.keyImages,
  }) : super(network);

  static const String kindName = 'xmr-signed';

  final String txHex;
  final String txHash;

  /// Chave pública da saída (hex) → key image (hex), de todas as saídas
  /// conhecidas. Não permite gastar; só revela quais foram gastas.
  final Map<String, String> keyImages;

  @override
  String get kind => kindName;

  @override
  String get suggestedFileName => 'xmr-assinada.json';

  @override
  Map<String, Object?> payload() => {
    'txHex': txHex,
    'txHash': txHash,
    'keyImages': keyImages,
  };
}

/// Pedido de key images (sem envio), para a carteira online descobrir quais
/// saídas já foram gastas (ex.: depois de perder o cache).
final class XmrKeyImageRequest extends TransferDocument {
  const XmrKeyImageRequest({
    required WalletNetwork network,
    required this.knownOutputs,
  }) : super(network);

  static const String kindName = 'xmr-key-image-request';

  final List<String> knownOutputs;

  @override
  String get kind => kindName;

  @override
  String get suggestedFileName => 'xmr-pedido-key-images.json';

  @override
  Map<String, Object?> payload() => {'knownOutputs': knownOutputs};
}

final class XmrKeyImages extends TransferDocument {
  const XmrKeyImages({required WalletNetwork network, required this.keyImages})
    : super(network);

  static const String kindName = 'xmr-key-images';

  final Map<String, String> keyImages;

  @override
  String get kind => kindName;

  @override
  String get suggestedFileName => 'xmr-key-images.json';

  @override
  Map<String, Object?> payload() => {'keyImages': keyImages};
}
