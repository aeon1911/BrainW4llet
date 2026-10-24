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
import 'package:brainw4llet/features/wallet/watch_only.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

// Conferido em Python (assinatura legada SIGHASH_ALL, low-S, chave pública ↔
// endereço de origem, endereços "X…" e txid).
const _expectedSignedHex =
    '0200000001d3a87c6fcdde175b83d8cd78b1c9977081772b594497aca7349efc59d2138ce2000000006a473044022029bd08ffc08287f7099d148d32fcf6716a74b08879996c786b7ec1a86484a0d202204410612fd3c00f3fae85885c334d0bf97e516d8cef9db58b5579507f54f961e70121026fa9a6f213b6ba86447965f6b4821264aaadd7521f049f00db9c43a770ea7405ffffffff0240420f00000000001976a914f7428a48ad30725069624a35874523e5157c19c188ac1e083d00000000001976a914265a7d4ef63d643548a599c8fa53a0d9ef3fdca488ac00000000';
const _expectedTxid =
    '23b3f238dabed9f0c335e8d9235e5ca7cbbcfdbdde079850a612bd86f1635a40';
const _destination = 'XyEESvmAig9ypH3yuHXLTuJZsAU9fKxj4W';

void main() {
  final seedBytes = Bip39SeedGenerator(
    Mnemonic.fromString('${'abandon ' * 11}about'),
  ).generate();
  late SecureKey seed;
  late DashAccount account;
  late BtcTransaction funding;
  late BtcWalletState state;

  setUp(() {
    seed = SodiumRuntime.instance.secureCopy(Uint8List.fromList(seedBytes));
    final wallet = WatchOnlyWallet.fromSeed(seed, WalletNetwork.mainnet);
    account = DashAccount(wallet.dashAccountKey!, WalletNetwork.mainnet);
    final a0 = account.address(0, 0);
    funding = BtcTransaction(
      inputs: [TxInput(txId: 'cc' * 32, txIndex: 0)],
      outputs: [
        TxOutput(
          amount: BigInt.from(5000000),
          scriptPubKey: account.parseAddress(a0).toScriptPubKey(),
        ),
      ],
    );
    state = BtcWalletState(
      confirmedBalance: BigInt.from(5000000),
      unconfirmedBalance: BigInt.zero,
      utxos: [
        BtcOwnedUtxo(
          txid: funding.txId(),
          vout: 0,
          value: BigInt.from(5000000),
          confirmed: true,
          path: (chain: 0, index: 0),
          address: a0,
        ),
      ],
      history: const [],
      nextReceive: (chain: 0, index: 1),
      nextChange: (chain: 1, index: 0),
    );
  });
  tearDown(() => seed.dispose());

  Future<UtxoSignRequest> request() async {
    final plan = BtcSend.plan(
      state: state,
      account: account,
      destination: _destination,
      amount: BigInt.from(1000000),
      feeRate: 1,
    );
    final req = await BtcSend.buildRequest(
      plan: plan,
      state: state,
      account: account,
      rawTransaction: (_) async => funding.serialize(),
    );
    return TransferDocument.decode(req.encode()) as UtxoSignRequest;
  }

  test('endereços Dash batem com a derivação independente', () {
    expect(account.address(0, 0), 'XoJA8qE3N2Y3jMLEtZ3vcN42qseZ8LvFf5');
  });

  test('PSBT Dash → revisão → assinatura confere com a verificação '
      'independente', () async {
    final req = await request();
    expect(req.kind, 'dash-sign-request');
    expect(req.coin, UtxoCoin.dash);
    final review = BtcSigner.review(req, seed);
    expect(review.fee, BigInt.from(226)); // 226 bytes × 1 duff/B
    expect(review.outputs.first.address, _destination);
    expect(review.outputs.last.isChange, isTrue);
    expect(review.warnings, isEmpty);

    final signed = BtcSigner.sign(req, seed);
    expect(signed.kind, 'dash-signed');
    expect(signed.txHex, _expectedSignedHex);
    expect(signed.txid, _expectedTxid);
  });

  test('recusa endereço Bitcoin como destino de Dash', () {
    expect(
      () => BtcSend.plan(
        state: state,
        account: account,
        destination: 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
        amount: BigInt.from(100000),
        feeRate: 1,
      ),
      throwsA(isA<BtcSendException>()),
    );
  });

  test('recusa PSBT Dash rotulado como Bitcoin (confusão de moeda)', () async {
    final req = await request();
    final relabeled = UtxoSignRequest(
      network: req.network,
      psbtBase64: req.psbtBase64,
      inputPaths: req.inputPaths,
      changePath: req.changePath,
    );
    expect(
      () => BtcSigner.review(relabeled, seed),
      throwsA(isA<BtcSendException>()),
    );
  });

  test('recusa SIGHASH_NONE também no Dash', () {
    final mine = account.parseAddress(account.address(0, 0));
    final psbt = PsbtBuilderV0.create()
      ..addOutput(
        PsbtTransactionOutput(
          amount: BigInt.from(4000000),
          address: account.parseAddress(_destination),
        ),
      )
      ..addInput(
        PsbtTransactionInput.legacy(
          outIndex: 0,
          txId: funding.txId(),
          amount: BigInt.from(5000000),
          scriptPubKey: mine.toScriptPubKey(),
          nonWitnessUtxo: funding,
          sigHashType: BitcoinOpCodeConst.sighashNone,
        ),
      );
    final req = UtxoSignRequest(
      coin: UtxoCoin.dash,
      network: WalletNetwork.mainnet,
      psbtBase64: psbt.toBase64(),
      inputPaths: const [(chain: 0, index: 0)],
    );
    expect(() => BtcSigner.sign(req, seed), throwsA(isA<BtcSendException>()));
  });
}
