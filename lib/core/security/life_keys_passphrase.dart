import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sodium/sodium_sumo.dart';

import 'argon2id_params.dart';
import 'input_normalizer.dart';
import 'memory.dart';
import 'sodium_runtime.dart';

/// Deriva das "Chaves de Vida" a chave de 32 bytes usada como passphrase
/// BIP-39 (segundo fator sobre a seed aleatória de 24 palavras).
///
/// Esquema v1 (CONGELADO — ver `README.md` nesta pasta):
///
/// ```text
/// password = "BrainW4llet/Passphrase/v1" 0x00 u32be(n)
///            { u32be(len(a_i)) utf8(normalize(a_i)) } para i em 0..n-1
/// salt     = BLAKE2b-128("BrainW4llet/Salt/v1")
/// lifeKey  = Argon2id-v1.3(password, salt, m=512 MiB, t=4, p=1) // 32 bytes
/// ```
///
/// O prefixo de tamanho em cada resposta impede ambiguidades como
/// `["ab", "c"]` vs `["a", "bc"]`. A ordem das respostas importa.
///
/// Não há salt por usuário: a seed é aleatória (256 bits), então não existe
/// pré-computação útil para um atacante sem o backup físico da seed.
final class LifeKeysPassphrase {
  /// Instância de produção. Recusa parâmetros abaixo do piso de segurança.
  LifeKeysPassphrase({Argon2idParams params = Argon2idParams.v1})
    : this._(params..validate());

  /// Permite parâmetros baratos para testes rápidos. Nunca use em produção.
  @visibleForTesting
  const LifeKeysPassphrase.insecureForTesting(Argon2idParams params)
    : this._(params);

  const LifeKeysPassphrase._(this.params);

  static const String passwordDomain = 'BrainW4llet/Passphrase/v1';
  static const String saltDomain = 'BrainW4llet/Salt/v1';

  final Argon2idParams params;

  /// Executa o Argon2id num isolate separado (a UI não trava) e devolve a
  /// chave em memória protegida da libsodium. Quem chama deve chamar
  /// `dispose()` assim que derivar a seed.
  Future<SecureKey> derive(List<String> answers) async {
    final sodium = SodiumRuntime.instance;
    final encoded = encodePassword(answers);
    final SecureKey password;
    try {
      password = sodium.secureCopy(encoded);
    } finally {
      wipeBytes(encoded);
    }

    final opsLimit = params.iterations;
    final memLimit = params.memoryBytes;
    try {
      return await sodium.runIsolated(
        (keys, _) => _pwhash(keys.single, opsLimit, memLimit),
        secureKeys: [password],
      );
    } finally {
      password.dispose();
    }
  }

  // Estática para que o closure enviado ao isolate não capture nada além de
  // inteiros e da chave transferível.
  static SecureKey _pwhash(SecureKey password, int opsLimit, int memLimit) {
    final sodium = SodiumRuntime.instance;
    try {
      return password.runUnlockedSync(
        (bytes) => sodium.crypto.pwhash.callRaw(
          outLen: Argon2idParams.outputLength,
          password: Int8List.sublistView(bytes),
          salt: salt(sodium),
          opsLimit: opsLimit,
          memLimit: memLimit,
          alg: CryptoPwhashAlgorithm.argon2id13,
        ),
      );
    } finally {
      password.dispose();
    }
  }

  /// `BLAKE2b-128(saltDomain)`. Não é segredo; o hash só ajusta o tamanho
  /// para os 16 bytes exigidos pela libsodium.
  @visibleForTesting
  static Uint8List salt(Sodium sodium) => sodium.crypto.genericHash(
    message: utf8.encode(saltDomain),
    outLen: sodium.crypto.genericHash.bytesMin,
  );

  /// Codifica as respostas normalizadas de forma inequívoca (ver doc da
  /// classe). O buffer retornado deve ser zerado pelo chamador.
  @visibleForTesting
  static Uint8List encodePassword(List<String> answers) {
    if (answers.isEmpty) {
      throw ArgumentError('Informe ao menos uma resposta.');
    }
    final domain = utf8.encode(passwordDomain);
    final normalized = <Uint8List>[];
    try {
      for (var i = 0; i < answers.length; i++) {
        final bytes = InputNormalizer.normalizeToBytes(answers[i]);
        normalized.add(bytes);
        if (bytes.isEmpty) {
          // Nunca inclua o conteúdo da resposta em mensagens de erro.
          throw ArgumentError(
            'Resposta #${i + 1} está vazia após normalização.',
          );
        }
      }

      var total = domain.length + 1 + 4;
      for (final bytes in normalized) {
        total += 4 + bytes.length;
      }

      final out = Uint8List(total);
      final view = ByteData.sublistView(out);
      var offset = 0;
      out.setAll(offset, domain);
      offset += domain.length + 1; // separador 0x00
      view.setUint32(offset, normalized.length);
      offset += 4;
      for (final bytes in normalized) {
        view.setUint32(offset, bytes.length);
        offset += 4;
        out.setAll(offset, bytes);
        offset += bytes.length;
      }
      return out;
    } finally {
      normalized.forEach(wipeBytes);
    }
  }
}
