import 'dart:convert';
import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:monero_dart/monero_dart.dart';

import '../network/http_json.dart';
import '../network/wallet_network.dart';
import '../transfer/transfer_document.dart';
import 'monero_service.dart';
import 'xmr_keys.dart';

/// Uma saída (moeda) recebida pela carteira.
final class XmrOwnedOutput {
  XmrOwnedOutput({
    required this.outputKey,
    required this.txHash,
    required this.amount,
    required this.height,
    required this.paymentHex,
    this.keyImage,
    this.spent = false,
  });

  /// Chave pública única da saída (hex); identifica a saída.
  final String outputKey;
  final String txHash;
  final BigInt amount;
  final int height;

  /// `MoneroLockedPayment` serializado (hex): o que o assinador precisa.
  final String paymentHex;

  /// Vem do assinador frio; com ela dá para saber se a saída foi gasta.
  String? keyImage;
  bool spent;

  Map<String, Object?> toJson() => {
    'outputKey': outputKey,
    'txHash': txHash,
    'amount': amount.toString(),
    'height': height,
    'payment': paymentHex,
    'keyImage': keyImage,
    'spent': spent,
  };

  static XmrOwnedOutput fromJson(Map<String, Object?> json) => XmrOwnedOutput(
    outputKey: json['outputKey']! as String,
    txHash: json['txHash']! as String,
    amount: BigInt.parse(json['amount']! as String),
    height: json['height']! as int,
    paymentHex: json['payment']! as String,
    keyImage: json['keyImage'] as String?,
    spent: json['spent'] == true,
  );
}

/// Progresso da varredura, guardado no disco da máquina online. Não contém
/// nenhuma chave: só o que a view key já revela (entradas e valores).
final class XmrCache {
  XmrCache({
    required this.address,
    required this.network,
    required this.restoreHeight,
    required this.scannedHeight,
    List<XmrOwnedOutput>? outputs,
  }) : outputs = outputs ?? [];

  static const int version = 1;

  final String address;
  final WalletNetwork network;
  int restoreHeight;

  /// Última altura já varrida (inclusive).
  int scannedHeight;
  final List<XmrOwnedOutput> outputs;

  Map<String, Object?> toJson() => {
    'version': version,
    'address': address,
    'network': network.name,
    'restoreHeight': restoreHeight,
    'scannedHeight': scannedHeight,
    'outputs': [for (final o in outputs) o.toJson()],
  };

  static XmrCache fromJson(Map<String, Object?> json) => XmrCache(
    address: json['address']! as String,
    network: WalletNetwork.parse(json['network']),
    restoreHeight: json['restoreHeight']! as int,
    scannedHeight: json['scannedHeight']! as int,
    outputs: [
      for (final o in (json['outputs']! as List).cast<Map<String, Object?>>())
        XmrOwnedOutput.fromJson(o),
    ],
  );
}

/// Grava/lê o cache num diretório da máquina online.
final class XmrCacheStore {
  XmrCacheStore(this.directory);

  final Directory directory;

  File _file(String address) {
    final id = BytesUtils.toHexString(
      QuickCrypto.sha256Hash(utf8.encode(address)).sublist(0, 8),
    );
    return File('${directory.path}/xmr-cache-$id.json');
  }

  Future<XmrCache?> load(String address) async {
    final file = _file(address);
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      final cache = XmrCache.fromJson(json as Map<String, Object?>);
      return cache.address == address ? cache : null;
    } on Object {
      return null; // cache corrompido: varre de novo
    }
  }

  Future<void> save(XmrCache cache) async {
    await directory.create(recursive: true);
    final file = _file(cache.address);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(cache.toJson()));
    await tmp.rename(file.path);
  }

  Future<void> delete(String address) async {
    final file = _file(address);
    if (await file.exists()) await file.delete();
  }
}

/// Saldo e estado do Monero após sincronizar.
final class XmrBalance {
  const XmrBalance({
    required this.unlocked,
    required this.locked,
    required this.unknownSpentState,
  });

  /// Pode ser gasto (10 confirmações).
  final BigInt unlocked;

  /// Ainda bloqueado (menos de 10 confirmações).
  final BigInt locked;

  /// Saídas sem key image: se você gastou fora deste app, o saldo pode estar
  /// maior que o real até sincronizar as key images.
  final int unknownSpentState;
}

/// Carteira Monero online (somente leitura): varre a blockchain com a view
/// key, guarda o progresso e monta pedidos de envio. Nunca tem a chave de
/// gasto.
final class XmrWatcher {
  XmrWatcher({
    required this.address,
    required this.viewKeyHex,
    required this.network,
    required this.nodeUrl,
    required this.store,
    HttpJson? http,
  }) : _http = http ?? HttpJson(timeout: const Duration(seconds: 90)) {
    _account = XmrKeys.keys(
      XmrKeys.watchAccount(
        address: address,
        viewKeyHex: viewKeyHex,
        network: network,
      ),
      network,
    );
    _provider = MoneroProvider(MoneroDaemonService(nodeUrl, _http));
    _api = MoneroApi(_provider);
  }

  /// Confirmações para uma saída poder ser gasta.
  static const int unlockConfirmations = 10;

  /// Tempo médio de bloco do Monero.
  static const Duration blockTime = Duration(minutes: 2);

  /// Margem ao estimar a altura de início pela data (1 dia de blocos).
  static const int restoreMarginBlocks = 720;

  final String address;
  final String viewKeyHex;
  final WalletNetwork network;
  final String nodeUrl;
  final XmrCacheStore store;
  final HttpJson _http;
  late final MoneroAccountKeys _account;
  late final MoneroProvider _provider;
  late final MoneroApi _api;

  XmrCache? cache;
  int? tipHeight;

  void close() => _http.close();

  Future<int> currentHeight() async =>
      tipHeight = (await _api.provider.currentHeight()).height;

  /// Altura estimada a partir de uma data (com margem de 1 dia antes).
  Future<int> heightForDate(DateTime date) async {
    final tip = await currentHeight();
    final elapsed = DateTime.now().toUtc().difference(date.toUtc());
    final blocks = elapsed.inSeconds ~/ blockTime.inSeconds;
    final height = tip - blocks - restoreMarginBlocks;
    return height < 1 ? 1 : height;
  }

  /// Carrega o cache do disco ou cria um novo a partir de [startDate].
  Future<XmrCache> open(DateTime startDate) async {
    final loaded = await store.load(address);
    if (loaded != null && loaded.network == network) return cache = loaded;
    final start = await heightForDate(startDate);
    return cache = XmrCache(
      address: address,
      network: network,
      restoreHeight: start,
      scannedHeight: start - 1,
    );
  }

  /// Recomeça a varredura a partir de outra data (descarta o cache).
  Future<XmrCache> rescanFrom(DateTime startDate) async {
    await store.delete(address);
    cache = null;
    return open(startDate);
  }

  /// Varre do último ponto até o topo. [onProgress] recebe (atual, alvo).
  Future<void> sync({
    void Function(int current, int target)? onProgress,
  }) async {
    final state = cache!;
    final tip = await currentHeight();
    final end = tip - 1;
    final known = {for (final o in state.outputs) o.keyImage: o}..remove(null);
    final processor = DefaultMoneroBlockProcessor(
      provider: _provider,
      config: BlockProcessorConfig(
        network: XmrKeys.networkFor(network),
        unlocker: DefaultMoneroOutputUnlocker(accounts: [_account]),
      ),
    );

    final foundTxs = <String, int>{}; // txHash → altura
    var processed = 0;
    if (state.scannedHeight < end) {
      await for (final block in processor.scanBlock(
        state.scannedHeight + 1,
        end,
      )) {
        for (final tx in block.txes) {
          if (tx.unlockedOutputs.isNotEmpty) {
            foundTxs[tx.txHash] = block.blockHeight;
          }
        }
        // Gastos detectados durante a varredura (key images já conhecidas).
        for (final image in block.keyImages()) {
          known[BytesUtils.toHexString(image.keyImage)]?.spent = true;
        }
        state.scannedHeight = block.blockHeight;
        onProgress?.call(block.blockHeight, end);
        if (++processed % 200 == 0) {
          await _addOutputs(state, foundTxs);
          foundTxs.clear();
          await store.save(state);
        }
      }
    }
    await _addOutputs(state, foundTxs);
    await refreshSpent();
    await store.save(state);
  }

  /// Busca as transações que contêm saídas nossas e guarda cada saída.
  Future<void> _addOutputs(XmrCache state, Map<String, int> txs) async {
    final existing = {for (final o in state.outputs) o.outputKey};
    for (final MapEntry(key: txHash, value: height) in txs.entries) {
      final payments = await _api.watchTxHashesPayments(
        txHashes: [txHash],
        account: _account,
      );
      for (final payment in payments) {
        final key = BytesUtils.toHexString(payment.output.outputPublicKey);
        if (!existing.add(key)) continue;
        state.outputs.add(
          XmrOwnedOutput(
            outputKey: key,
            txHash: txHash,
            amount: payment.output.amount,
            height: height,
            paymentHex: BytesUtils.toHexString(payment.serialize()),
          ),
        );
      }
    }
  }

  /// Pergunta ao nó quais key images conhecidas já foram gastas.
  Future<void> refreshSpent() async {
    final pending = [
      for (final o in cache!.outputs)
        if (o.keyImage != null && !o.spent) o,
    ];
    if (pending.isEmpty) return;
    final result = await _provider.request(
      DaemonRequestIsKeyImageSpent([for (final o in pending) o.keyImage!]),
    );
    for (var i = 0; i < pending.length; i++) {
      if (result.spentStatus[i] != DaemonKeyImageSpentStatus.unspent) {
        pending[i].spent = true;
      }
    }
  }

  /// Importa key images vindas do assinador frio.
  Future<void> importKeyImages(Map<String, String> keyImages) async {
    for (final o in cache!.outputs) {
      final image = keyImages[o.outputKey];
      if (image != null) o.keyImage = image;
    }
    await refreshSpent();
    await store.save(cache!);
  }

  XmrBalance balance() {
    final tip = tipHeight ?? cache!.scannedHeight;
    var unlocked = BigInt.zero;
    var locked = BigInt.zero;
    var unknown = 0;
    for (final o in cache!.outputs.where((o) => !o.spent)) {
      if (o.keyImage == null) unknown++;
      if (o.height + unlockConfirmations <= tip) {
        unlocked += o.amount;
      } else {
        locked += o.amount;
      }
    }
    return XmrBalance(
      unlocked: unlocked,
      locked: locked,
      unknownSpentState: unknown,
    );
  }

  List<XmrOwnedOutput> spendable() {
    final tip = tipHeight ?? cache!.scannedHeight;
    return [
      for (final o in cache!.outputs)
        if (!o.spent && o.height + unlockConfirmations <= tip) o,
    ]..sort((a, b) => b.amount.compareTo(a.amount));
  }

  /// Pedido de key images para o assinador (descobrir gastos).
  XmrKeyImageRequest keyImageRequest() => XmrKeyImageRequest(
    network: network,
    knownOutputs: [for (final o in cache!.outputs) o.paymentHex],
  );

  /// Monta o pedido de assinatura: escolhe as moedas, busca os decoys no nó
  /// e a taxa atual. [amount] nulo = enviar tudo.
  Future<XmrSignRequest> buildRequest({
    required String destination,
    required BigInt? amount,
  }) async {
    final target = MoneroAddress(destination.trim());
    if (target.network != XmrKeys.networkFor(network)) {
      throw const FormatException('Endereço Monero de outra rede.');
    }
    final fee = await _api.provider.baseFee();
    final available = spendable();
    if (available.isEmpty) {
      throw const FormatException('Não há saldo desbloqueado para enviar.');
    }
    final List<XmrOwnedOutput> chosen;
    if (amount == null) {
      chosen = available;
    } else {
      // Limite superior da taxa: ~3 KB por entrada + 2 KB, pela taxa mais alta.
      final fees = fee.fees;
      final perByte = fees != null && fees.isNotEmpty ? fees.last : fee.fee;
      chosen = [];
      var total = BigInt.zero;
      for (final o in available) {
        chosen.add(o);
        total += o.amount;
        final maxFee = perByte * BigInt.from(3000 * chosen.length + 2000);
        if (total >= amount + maxFee) break;
      }
      final maxFee = perByte * BigInt.from(3000 * chosen.length + 2000);
      if (total < amount + maxFee) {
        throw const FormatException(
          'Saldo desbloqueado insuficiente (valor + taxa).',
        );
      }
    }
    final payments = [
      for (final o in chosen)
        MoneroLockedPayment.deserialize(BytesUtils.fromHexString(o.paymentHex)),
    ];
    final spendables = await _api.provider.generatePaymentOutputs(
      payments: payments,
    );
    return XmrSignRequest(
      network: network,
      sources: [
        for (final s in spendables) BytesUtils.toHexString(s.serialize()),
      ],
      knownOutputs: [for (final o in cache!.outputs) o.paymentHex],
      destinations: [(address: target.address, amount: amount ?? BigInt.zero)],
      feeEstimate: {
        'fee': fee.fee.toString(),
        'fees': [for (final f in fee.fees ?? <BigInt>[]) f.toString()],
        'quantization_mask': fee.quantizationMask.toString(),
        'status': 'OK',
        'untrusted': false,
      },
    );
  }

  /// Transmite a transação assinada e importa as key images devolvidas.
  Future<String> broadcast(XmrSignedTransaction signed) async {
    final result = await _provider.request(
      DaemonRequestSendRawTransaction(txAsHex: signed.txHex),
    );
    if (result.status != 'OK' || result.notRelayed == true) {
      throw NetworkException(
        'O nó recusou a transação: ${result.reason.isEmpty ? result.status : result.reason}',
      );
    }
    await importKeyImages(signed.keyImages);
    return signed.txHash;
  }
}
