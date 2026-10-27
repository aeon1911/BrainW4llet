import 'package:flutter/material.dart';

/// Identidade visual de cada moeda: cor e ícone (sem logos de marca).
enum CoinStyle {
  btc('Bitcoin', 'BTC', Icons.currency_bitcoin_rounded, Color(0xFFF7931A)),
  eth('Ethereum', 'ETH', Icons.diamond_outlined, Color(0xFF7B8CF5)),
  sol('Solana', 'SOL', Icons.density_medium_rounded, Color(0xFFA06BFF)),
  dash('Dash', 'DASH', Icons.bolt_rounded, Color(0xFF1C8CE6)),
  xmr('Monero', 'XMR', Icons.visibility_off_outlined, Color(0xFFFF7A1A));

  const CoinStyle(this.label, this.ticker, this.icon, this.color);

  final String label;
  final String ticker;

  /// Ícone genérico (embutido no app), não o logo da moeda.
  final IconData icon;
  final Color color;

  static CoinStyle? fromTicker(String ticker) {
    for (final c in values) {
      if (c.ticker == ticker.toUpperCase()) return c;
    }
    return null;
  }
}
