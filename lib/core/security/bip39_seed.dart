import 'dart:convert';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:meta/meta.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'memory.dart';
import 'sodium_runtime.dart';

/// Seed BIP-39 da arquitetura B: mnemônica aleatória + Chaves de Vida.
///
/// ```text
/// seed = PBKDF2-HMAC-SHA512(NFKD(mnemônica), "mnemonic" || hex(lifeKey), 2048)
/// ```
///
/// É exatamente o BIP-39 padrão com a passphrase `hex(lifeKey)` (64
/// caracteres minúsculos), portanto recuperável em qualquer carteira que
/// aceite passphrase (Sparrow, Electrum, Keystone...).
abstract final class Bip39Seed {
  /// 256 bits de entropia → 24 palavras.
  static const int entropyBytes = 32;
  static const int seedBytes = 64;
  static const int _pbkdf2Rounds = 2048;
  static final List<int> _saltPrefix = ascii.encode('mnemonic');

  /// Gera uma mnemônica nova com o CSPRNG da libsodium (`randombytes_buf`).
  static List<String> generateMnemonic() {
    final entropy = SodiumRuntime.instance.randombytes.buf(entropyBytes);
    try {
      return Bip39MnemonicEncoder().encode(entropy).toList();
    } finally {
      wipeBytes(entropy);
    }
  }

  static const Set<int> _validWordCounts = {12, 15, 18, 21, 24};
  static final List<String> _wordList = Bip39Languages.english.wordList;
  static final Set<String> _words = _wordList.toSet();
  // Numeração copiada da tela ("1.", "02)", "3-") colada ou não à palavra.
  static final RegExp _numbering = RegExp(r'^\d+[.):\-]*');
  static final RegExp _separators = RegExp(r'[\s,;]+', unicode: true);

  /// Forma canônica da mnemônica digitada: minúsculas, NFKD, sem numeração,
  /// separada por um espaço e com abreviações de 4 letras expandidas (no
  /// BIP-39 em inglês, as 4 primeiras letras identificam a palavra).
  ///
  /// Para uma mnemônica já correta, o resultado é ela mesma normalizada,
  /// então a seed derivada não muda.
  static String normalizeMnemonic(String mnemonic) =>
      _tokens(mnemonic).join(' ');

  static List<String> _tokens(String mnemonic) => [
    for (final raw in unorm.nfkd(mnemonic.toLowerCase()).split(_separators))
      if (raw.replaceFirst(_numbering, '') case final token
          when token.isNotEmpty)
        _expand(token),
  ];

  static String _expand(String token) {
    if (token.length < 4 || _words.contains(token)) return token;
    final matches = _wordList.where((w) => w.startsWith(token)).take(2);
    return matches.length == 1 ? matches.first : token;
  }

  /// Valida palavras e checksum (lista em inglês).
  static bool isValid(String mnemonic) => describeProblem(mnemonic) == null;

  /// Explica o que está errado na mnemônica, ou `null` se ela é válida.
  /// Aponta só posições, nunca repete as palavras digitadas.
  static String? describeProblem(String mnemonic) {
    final tokens = _tokens(mnemonic);
    if (tokens.isEmpty) return 'Digite as palavras da seed.';

    final unknown = [
      for (var i = 0; i < tokens.length; i++)
        if (!_words.contains(tokens[i])) i + 1,
    ];
    if (unknown.isNotEmpty) {
      final positions = unknown.join(', ');
      return unknown.length == 1
          ? 'A palavra nº $positions não existe na lista BIP-39. '
                'Confira a grafia.'
          : 'As palavras nº $positions não existem na lista BIP-39. '
                'Confira a grafia.';
    }

    if (!_validWordCounts.contains(tokens.length)) {
      return 'Foram digitadas ${tokens.length} palavras; uma seed tem 24 '
          '(ou 12, 15, 18, 21).';
    }

    try {
      if (Bip39MnemonicValidator().isValid(tokens.join(' '))) return null;
    } on Exception {
      // Cai na mensagem de checksum abaixo.
    }
    return 'Todas as palavras existem, mas a combinação não fecha '
        '(checksum): alguma palavra está trocada ou fora de ordem.';
  }

  /// Deriva a seed de 64 bytes em memória protegida. [lifeKey] não é
  /// descartada aqui; quem chama continua responsável por ela.
  static SecureKey deriveSeed({
    required String mnemonic,
    required SecureKey lifeKey,
  }) {
    final normalized = normalizeMnemonic(mnemonic);
    if (describeProblem(normalized) != null) {
      // Nunca inclua a mnemônica em mensagens de erro.
      throw ArgumentError('Mnemônica BIP-39 inválida.');
    }
    final password = utf8.encode(normalized);
    final salt = lifeKey.runUnlockedSync(passphraseSalt);
    List<int>? seed;
    try {
      seed = QuickCrypto.pbkdf2DeriveKey(
        password: password,
        salt: salt,
        iterations: _pbkdf2Rounds,
      );
      return SodiumRuntime.instance.secureCopy(
        seed is Uint8List ? seed : Uint8List.fromList(seed),
      );
    } finally {
      wipeBytes(password);
      wipeBytes(salt);
      if (seed != null) wipeBytes(seed);
    }
  }

  /// `"mnemonic" || hex(lifeKey)` montado direto em bytes, sem `String`
  /// intermediária (que não poderia ser zerada).
  @visibleForTesting
  static Uint8List passphraseSalt(Uint8List lifeKey) {
    const hexDigits = '0123456789abcdef';
    final out = Uint8List(_saltPrefix.length + lifeKey.length * 2)
      ..setAll(0, _saltPrefix);
    var offset = _saltPrefix.length;
    for (final byte in lifeKey) {
      out[offset++] = hexDigits.codeUnitAt(byte >> 4);
      out[offset++] = hexDigits.codeUnitAt(byte & 0x0f);
    }
    return out;
  }
}
