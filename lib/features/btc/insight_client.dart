import '../network/http_json.dart';
import 'esplora_client.dart';

/// Cliente da API Insight (insight.dash.org, mantido pela Dash Core Group).
/// Devolve os mesmos modelos do cliente Esplora para reaproveitar a
/// sincronização e o envio.
final class InsightClient implements UtxoBackend {
  InsightClient(this.baseUrl, this._http);

  final Uri baseUrl;
  final HttpJson _http;

  Uri _url(String path) => Uri.parse('$baseUrl$path');

  @override
  Future<EsploraAddressStats> addressStats(String address) async {
    final json = _map(await _http.getJson(_url('/addr/$address?noTxList=1')));
    return EsploraAddressStats(
      txCount:
          _int(json['txApperances']) + _int(json['unconfirmedTxApperances']),
      confirmedBalance: _big(json['balanceSat']),
      unconfirmedBalance: _big(json['unconfirmedBalanceSat']),
    );
  }

  @override
  Future<List<EsploraUtxo>> utxos(String address) async {
    final json = await _http.getJson(_url('/addrs/$address/utxo'));
    return [
      for (final u in _list(json).map(_map))
        EsploraUtxo(
          txid: u['txid']! as String,
          vout: _int(u['vout']),
          value: _big(u['satoshis']),
          confirmed: _int(u['confirmations']) > 0,
        ),
    ];
  }

  @override
  Future<List<EsploraTx>> transactions(String address) async {
    final json = _map(
      await _http.getJson(_url('/addrs/$address/txs?from=0&to=50')),
    );
    return [for (final t in _list(json['items']).map(_map)) _tx(t)];
  }

  @override
  Future<String> rawTransaction(String txid) async {
    final json = _map(await _http.getJson(_url('/rawtx/$txid')));
    return json['rawtx']! as String;
  }

  @override
  Future<String> broadcast(String txHex) async {
    final json = _map(await _http.postJson(_url('/tx/send'), {'rawtx': txHex}));
    return json['txid']! as String;
  }

  static EsploraTx _tx(Map<String, Object?> t) {
    final time = t['blocktime'] ?? t['time'];
    final confirmations = _int(t['confirmations']);
    return EsploraTx(
      txid: t['txid']! as String,
      confirmed: confirmations > 0,
      blockTime: confirmations > 0 && time is int
          ? DateTime.fromMillisecondsSinceEpoch(time * 1000)
          : null,
      fee: _duffs(t['fees']),
      inputs: [
        for (final vin in _list(t['vin']).map(_map))
          (vin['addr'] as String?, _big(vin['valueSat'])),
      ],
      outputs: [
        for (final vout in _list(t['vout']).map(_map))
          (
            (_map(vout['scriptPubKey'])['addresses'] as List?)?.firstOrNull
                as String?,
            _duffs(vout['value']),
          ),
      ],
    );
  }

  /// Converte "0.00117200" (DASH em texto) para duffs sem ponto flutuante.
  static BigInt _duffs(Object? value) {
    final text = '$value';
    final parts = text.split('.');
    final fraction = (parts.length > 1 ? parts[1] : '').padRight(8, '0');
    return BigInt.tryParse(parts[0] + fraction.substring(0, 8)) ?? BigInt.zero;
  }

  static Map<String, Object?> _map(Object? v) {
    if (v is Map<String, Object?>) return v;
    throw const NetworkException('Resposta inesperada do servidor Dash.');
  }

  static List<Object?> _list(Object? v) {
    if (v is List) return v;
    throw const NetworkException('Resposta inesperada do servidor Dash.');
  }

  static int _int(Object? v) => v is int ? v : 0;

  static BigInt _big(Object? v) => v is int ? BigInt.from(v) : BigInt.zero;
}
