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
  static final RegExp _whitespace = RegExp(r'\s+', unicode: true);

  /// Gera uma mnemônica nova com o CSPRNG da libsodium (`randombytes_buf`).
  static List<String> generateMnemonic() {
    final entropy = SodiumRuntime.instance.randombytes.buf(entropyBytes);
    try {
      return Bip39MnemonicEncoder().encode(entropy).toList();
    } finally {
      wipeBytes(entropy);
    }
  }

  /// Minúsculas, espaços colapsados e NFKD (exigido pelo BIP-39).
  static String normalizeMnemonic(String mnemonic) =>
      unorm.nfkd(mnemonic.toLowerCase().trim().replaceAll(_whitespace, ' '));

  /// Valida palavras e checksum (lista em inglês).
  static bool isValid(String mnemonic) {
    try {
      return Bip39MnemonicValidator().isValid(normalizeMnemonic(mnemonic));
    } on Exception {
      return false;
    }
  }

  /// Deriva a seed de 64 bytes em memória protegida. [lifeKey] não é
  /// descartada aqui; quem chama continua responsável por ela.
  static SecureKey deriveSeed({
    required String mnemonic,
    required SecureKey lifeKey,
  }) {
    final normalized = normalizeMnemonic(mnemonic);
    if (!isValid(normalized)) {
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
