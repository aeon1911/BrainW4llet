import 'dart:convert';

import 'package:brainw4llet/core/security/security.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Parâmetros baratos, só para testes rápidos de comportamento.
const _cheap = Argon2idParams(memoryKiB: 8 * 1024, iterations: 1);

// Entrada de referência e vetores gerados com `openssl kdf ... ARGON2ID`
// (OpenSSL 3.6, lanes=1), implementação independente da libsodium.
const _answers = ['  Maria  JOSÉ ', 'São\tPaulo', 'Rex'];
const _expectedPasswordHex =
    '427261696e57346c6c65742f506173737068726173652f76310000000003000000'
    '0a6d61726961206a6f73650000000973616f207061756c6f00000003726578';
const _expectedSaltHex = '276c682c1440aabf4d002f3b2f71b9df';
const _goldenCheap =
    'cbfa7054e8e3f46a285c013e3d7a9556cde089ff23dd2c3f96b7ceb196423e06';
const _goldenV1 =
    '4a1aa419f6d800daff8e8e5ed5446f5745573e7e5bdc0bfe44ea8f7314387c94';

void main() {
  group('Argon2idParams', () {
    test('v1 = 512 MiB, t=4 e atende ao piso', () {
      expect(Argon2idParams.v1.memoryKiB, 512 * 1024);
      expect(Argon2idParams.v1.iterations, 4);
      expect(Argon2idParams.v1.meetsSecurityFloor, isTrue);
    });

    test('construtor de produção recusa parâmetros fracos', () {
      expect(() => LifeKeysPassphrase(params: _cheap), throwsArgumentError);
      expect(
        () => LifeKeysPassphrase(
          params: const Argon2idParams(memoryKiB: 1 << 20, iterations: 2),
        ),
        throwsArgumentError,
      );
    });
  });

  group('codificação', () {
    test('password e salt batem com o esquema v1 documentado', () {
      expect(
        _hex(LifeKeysPassphrase.encodePassword(_answers)),
        _expectedPasswordHex,
      );
      expect(
        _hex(LifeKeysPassphrase.salt(SodiumRuntime.instance)),
        _expectedSaltHex,
      );
    });

    test('prefixo de tamanho evita ambiguidade entre respostas', () {
      expect(
        LifeKeysPassphrase.encodePassword(['ab', 'c']),
        isNot(LifeKeysPassphrase.encodePassword(['a', 'bc'])),
      );
      expect(
        LifeKeysPassphrase.encodePassword(['a b']),
        isNot(LifeKeysPassphrase.encodePassword(['a', 'b'])),
      );
    });

    test('a ordem das respostas importa', () {
      expect(
        LifeKeysPassphrase.encodePassword(['rex', 'maria']),
        isNot(LifeKeysPassphrase.encodePassword(['maria', 'rex'])),
      );
    });

    test('recusa lista vazia ou resposta vazia sem vazar o conteúdo', () {
      expect(() => LifeKeysPassphrase.encodePassword([]), throwsArgumentError);
      expect(
        () => LifeKeysPassphrase.encodePassword(['segredo', ' ​ ']),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'mensagem',
            allOf(contains('#2'), isNot(contains('segredo'))),
          ),
        ),
      );
    });

    test('password começa com o domínio v1', () {
      final encoded = LifeKeysPassphrase.encodePassword(['x']);
      expect(
        utf8.decode(
          encoded.sublist(0, LifeKeysPassphrase.passwordDomain.length),
        ),
        LifeKeysPassphrase.passwordDomain,
      );
    });
  });

  group('derive (parâmetros baratos)', () {
    const kdf = LifeKeysPassphrase.insecureForTesting(_cheap);

    test('confere com vetor gerado pelo OpenSSL', () async {
      final key = await kdf.derive(_answers);
      expect(key.length, 32);
      expect(_hex(key.extractBytes()), _goldenCheap);
      key.dispose();
    });

    test('variações de acento/caixa/espaço geram a mesma chave', () async {
      final a = await kdf.derive(['maria jose', 'sao paulo', 'rex']);
      final b = await kdf.derive(_answers);
      expect(a, b); // comparação dentro da memória protegida
      a.dispose();
      b.dispose();
    });

    test('respostas diferentes geram chaves diferentes', () async {
      final a = await kdf.derive(['maria jose', 'sao paulo', 'rex']);
      final b = await kdf.derive(['maria jose', 'sao paulo', 'rax']);
      expect(a, isNot(b));
      a.dispose();
      b.dispose();
    });
  });

  test('derive com parâmetros v1 de produção confere com OpenSSL', () async {
    final key = await LifeKeysPassphrase().derive(_answers);
    expect(_hex(key.extractBytes()), _goldenV1);
    key.dispose();
  }, tags: 'slow');
}
