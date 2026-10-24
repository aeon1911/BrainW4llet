import 'package:sodium/sodium.ffi.dart' as sodium_ffi;
import 'package:sodium/sodium_sumo.dart';

/// Instância única da libsodium (variante "sumo", que inclui `crypto_pwhash`).
///
/// A libsodium é compilada a partir do código-fonte assinado que vem dentro do
/// pacote `sodium` (ver README.md). Usa a entrada FFI diretamente: o app não
/// tem alvo web. A inicialização é síncrona e idempotente, então também pode
/// ser chamada dentro de isolates.
abstract final class SodiumRuntime {
  static SodiumSumo? _instance;

  static SodiumSumo get instance =>
      _instance ??= sodium_ffi.SodiumSumoInit.init();
}
