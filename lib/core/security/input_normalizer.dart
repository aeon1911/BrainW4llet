import 'dart:convert';
import 'dart:typed_data';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Normalização canônica das respostas ("Chaves de Vida") — versão 1.
///
/// ATENÇÃO: qualquer mudança no comportamento desta classe altera as chaves
/// derivadas e torna carteiras existentes inacessíveis. Mudanças exigem uma
/// nova [version] e um caminho de migração explícito.
///
/// Etapas (nesta ordem):
///  1. NFKD — separa acentos das letras e unifica formas de compatibilidade
///     (largura total, ligaduras, espaço não separável).
///  2. Minúsculas (mapeamento Unicode independente de locale).
///  3. NFKD de novo, pois o lowercase pode gerar novas sequências
///     decomponíveis (ex.: `İ` → `i̇`).
///  4. Remove marcas combinantes (`\p{M}`) — acentos, cedilha, til etc.
///  5. Translitera letras sem decomposição Unicode (`ß`, `ø`, `æ`, `ł`...).
///  6. Remove caracteres de formatação invisíveis (`\p{Cf}`: zero-width,
///     BOM...), converte todo espaço em branco Unicode em espaço simples e
///     remove os caracteres de controle restantes (`\p{Cc}`).
///  7. Colapsa espaços múltiplos e remove espaços das extremidades.
///  8. NFC — forma composta final (relevante só para scripts como Hangul).
abstract final class InputNormalizer {
  static const int version = 1;

  static final RegExp _combiningMarks = RegExp(r'\p{M}', unicode: true);
  static final RegExp _whitespace = RegExp(r'\s', unicode: true);
  static final RegExp _format = RegExp(r'\p{Cf}', unicode: true);
  static final RegExp _control = RegExp(r'\p{Cc}', unicode: true);
  static final RegExp _multipleSpaces = RegExp(r' {2,}');

  /// Letras latinas que o Unicode não decompõe em base + acento.
  static const Map<String, String> _fold = {
    'ß': 'ss',
    'æ': 'ae',
    'œ': 'oe',
    'ø': 'o',
    'đ': 'd',
    'ð': 'd',
    'ł': 'l',
    'ı': 'i',
    'ħ': 'h',
    'ŧ': 't',
    'þ': 'th',
  };
  static final RegExp _foldPattern = RegExp(_fold.keys.join('|'));

  static String normalize(String input) {
    var s = unorm.nfkd(input);
    s = s.toLowerCase();
    s = unorm.nfkd(s);
    s = s.replaceAll(_combiningMarks, '');
    s = s.replaceAllMapped(_foldPattern, (m) => _fold[m[0]]!);
    s = s.replaceAll(_format, '');
    s = s.replaceAll(_whitespace, ' ');
    s = s.replaceAll(_control, '');
    s = s.replaceAll(_multipleSpaces, ' ').trim();
    return unorm.nfc(s);
  }

  /// [normalize] codificado em UTF-8. O buffer retornado deve ser zerado
  /// pelo chamador (ver `SecureBytes.wipe`).
  static Uint8List normalizeToBytes(String input) =>
      utf8.encode(normalize(input));
}
