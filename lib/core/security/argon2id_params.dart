/// Parâmetros de custo do Argon2id (libsodium `crypto_pwhash`, Argon2id v1.3).
///
/// A libsodium usa sempre paralelismo 1 (uma lane). Isso não reduz o custo
/// do atacante: o paralelismo só permite ao *defensor* usar vários núcleos.
/// O ganho de usar código nativo é poder subir a memória (decisão registrada
/// em docs/AVALIACAO_SEGURANCA.md §5).
///
/// [v1] está CONGELADO: alterar qualquer valor muda todas as passphrases.
final class Argon2idParams {
  const Argon2idParams({required this.memoryKiB, required this.iterations});

  /// 512 MiB, 4 iterações. Calibrar no iPhone antes de guardar fundos.
  static const Argon2idParams v1 = Argon2idParams(
    memoryKiB: 512 * 1024,
    iterations: 4,
  );

  static const int minMemoryKiB = 64 * 1024;
  static const int minIterations = 3;
  static const int outputLength = 32;
  static const int parallelism = 1;

  /// Memória em blocos de 1 KiB (parâmetro `m` do Argon2).
  final int memoryKiB;
  final int iterations;

  int get memoryBytes => memoryKiB * 1024;

  bool get meetsSecurityFloor =>
      memoryKiB >= minMemoryKiB && iterations >= minIterations;

  /// Lança [ArgumentError] se os parâmetros estiverem abaixo do piso.
  void validate() {
    if (!meetsSecurityFloor) {
      throw ArgumentError.value(
        this,
        'params',
        'Argon2id abaixo do piso de segurança '
            '(m>=$minMemoryKiB KiB, t>=$minIterations)',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Argon2idParams &&
      other.memoryKiB == memoryKiB &&
      other.iterations == iterations;

  @override
  int get hashCode => Object.hash(memoryKiB, iterations);

  @override
  String toString() =>
      'Argon2idParams(m=${memoryKiB}KiB, t=$iterations, p=$parallelism)';
}
