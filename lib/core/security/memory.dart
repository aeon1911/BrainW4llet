/// Sobrescreve [buffer] com zeros. Ignora listas imutáveis.
///
/// Para buffers no heap do Dart, que o GC pode ter copiado antes; é uma
/// redução de janela de exposição, não uma garantia. Segredos de longa
/// duração devem ficar em `SecureKey` (memória da libsodium).
void wipeBytes(List<int> buffer) {
  try {
    buffer.fillRange(0, buffer.length, 0);
  } on UnsupportedError {
    // Visão somente-leitura: nada a fazer além de soltar a referência.
  }
}
