import '../network/http_json.dart';

/// Uma linha do histórico Solana.
final class SolHistoryEntry {
  const SolHistoryEntry({
    required this.signature,
    required this.delta,
    required this.failed,
    required this.time,
  });

  final String signature;

  /// Variação do saldo em lamports (inclui a taxa quando você pagou).
  final BigInt? delta;
  final bool failed;
  final DateTime? time;
}

/// Blockhash recente: a transação precisa ser transmitida antes de
/// [lastValidBlockHeight] (cerca de 1 minuto).
final class SolBlockhash {
  const SolBlockhash(this.blockhash, this.lastValidBlockHeight);

  final String blockhash;
  final int lastValidBlockHeight;
}

/// Cliente JSON-RPC Solana.
final class SolClient {
  SolClient(this.rpc, this._http);

  final Uri rpc;
  final HttpJson _http;

  static const _confirmed = {'commitment': 'confirmed'};

  Future<BigInt> balance(String address) async {
    final result = await _http.rpc(rpc, 'getBalance', [address, _confirmed]);
    return BigInt.from(_int(result is Map ? result['value'] : null));
  }

  /// Saldo mínimo para uma conta existir (isenta de aluguel).
  Future<BigInt> rentExemptMinimum() async => BigInt.from(
    _int(await _http.rpc(rpc, 'getMinimumBalanceForRentExemption', [0])),
  );

  Future<SolBlockhash> latestBlockhash() async {
    final result = await _http.rpc(rpc, 'getLatestBlockhash', [_confirmed]);
    final value = result is Map ? result['value'] : null;
    if (value is! Map) {
      throw const NetworkException('Resposta inesperada do servidor Solana.');
    }
    return SolBlockhash(
      value['blockhash']! as String,
      _int(value['lastValidBlockHeight']),
    );
  }

  Future<String> broadcast(String txBase64) async =>
      (await _http.rpc(rpc, 'sendTransaction', [
            txBase64,
            {'encoding': 'base64', 'preflightCommitment': 'confirmed'},
          ]))!
          as String;

  /// Últimas [limit] transações, com a variação de saldo de cada uma.
  Future<List<SolHistoryEntry>> history(
    String address, {
    int limit = 15,
  }) async {
    final sigs = await _http.rpc(rpc, 'getSignaturesForAddress', [
      address,
      {'limit': limit, ..._confirmed},
    ]);
    final entries = <SolHistoryEntry>[];
    for (final s in (sigs is List ? sigs : const []).whereType<Map>()) {
      final signature = s['signature']! as String;
      final time = s['blockTime'];
      entries.add(
        SolHistoryEntry(
          signature: signature,
          delta: await _delta(signature, address),
          failed: s['err'] != null,
          time: time is int
              ? DateTime.fromMillisecondsSinceEpoch(time * 1000)
              : null,
        ),
      );
    }
    return entries;
  }

  Future<BigInt?> _delta(String signature, String address) async {
    try {
      final tx = await _http.rpc(rpc, 'getTransaction', [
        signature,
        {
          'encoding': 'json',
          'maxSupportedTransactionVersion': 0,
          ..._confirmed,
        },
      ]);
      if (tx is! Map) return null;
      final keys =
          (((tx['transaction'] as Map?)?['message'] as Map?)?['accountKeys']
              as List?);
      final meta = tx['meta'] as Map?;
      final index = keys?.indexOf(address) ?? -1;
      if (index < 0 || meta == null) return null;
      final pre = (meta['preBalances'] as List)[index] as int;
      final post = (meta['postBalances'] as List)[index] as int;
      return BigInt.from(post - pre);
    } on NetworkException {
      return null;
    }
  }

  static int _int(Object? v) {
    if (v is int) return v;
    throw const NetworkException('Resposta inesperada do servidor Solana.');
  }
}
