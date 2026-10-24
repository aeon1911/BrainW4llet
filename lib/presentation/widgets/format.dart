import '../../features/btc/btc_account.dart';
import '../../features/wallet/amounts.dart';

String formatBtc(BigInt sats) => '${Amounts.format(sats, 8)} BTC';

/// Valor em unidades base (satoshis/duffs) de uma moeda UTXO.
String formatUtxo(UtxoCoin coin, BigInt units) =>
    '${Amounts.format(units, 8)} ${coin.ticker}';

String formatEth(BigInt wei) => '${Amounts.format(wei, 18)} ETH';

String formatSol(BigInt lamports) => '${Amounts.format(lamports, 9)} SOL';

/// Valor com sinal explícito para o histórico (+ recebido, − enviado).
String signed(String formatted, BigInt delta) =>
    delta.isNegative ? '−${formatted.substring(1)}' : '+$formatted';

String formatDate(DateTime? time) {
  if (time == null) return 'pendente';
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
}

String shorten(String text, [int keep = 8]) => text.length <= keep * 2 + 1
    ? text
    : '${text.substring(0, keep)}…${text.substring(text.length - keep)}';
