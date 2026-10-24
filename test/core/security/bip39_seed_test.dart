import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:brainw4llet/core/security/security.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _unhex(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

const _abandon12 =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon about';
final _abandon24 = '${'abandon ' * 23}art';

// lifeKey dos vetores OpenSSL em life_keys_passphrase_test.dart e seeds
// calculadas com hashlib.pbkdf2_hmac (Python), implementação independente.
const _lifeKeyCheap =
    'cbfa7054e8e3f46a285c013e3d7a9556cde089ff23dd2c3f96b7ceb196423e06';
const _seedCheap =
    '58f6ce6451d68325dabd14fba7ea4f09ba7b81e2f6f4d01790ad4e9827b04a61'
    '2fd12ce8aab8728ea906bb9fb4ac7c70fa90916f080ddaf00f260512f9720c0f';

void main() {
  final sodium = SodiumRuntime.instance;

  test('vetor oficial BIP-39 (passphrase TREZOR) via PBKDF2 da lib', () {
    final seed = Bip39SeedGenerator(
      Mnemonic.fromString(_abandon12),
    ).generate('TREZOR');
    expect(
      _hex(seed),
      'c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e5349553'
      '1f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04',
    );
  });

  test('generateMnemonic gera 24 palavras válidas e diferentes', () {
    final a = Bip39Seed.generateMnemonic();
    final b = Bip39Seed.generateMnemonic();
    expect(a, hasLength(24));
    expect(Bip39Seed.isValid(a.join(' ')), isTrue);
    expect(a, isNot(b));
  });

  test('isValid rejeita checksum e palavras erradas', () {
    expect(Bip39Seed.isValid(_abandon12), isTrue);
    expect(Bip39Seed.isValid('${'abandon ' * 11}abandon'), isFalse);
    expect(Bip39Seed.isValid('${'abandon ' * 11}abacaxi'), isFalse);
    expect(Bip39Seed.isValid(''), isFalse);
  });

  test('isValid tolera maiúsculas e espaços extras', () {
    expect(Bip39Seed.isValid('  ${_abandon12.toUpperCase()}\n'), isTrue);
  });

  test('passphraseSalt = "mnemonic" + hex minúsculo da lifeKey', () {
    final salt = Bip39Seed.passphraseSalt(
      Uint8List.fromList(_unhex(_lifeKeyCheap)),
    );
    expect(String.fromCharCodes(salt), 'mnemonic$_lifeKeyCheap');
  });

  test('deriveSeed confere com vetor calculado em Python', () {
    final lifeKey = sodium.secureCopy(
      Uint8List.fromList(_unhex(_lifeKeyCheap)),
    );
    final seed = Bip39Seed.deriveSeed(mnemonic: _abandon24, lifeKey: lifeKey);
    expect(seed.length, 64);
    expect(_hex(seed.extractBytes()), _seedCheap);
    seed.dispose();
    lifeKey.dispose();
  });

  test('deriveSeed = BIP-39 padrão com passphrase hex (compatibilidade)', () {
    final lifeKey = sodium.secureCopy(
      Uint8List.fromList(_unhex(_lifeKeyCheap)),
    );
    final ours = Bip39Seed.deriveSeed(mnemonic: _abandon24, lifeKey: lifeKey);
    final standard = Bip39SeedGenerator(
      Mnemonic.fromString(_abandon24),
    ).generate(_lifeKeyCheap);
    expect(_hex(ours.extractBytes()), _hex(standard));
    ours.dispose();
    lifeKey.dispose();
  });

  test('deriveSeed recusa mnemônica inválida sem vazar o conteúdo', () {
    final lifeKey = sodium.secureRandom(32);
    expect(
      () => Bip39Seed.deriveSeed(mnemonic: 'segredo abacaxi', lifeKey: lifeKey),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.toString(),
          'mensagem',
          isNot(contains('segredo')),
        ),
      ),
    );
    lifeKey.dispose();
  });
}
