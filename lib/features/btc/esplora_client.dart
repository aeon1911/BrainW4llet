import '../network/http_json.dart';

/// Estatísticas de um endereço na API Esplora.
final class EsploraAddressStats {
  const EsploraAddressStats({
    required this.txCount,
    required this.confirmedBalance,
    required this.unconfirmedBalance,
  });

  final int txCount;
  final BigInt confirmedBalance;
  final BigInt unconfirmedBalance;

  bool get used => txCount > 0;
}

final class EsploraUtxo {
  const EsploraUtxo({
    required this.txid,
    required this.vout,
    required this.value,
    required this.confirmed,
  });

  final String txid;
  final int vout;
  final BigInt value;
  final bool confirmed;
}

/// Transação como a Esplora devolve, reduzida ao que a carteira usa.
final class EsploraTx {
  const EsploraTx({
    required this.txid,
    required this.confirmed,
    required this.blockTime,
    required this.fee,
    required this.inputs,
    required this.outputs,
  });

  final String txid;
  final bool confirmed;
  final DateTime? blockTime;
  final BigInt fee;

  /// (endereço, valor) de cada entrada gasta.
  final List<(String?, BigInt)> inputs;

  /// (endereço, valor) de cada saída.
  final List<(String?, BigInt)> outputs;
}

/// Taxas recomendadas em sat/vB.
final class BtcFeeRates {
  const BtcFeeRates({
    required this.fastest,
    required this.halfHour,
    required this.hour,
    required this.economy,
  });

  final int fastest;
  final int halfHour;
  final int hour;
  final int economy;
}

/// O que a sincronização e o envio precisam de um servidor UTXO.
abstract interface class UtxoBackend {
  Future<EsploraAddressStats> addressStats(String address);

  Future<List<EsploraUtxo>> utxos(String address);

  Future<List<EsploraTx>> transactions(String address);

  Future<String> rawTransaction(String txid);

  /// Transmite a transação; devolve o txid informado pelo servidor.
  Future<String> broadcast(String txHex);
}

/// Cliente da API Esplora (mempool.space / blockstream.info).
final class EsploraClient implements UtxoBackend {
  EsploraClient(this.baseUrl, this._http);

  final Uri baseUrl;
  final HttpJson _http;

  Uri _url(String path) => Uri.parse('$baseUrl$path');

  @override
  Future<EsploraAddressStats> addressStats(String address) async {
    final json = _map(await _http.getJson(_url('/address/$address')));
    final chain = _map(json['chain_stats']);
    final mempool = _map(json['mempool_stats']);
    BigInt balance(Map<String, Object?> s) =>
        _big(s['funded_txo_sum']) - _big(s['spent_txo_sum']);
    return EsploraAddressStats(
      txCount: _int(chain['tx_count']) + _int(mempool['tx_count']),
      confirmedBalance: balance(chain),
      unconfirmedBalance: balance(mempool),
    );
  }

  @override
  Future<List<EsploraUtxo>> utxos(String address) async {
    final json = await _http.getJson(_url('/address/$address/utxo'));
    return [
      for (final u in _list(json))
        EsploraUtxo(
          txid: _map(u)['txid']! as String,
          vout: _int(_map(u)['vout']),
          value: _big(_map(u)['value']),
          confirmed: _map(_map(u)['status'])['confirmed'] == true,
        ),
    ];
  }

  /// Até 50 transações mais recentes (inclui as da mempool).
  @override
  Future<List<EsploraTx>> transactions(String address) async {
    final json = await _http.getJson(_url('/address/$address/txs'));
    return [for (final t in _list(json)) _tx(_map(t))];
  }

  @override
  Future<String> rawTransaction(String txid) =>
      _http.getText(_url('/tx/$txid/hex'));

  Future<BtcFeeRates> feeRates() async {
    final json = _map(await _http.getJson(_url('/v1/fees/recommended')));
    return BtcFeeRates(
      fastest: _int(json['fastestFee']),
      halfHour: _int(json['halfHourFee']),
      hour: _int(json['hourFee']),
      economy: _int(json['economyFee']),
    );
  }

  @override
  Future<String> broadcast(String txHex) async =>
      (await _http.postText(_url('/tx'), txHex)).trim();

  static EsploraTx _tx(Map<String, Object?> t) {
    final status = _map(t['status']);
    final time = status['block_time'];
    return EsploraTx(
      txid: t['txid']! as String,
      confirmed: status['confirmed'] == true,
      blockTime: time is int
          ? DateTime.fromMillisecondsSinceEpoch(time * 1000)
          : null,
      fee: _big(t['fee']),
      inputs: [
        for (final vin in _list(t['vin']))
          if (_map(vin)['prevout'] case final Map<String, Object?> prev)
            (prev['scriptpubkey_address'] as String?, _big(prev['value'])),
      ],
      outputs: [
        for (final vout in _list(t['vout']))
          (
            _map(vout)['scriptpubkey_address'] as String?,
            _big(_map(vout)['value']),
          ),
      ],
    );
  }

  static Map<String, Object?> _map(Object? v) {
    if (v is Map<String, Object?>) return v;
    throw const NetworkException('Resposta inesperada do servidor Bitcoin.');
  }

  static List<Object?> _list(Object? v) {
    if (v is List) return v;
    throw const NetworkException('Resposta inesperada do servidor Bitcoin.');
  }

  static int _int(Object? v) => v is int ? v : 0;

  static BigInt _big(Object? v) => v is int ? BigInt.from(v) : BigInt.zero;
}
