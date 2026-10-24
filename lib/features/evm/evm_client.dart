import '../network/http_json.dart';

/// Uma linha do histórico (fonte: Blockscout).
final class EvmHistoryEntry {
  const EvmHistoryEntry({
    required this.hash,
    required this.delta,
    required this.fee,
    required this.failed,
    required this.time,
  });

  final String hash;

  /// Positivo = recebido; negativo = enviado (inclui a taxa).
  final BigInt delta;
  final BigInt fee;
  final bool failed;
  final DateTime? time;
}

/// Taxas EIP-1559 sugeridas, em wei por unidade de gás.
final class EvmFees {
  const EvmFees({required this.maxFeePerGas, required this.maxPriorityFee});

  final BigInt maxFeePerGas;
  final BigInt maxPriorityFee;
}

/// Cliente JSON-RPC Ethereum + API Blockscout para o histórico.
final class EvmClient {
  EvmClient({
    required this.rpc,
    required this.blockscout,
    required this.chainId,
    required HttpJson http,
  }) : _http = http;

  final Uri rpc;
  final Uri blockscout;
  final int chainId;
  final HttpJson _http;

  Future<BigInt> balance(String address) async =>
      _hex(await _http.rpc(rpc, 'eth_getBalance', [address, 'latest']));

  Future<int> nonce(String address) async => _hex(
    await _http.rpc(rpc, 'eth_getTransactionCount', [address, 'pending']),
  ).toInt();

  /// Confere que o servidor está na rede esperada (evita assinar para a
  /// rede errada por um RPC mal configurado).
  Future<void> checkChain() async {
    final remote = _hex(await _http.rpc(rpc, 'eth_chainId')).toInt();
    if (remote != chainId) {
      throw NetworkException(
        'O servidor RPC está na rede $remote, esperado $chainId.',
      );
    }
  }

  /// maxFee = 2 × baseFee + gorjeta: cobre alguns blocos de alta.
  Future<EvmFees> fees() async {
    final block = await _http.rpc(rpc, 'eth_getBlockByNumber', [
      'latest',
      false,
    ]);
    final baseFee = block is Map ? _hex(block['baseFeePerGas']) : BigInt.zero;
    final tip = _hex(await _http.rpc(rpc, 'eth_maxPriorityFeePerGas'));
    return EvmFees(
      maxFeePerGas: baseFee * BigInt.two + tip,
      maxPriorityFee: tip,
    );
  }

  Future<String> broadcast(String signedTxHex) async =>
      (await _http.rpc(rpc, 'eth_sendRawTransaction', [signedTxHex]))!
          as String;

  Future<List<EvmHistoryEntry>> history(String address) async {
    final json = await _http.getJson(
      Uri.parse('$blockscout/addresses/$address/transactions'),
    );
    final items = json is Map && json['items'] is List
        ? json['items'] as List
        : const [];
    final me = address.toLowerCase();
    return [
      for (final item in items.whereType<Map<String, Object?>>())
        _entry(item, me),
    ];
  }

  static EvmHistoryEntry _entry(Map<String, Object?> item, String me) {
    String? hashOf(Object? party) =>
        party is Map ? (party['hash'] as String?)?.toLowerCase() : null;
    final value = BigInt.tryParse('${item['value']}') ?? BigInt.zero;
    final fee = item['fee'] is Map
        ? BigInt.tryParse('${(item['fee']! as Map)['value']}') ?? BigInt.zero
        : BigInt.zero;
    final outgoing = hashOf(item['from']) == me;
    final incoming = hashOf(item['to']) == me;
    var delta = BigInt.zero;
    if (incoming) delta += value;
    if (outgoing) delta -= value + fee;
    final status = item['status'];
    return EvmHistoryEntry(
      hash: item['hash']! as String,
      delta: delta,
      fee: outgoing ? fee : BigInt.zero,
      failed: status == 'error',
      time: DateTime.tryParse('${item['timestamp']}'),
    );
  }

  static BigInt _hex(Object? value) {
    if (value is! String || !value.startsWith('0x')) {
      throw const NetworkException('Resposta inesperada do servidor Ethereum.');
    }
    return value.length == 2
        ? BigInt.zero
        : BigInt.parse(value.substring(2), radix: 16);
  }
}
