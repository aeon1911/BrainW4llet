import 'dart:typed_data';

import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:brainw4llet/core/security/security.dart';
import 'package:brainw4llet/features/btc/btc_account.dart';
import 'package:brainw4llet/features/btc/btc_send.dart';
import 'package:brainw4llet/features/btc/btc_signer.dart';
import 'package:brainw4llet/features/btc/btc_wallet_state.dart';
import 'package:brainw4llet/features/network/wallet_network.dart';
import 'package:brainw4llet/features/transfer/transfer_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

// Transação assinada conferida por implementação independente em Python
// (hash BIP-143, verificação ECDSA, chave pública ↔ endereço, low-S e txid
// pela serialização legada). A assinatura é determinística (RFC 6979).
const _expectedSignedHex =
    '02000000000102cee6053716e6cb56f3f7b453849d8c2492532aa672ed257bd7a47bc71d943a570000000000ffffffffcee6053716e6cb56f3f7b453849d8c2492532aa672ed257bd7a47bc71d943a570100000000ffffffff02c0d4010000000000160014e8df018c7e326cc253faac7e46cdc51e68542c421b710000000000001600143e34985dca6fddc9fb369940e4c7d8e2873f529c0247304402201297be97aae261481993c2517032755c9adc1e2a6d901d5aa175368f065d63d40220684e1a5fd367050984802dd0d7cf3721f88dcf4a461f28d523dd31ff6afa1e7c01210330d54fd0dd420a6e5f8d3624f5f3482cae350f79d5f0753bf5beef9c2d91af3c0247304402202705b03bbabdd51ad822715ecaf8544e6cd55558be392891192eefa568ac6d6102203f6193f513b87b2d26e10a4075e491db2c388a05c7a9edf8e3af7b1dcddda831012103e775fd51f0dfb8cd865d9ff1cca2a158cf651fe997fdc9fee9c1d3b5e995ea7700000000';
const _expectedTxid =
    'd023fed1d9d53c28f3361e2af8918a6960f199615ca4447227e985686d1c396c';
const _destination = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';

void main() {
  final seedBytes = Bip39SeedGenerator(
    Mnemonic.fromString('${'abandon ' * 11}about'),
  ).generate();
  final account = BtcAccount(
    BtcAccount.accountKeyFromSeed(seedBytes, WalletNetwork.mainnet),
    WalletNetwork.mainnet,
  );
  final a0 = account.address(0, 0);
  final a1 = account.address(0, 1);
  final funding = BtcTransaction(
    inputs: [TxInput(txId: 'aa' * 32, txIndex: 0)],
    outputs: [
      TxOutput(
        amount: BigInt.from(100000),
        scriptPubKey: BitcoinAddress(a0).baseAddress.toScriptPubKey(),
      ),
      TxOutput(
        amount: BigInt.from(50000),
        scriptPubKey: BitcoinAddress(a1).baseAddress.toScriptPubKey(),
      ),
    ],
  );
  final fid = funding.txId();
  final state = BtcWalletState(
    confirmedBalance: BigInt.from(150000),
    unconfirmedBalance: BigInt.zero,
    utxos: [
      BtcOwnedUtxo(
        txid: fid,
        vout: 0,
        value: BigInt.from(100000),
        confirmed: true,
        path: (chain: 0, index: 0),
        address: a0,
      ),
      BtcOwnedUtxo(
        txid: fid,
        vout: 1,
        value: BigInt.from(50000),
        confirmed: true,
        path: (chain: 0, index: 1),
        address: a1,
      ),
    ],
    history: const [],
    nextReceive: (chain: 0, index: 2),
    nextChange: (chain: 1, index: 0),
  );
  late SecureKey seed;

  setUp(() {
    seed = SodiumRuntime.instance.secureCopy(Uint8List.fromList(seedBytes));
  });
  tearDown(() => seed.dispose());

  Future<UtxoSignRequest> request({BigInt? amount}) async {
    final plan = BtcSend.plan(
      state: state,
      account: account,
      destination: _destination,
      amount: amount,
      feeRate: 5,
    );
    final req = await BtcSend.buildRequest(
      plan: plan,
      state: state,
      account: account,
      rawTransaction: (_) async => funding.serialize(),
    );
    // Passa pelo arquivo, como no pendrive.
    return TransferDocument.decode(req.encode()) as UtxoSignRequest;
  }

  test(
    'PSBT → revisão → assinatura confere com a verificação independente',
    () async {
      final req = await request(amount: BigInt.from(120000));
      final review = BtcSigner.review(req, seed);
      expect(review.fee, BigInt.from(1045)); // 209 vB × 5 sat/vB
      expect(review.sending, BigInt.from(120000));
      expect(review.outputs.first.address, _destination);
      expect(review.outputs.last.isChange, isTrue);
      expect(review.outputs.last.address, account.address(1, 0));

      final signed = BtcSigner.sign(req, seed);
      expect(signed.txHex, _expectedSignedHex);
      expect(signed.txid, _expectedTxid);
    },
  );

  test('enviar tudo: uma saída, sem troco', () async {
    final review = BtcSigner.review(await request(), seed);
    expect(review.outputs, hasLength(1));
    expect(review.inputsTotal - review.fee, review.sending);
  });

  test('saldo insuficiente e endereço inválido dão mensagens claras', () {
    expect(
      () => BtcSend.plan(
        state: state,
        account: account,
        destination: _destination,
        amount: BigInt.from(200000),
        feeRate: 5,
      ),
      throwsA(isA<BtcSendException>()),
    );
    expect(
      () => BtcSend.plan(
        state: state,
        account: account,
        destination: 'tb1qxyz',
        amount: BigInt.from(1000),
        feeRate: 5,
      ),
      throwsA(isA<BtcSendException>()),
    );
  });

  test('recusa entrada que não é desta seed (caminho adulterado)', () async {
    final req = await request(amount: BigInt.from(120000));
    final tampered = UtxoSignRequest(
      network: req.network,
      psbtBase64: req.psbtBase64,
      inputPaths: [(chain: 0, index: 5), req.inputPaths[1]],
      changePath: req.changePath,
    );
    expect(
      () => BtcSigner.review(tampered, seed),
      throwsA(
        isA<BtcSendException>().having(
          (e) => e.message,
          'mensagem',
          contains('não pertence'),
        ),
      ),
    );
  });

  test('troco declarado falso não aparece como troco', () async {
    final req = await request(amount: BigInt.from(120000));
    final lying = UtxoSignRequest(
      network: req.network,
      psbtBase64: req.psbtBase64,
      inputPaths: req.inputPaths,
      changePath: (chain: 1, index: 7),
    );
    final review = BtcSigner.review(lying, seed);
    expect(review.outputs.where((o) => o.isChange), isEmpty);
    expect(review.sending, BigInt.from(120000 + 28955));
  });
}
