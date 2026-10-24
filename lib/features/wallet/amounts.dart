/// Conversão entre unidades base (satoshi, wei, lamport) e texto decimal,
/// sempre com BigInt: nada de ponto flutuante com dinheiro.
abstract final class Amounts {
  static final RegExp _decimal = RegExp(r'^\d+([.,]\d+)?$');

  /// `formatUnits(150000000, 8)` → `1.5`.
  static String format(BigInt value, int decimals) {
    final negative = value.isNegative;
    final digits = value.abs().toString().padLeft(decimals + 1, '0');
    final whole = digits.substring(0, digits.length - decimals);
    var fraction = digits.substring(digits.length - decimals);
    fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
    final text = fraction.isEmpty ? whole : '$whole.$fraction';
    return negative ? '-$text' : text;
  }

  /// `parse('1,5', 8)` → 150000000. Lança [FormatException] se o texto não
  /// for um número positivo ou tiver casas decimais demais.
  static BigInt parse(String text, int decimals) {
    final clean = text.trim().replaceAll(' ', '');
    if (!_decimal.hasMatch(clean)) {
      throw const FormatException('Valor inválido.');
    }
    final parts = clean.replaceAll(',', '.').split('.');
    final fraction = parts.length > 1 ? parts[1] : '';
    if (fraction.length > decimals) {
      throw FormatException('No máximo $decimals casas decimais.');
    }
    return BigInt.parse(parts[0] + fraction.padRight(decimals, '0'));
  }
}
