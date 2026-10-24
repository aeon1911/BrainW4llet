import '../transfer/transfer_document.dart';
import 'btc_account.dart';
import 'esplora_client.dart';

/// UTXO da carteira com o caminho de derivação do endereço dono.
final class BtcOwnedUtxo {
  const BtcOwnedUtxo({
    required this.txid,
    required this.vout,
    required this.value,
    required this.confirmed,
    required this.path,
    required this.address,
  });

  final String txid;
  final int vout;
  final BigInt value;
  final bool confirmed;
  final BtcPath path;
  final String address;
}

/// Uma linha do histórico, já com o efeito líquido na carteira.
final class BtcHistoryEntry {
  const BtcHistoryEntry({
    required this.txid,
    required this.delta,
    required this.fee,
    required this.confirmed,
    required this.time,
  });

  final String txid;

  /// Positivo = recebido; negativo = enviado (inclui a taxa).
  final BigInt delta;
  final BigInt fee;
  final bool confirmed;
  final DateTime? time;
}

/// Retrato da carteira Bitcoin após sincronizar com o servidor.
final class BtcWalletState {
  const BtcWalletState({
    required this.confirmedBalance,
    required this.unconfirmedBalance,
    required this.utxos,
    required this.history,
    required this.nextReceive,
    required this.nextChange,
  });

  final BigInt confirmedBalance;
  final BigInt unconfirmedBalance;
  final List<BtcOwnedUtxo> utxos;
  final List<BtcHistoryEntry> history;
  final BtcPath nextReceive;
  final BtcPath nextChange;

  BigInt get totalBalance => confirmedBalance + unconfirmedBalance;
}

/// Descobre os endereços usados como o Electrum: varre cada cadeia até
/// encontrar [gapLimit] endereços seguidos sem nenhuma transação.
final class BtcSync {
  BtcSync(this.account, this.client, {this.gapLimit = 20, this.batch = 4});

  final BtcAccount account;
  final EsploraClient client;
  final int gapLimit;
  final int batch;

  Future<BtcWalletState> run() async {
    final used = <String, BtcPath>{};
    final stats = <String, EsploraAddressStats>{};
    final next = <int, int>{};

    for (final chain in [BtcAccount.receiveChain, BtcAccount.changeChain]) {
      var index = 0;
      var gap = 0;
      int? firstUnused;
      while (gap < gapLimit) {
        final addresses = [
          for (var i = index; i < index + batch; i++) account.address(chain, i),
        ];
        final results = await Future.wait(addresses.map(client.addressStats));
        for (var i = 0; i < addresses.length; i++) {
          if (results[i].used) {
            used[addresses[i]] = (chain: chain, index: index + i);
            stats[addresses[i]] = results[i];
            gap = 0;
            firstUnused = null;
          } else {
            firstUnused ??= index + i;
            gap++;
          }
        }
        index += batch;
      }
      next[chain] = firstUnused ?? index;
    }

    var confirmed = BigInt.zero;
    var unconfirmed = BigInt.zero;
    for (final s in stats.values) {
      confirmed += s.confirmedBalance;
      unconfirmed += s.unconfirmedBalance;
    }

    final funded = [
      for (final e in stats.entries)
        if (e.value.confirmedBalance + e.value.unconfirmedBalance > BigInt.zero)
          e.key,
    ];
    final utxoLists = await _limited(funded, client.utxos);
    final utxos = [
      for (var i = 0; i < funded.length; i++)
        for (final u in utxoLists[i])
          BtcOwnedUtxo(
            txid: u.txid,
            vout: u.vout,
            value: u.value,
            confirmed: u.confirmed,
            path: used[funded[i]]!,
            address: funded[i],
          ),
    ];

    final txLists = await _limited(used.keys.toList(), client.transactions);
    final byId = <String, EsploraTx>{
      for (final list in txLists)
        for (final tx in list) tx.txid: tx,
    };
    final history = [
      for (final tx in byId.values)
        BtcHistoryEntry(
          txid: tx.txid,
          delta: _sumOwned(tx.outputs, used) - _sumOwned(tx.inputs, used),
          fee: tx.fee,
          confirmed: tx.confirmed,
          time: tx.blockTime,
        ),
    ]..sort(_newestFirst);

    return BtcWalletState(
      confirmedBalance: confirmed,
      unconfirmedBalance: unconfirmed,
      utxos: utxos,
      history: history,
      nextReceive: (chain: BtcAccount.receiveChain, index: next[0]!),
      nextChange: (chain: BtcAccount.changeChain, index: next[1]!),
    );
  }

  /// Executa no máximo [batch] consultas ao mesmo tempo.
  Future<List<R>> _limited<T, R>(
    List<T> items,
    Future<R> Function(T) fn,
  ) async {
    final results = <R>[];
    for (var i = 0; i < items.length; i += batch) {
      final end = i + batch > items.length ? items.length : i + batch;
      results.addAll(await Future.wait(items.sublist(i, end).map(fn)));
    }
    return results;
  }

  static BigInt _sumOwned(
    List<(String?, BigInt)> items,
    Map<String, BtcPath> owned,
  ) => items
      .where((e) => e.$1 != null && owned.containsKey(e.$1))
      .fold(BigInt.zero, (sum, e) => sum + e.$2);

  // Pendentes primeiro, depois do mais novo para o mais antigo.
  static int _newestFirst(BtcHistoryEntry a, BtcHistoryEntry b) {
    if (a.time == null && b.time == null) return 0;
    if (a.time == null) return -1;
    if (b.time == null) return 1;
    return b.time!.compareTo(a.time!);
  }
}
