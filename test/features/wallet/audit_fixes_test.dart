import 'dart:convert';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:brainw4llet/core/security/security.dart';
import 'package:brainw4llet/features/btc/btc_account.dart';
import 'package:brainw4llet/features/btc/btc_signer.dart';
import 'package:brainw4llet/features/evm/evm_send.dart';
import 'package:brainw4llet/features/network/wallet_network.dart';
import 'package:brainw4llet/features/sol/sol_send.dart';
import 'package:brainw4llet/features/transfer/transfer_document.dart';
import 'package:brainw4llet/features/wallet/address_check.dart';
import 'package:brainw4llet/features/wallet/watch_only.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/on_chain.dart';
import 'package:sodium/sodium_sumo.dart';

void main() {
  late SecureKey seed;
  late WatchOnlyWallet wallet;

  setUp(() {
    final bytes = Bip39SeedGenerator(
      Mnemonic.fromString('${'abandon ' * 11}about'),
    ).generate();
    seed = SodiumRuntime.instance.secureCopy(Uint8List.fromList(bytes));
    wallet = WatchOnlyWallet.fromSeed(seed, WalletNetwork.mainnet);
  });
  tearDown(() => seed.dispose());

  group('H1: conferir endereço no assinador', () {
    test('reconhece endereços próprios de cada moeda', () {
      final btc = BtcAccount(wallet.btcAccountKey, wallet.network);
      expect(findAddress(wallet, wallet.ethAddress.toLowerCase()), isNotNull);
      expect(findAddress(wallet, wallet.solAddress), isNotNull);
      expect(findAddress(wallet, wallet.xmrAddress!), isNotNull);
      expect(
        findAddress(wallet, btc.address(0, 5))!.description,
        contains('recebimento nº 5'),
      );
      expect(
        findAddress(
          wallet,
          '  ${btc.address(1, 3).toUpperCase()} ',
        )!.description,
        contains('troco nº 3'),
      );
    });

    test('rejeita endereço de outra pessoa', () {
      expect(
        findAddress(wallet, 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq'),
        isNull,
      );
      expect(
        findAddress(wallet, '0x000000000000000000000000000000000000dEaD'),
        isNull,
      );
      expect(findAddress(wallet, ''), isNull);
    });
  });

  test('M4: impressão digital muda se qualquer campo do arquivo mudar', () {
    final json = wallet.toJson();
    final tampered = WatchOnlyWallet.fromJson({
      ...json,
      'xmrAddress': '4' * 95,
    });
    expect(tampered.fingerprint, isNot(wallet.fingerprint));
    expect(WatchOnlyWallet.fromJson(json).fingerprint, wallet.fingerprint);
  });

  group('H2/M3: Ethereum', () {
    EvmSignRequest request({
      BigInt? maxFeePerGas,
      BigInt? gasLimit,
      List<AccessEntry>? accessList,
    }) {
      final tx = ETHTransaction(
        type: ETHTransactionType.eip1559,
        to: ETHAddress('0x000000000000000000000000000000000000dEaD'),
        nonce: 0,
        gasLimit: gasLimit ?? BigInt.from(21000),
        maxFeePerGas: maxFeePerGas ?? BigInt.from(30000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
        data: const [],
        value: BigInt.parse('1000000000000000000'),
        chainId: BigInt.one,
        accessList: accessList,
      );
      return EvmSignRequest(
        network: WalletNetwork.mainnet,
        unsignedTxHex: BytesUtils.toHexString(tx.serialized, prefix: '0x'),
        from: wallet.ethAddress,
      );
    }

    test('taxa normal não gera alerta', () {
      expect(EvmSend.review(request()).$2.warnings, isEmpty);
    });

    test('taxa absurda e gás incomum geram alertas', () {
      final review = EvmSend.review(
        request(
          maxFeePerGas: BigInt.from(5000) * BigInt.from(1000000000),
          gasLimit: BigInt.from(500000),
        ),
      ).$2;
      expect(review.warnings.length, greaterThanOrEqualTo(3));
    });

    test('lista de acesso é recusada', () {
      expect(
        () => EvmSend.review(
          request(
            accessList: [
              AccessEntry(
                address: ETHAddress(
                  '0x000000000000000000000000000000000000bEEF',
                ),
                storageKeys: const [],
              ),
            ],
          ),
        ),
        throwsA(isA<EvmSendException>()),
      );
    });
  });

  test('H2: Bitcoin alerta taxa anormal', () {
    final review = BtcReview(
      inputsTotal: BigInt.from(1000000),
      outputs: [
        BtcReviewOutput(
          address: 'x',
          amount: BigInt.from(100000),
          isChange: false,
        ),
      ],
      fee: BigInt.from(900000),
      vsize: 110,
    );
    expect(review.warnings.length, 2);
  });

  test('M1: mensagem Solana com índice fora dos limites é recusada', () {
    // header(1,0,1) + 1 chave + blockhash + 1 instrução com programa nº 9.
    final message = <int>[
      1, 0, 1, //
      1, ...List.filled(32, 7),
      ...List.filled(32, 1),
      1, 9, 0, 0,
    ];
    expect(
      () => SolSend.review(
        SolSignRequest(
          network: WalletNetwork.mainnet,
          messageBase64: base64Encode(message),
          from: Base58Encoder.encode(List.filled(32, 7)),
        ),
      ),
      throwsA(isA<SolSendException>()),
    );
  });

  test('M1: arquivo de transferência corrompido dá FormatException', () {
    expect(
      () => TransferDocument.decode('{"format":"brainw4llet-transfer"'),
      throwsFormatException,
    );
    expect(
      () => TransferDocument.decode(
        '{"format":"brainw4llet-transfer","version":1,"kind":"btc-sign-request",'
        '"network":"mainnet","psbt":"x","inputPaths":[[7,1]]}',
      ),
      throwsFormatException,
    );
  });
}
