import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:brainw4llet/core/security/security.dart';
import 'package:brainw4llet/features/wallet/watch_only.dart';
import 'package:flutter_test/flutter_test.dart';

// Seed pública de teste "abandon ×11 about", sem passphrase.
// BTC: vetor oficial do BIP-84. ETH: endereço de referência amplamente
// publicado. SOL, DASH, XMR: implementação independente em Python puro
// (secp256k1, SLIP-10 ed25519, Keccak e Base58 escritos do zero); o SOL
// confere com o endereço que o Phantom mostra para esta seed.
const _expected = {
  'BTC': [
    'zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtfSdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs',
    'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu',
  ],
  'ETH': ['0x9858EfFD232B4033E47d90003D41EC34EcaEda94'],
  'SOL': ['HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk'],
  'DASH': [
    'xpub6CYEjsU6zPM3sADS2ubu2aZeGxCm3C5KabkCpo4rkNbXGAH9M7rRUJ4E5CKiyUddmRzrSCopPzisTBrXkfCD4o577XKM9mzyZtP1Xdbizyk',
    'XoJA8qE3N2Y3jMLEtZ3vcN42qseZ8LvFf5',
  ],
  'XMR': [
    '49vDbkSo7eve3J41sBdjvjaBUyz8qHohsQcGtRf63qEUTMBvmA45fpp5pSacMdSg7A3b71RejLzB8EkGbfjp5PELVF2N4Zn',
    '0f3fe25d0c6d4c94dde0c0bcc214b233e9c72927f813728b0f01f28f9d5e1201',
  ],
};

void main() {
  test('dados watch-only batem com vetores independentes', () {
    final seedBytes = Bip39SeedGenerator(
      Mnemonic.fromString('${'abandon ' * 11}about'),
    ).generate();
    final seed = SodiumRuntime.instance.secureCopy(
      Uint8List.fromList(seedBytes),
    );
    final assets = deriveWatchOnly(seed);
    seed.dispose();

    expect(assets.map((a) => a.ticker), _expected.keys);
    for (final asset in assets) {
      expect(
        asset.fields.map((f) => f.value).toList(),
        _expected[asset.ticker],
        reason: asset.ticker,
      );
    }
    final viewKey = assets.last.fields.last;
    expect(viewKey.sensitive, isTrue);
  });
}
