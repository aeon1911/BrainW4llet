import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:brainw4llet/core/security/security.dart';
import 'package:brainw4llet/features/wallet/address_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('endereços batem com os vetores públicos de BIP-44 e BIP-84', () {
    // "abandon ×11 about" sem passphrase: vetor de teste do BIP-84 e
    // endereço Ethereum de referência amplamente publicado.
    final seedBytes = Bip39SeedGenerator(
      Mnemonic.fromString('${'abandon ' * 11}about'),
    ).generate();
    final seed = SodiumRuntime.instance.secureCopy(
      Uint8List.fromList(seedBytes),
    );

    final preview = AddressPreview.fromSeed(seed);
    expect(
      preview.ethereum.toLowerCase(),
      '0x9858effd232b4033e47d90003d41ec34ecaeda94',
    );
    expect(preview.bitcoin, 'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu');
    seed.dispose();
  });
}
