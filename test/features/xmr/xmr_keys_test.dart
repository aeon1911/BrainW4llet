import 'dart:io';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:brainw4llet/core/security/security.dart';
import 'package:brainw4llet/features/network/wallet_network.dart';
import 'package:brainw4llet/features/transfer/transfer_document.dart';
import 'package:brainw4llet/features/wallet/watch_only.dart';
import 'package:brainw4llet/features/xmr/xmr_keys.dart';
import 'package:brainw4llet/features/xmr/xmr_signer.dart';
import 'package:brainw4llet/features/xmr/xmr_wallet.dart';
import 'package:flutter_test/flutter_test.dart';

// Endereços conferidos por implementação independente em Python
// (Keccak, ed25519 e Base58 do Monero escritos do zero).
const _mainnet =
    '49vDbkSo7eve3J41sBdjvjaBUyz8qHohsQcGtRf63qEUTMBvmA45fpp5pSacMdSg7A3b71RejLzB8EkGbfjp5PELVF2N4Zn';
const _stagenet =
    '5A8FgbMkmG2e3J41sBdjvjaBUyz8qHohsQcGtRf63qEUTMBvmA45fpp5pSacMdSg7A3b71RejLzB8EkGbfjp5PELVHCRUaE';

void main() {
  final seedBytes = Bip39SeedGenerator(
    Mnemonic.fromString('${'abandon ' * 11}about'),
  ).generate();

  test('endereços Monero (rede principal e stagenet) batem com o Python', () {
    expect(
      XmrKeys.fullAccount(seedBytes, WalletNetwork.mainnet).primaryAddress,
      _mainnet,
    );
    expect(
      XmrKeys.fullAccount(seedBytes, WalletNetwork.testnet).primaryAddress,
      _stagenet,
    );
  });

  test('conta somente-leitura tem as mesmas chaves públicas e nenhuma de '
      'gasto', () {
    final full = XmrKeys.fullAccount(seedBytes, WalletNetwork.testnet);
    final watch = XmrKeys.watchAccount(
      address: full.primaryAddress,
      viewKeyHex: BytesUtils.toHexString(full.privateViewKey.raw),
      network: WalletNetwork.testnet,
    );
    expect(watch.primaryAddress, full.primaryAddress);
    expect(watch.isWatchOnly, isTrue);
    expect(() => watch.privateSpendKey, throwsA(anything));
  });

  test('conta somente-leitura recusa endereço de outra rede', () {
    final full = XmrKeys.fullAccount(seedBytes, WalletNetwork.mainnet);
    expect(
      () => XmrKeys.watchAccount(
        address: full.primaryAddress,
        viewKeyHex: BytesUtils.toHexString(full.privateViewKey.raw),
        network: WalletNetwork.testnet,
      ),
      throwsFormatException,
    );
  });

  test('arquivo somente-leitura de teste já traz Monero da stagenet', () {
    final seed = SodiumRuntime.instance.secureCopy(
      Uint8List.fromList(seedBytes),
    );
    final wallet = WatchOnlyWallet.fromSeed(seed, WalletNetwork.testnet);
    seed.dispose();
    expect(wallet.xmrAddress, _stagenet);
    expect(wallet.createdAt, isNotNull);
    final back = WatchOnlyWallet.fromJson(wallet.toJson());
    expect(back.createdAt, wallet.createdAt);
    expect(back.fingerprint, wallet.fingerprint);
  });

  test('documentos Monero sobrevivem à ida e volta pelo arquivo', () {
    final request = XmrSignRequest(
      network: WalletNetwork.testnet,
      sources: ['aa', 'bb'],
      knownOutputs: ['cc'],
      destinations: [(address: _stagenet, amount: BigInt.zero)],
      feeEstimate: {'fee': '20000', 'quantization_mask': '10000'},
    );
    final back = TransferDocument.decode(request.encode()) as XmrSignRequest;
    expect(back.sources, request.sources);
    expect(back.destinations.single.address, _stagenet);
    expect(back.feeEstimate['fee'], '20000');

    const signed = XmrSignedTransaction(
      network: WalletNetwork.testnet,
      txHex: '02',
      txHash: 'ff',
      keyImages: {'a': 'b'},
    );
    final s = TransferDocument.decode(signed.encode()) as XmrSignedTransaction;
    expect(s.keyImages, {'a': 'b'});
  });

  test('assinador recusa entrada ilegível sem travar', () {
    final seed = SodiumRuntime.instance.secureCopy(
      Uint8List.fromList(seedBytes),
    );
    expect(
      () => XmrSigner.review(
        XmrSignRequest(
          network: WalletNetwork.testnet,
          sources: ['00ff'],
          knownOutputs: [],
          destinations: [(address: _stagenet, amount: BigInt.one)],
          feeEstimate: {'fee': '20000', 'quantization_mask': '10000'},
        ),
        seed,
      ),
      throwsA(isA<XmrSignException>()),
    );
    seed.dispose();
  });

  test('cache do Monero grava e lê do disco', () async {
    final dir = await Directory.systemTemp.createTemp('xmr-cache-test');
    addTearDown(() => dir.delete(recursive: true));
    final store = XmrCacheStore(dir);
    final cache = XmrCache(
      address: _stagenet,
      network: WalletNetwork.testnet,
      restoreHeight: 100,
      scannedHeight: 150,
      outputs: [
        XmrOwnedOutput(
          outputKey: 'ab',
          txHash: 'cd',
          amount: BigInt.from(123),
          height: 120,
          paymentHex: 'ef',
          keyImage: '01',
        ),
      ],
    );
    await store.save(cache);
    final loaded = await store.load(_stagenet);
    expect(loaded!.scannedHeight, 150);
    expect(loaded.outputs.single.amount, BigInt.from(123));
    expect(loaded.outputs.single.keyImage, '01');
    expect(await store.load(_mainnet), isNull);
  });
}
