import 'dart:typed_data';

import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:brainw4llet/core/security/security.dart';
import 'package:brainw4llet/features/btc/btc_account.dart';
import 'package:brainw4llet/features/btc/btc_send.dart';
import 'package:brainw4llet/features/btc/btc_signer.dart';
import 'package:brainw4llet/features/network/wallet_network.dart';
import 'package:brainw4llet/features/transfer/transfer_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

/// Ataques que uma carteira online comprometida poderia tentar contra o
/// assinador frio. Todos precisam ser recusados.
void main() {
  final seedBytes = Bip39SeedGenerator(
    Mnemonic.fromString('${'abandon ' * 11}about'),
  ).generate();
  final account = BtcAccount(
    BtcAccount.accountKeyFromSeed(seedBytes, WalletNetwork.mainnet),
    WalletNetwork.mainnet,
  );
  final mine = BitcoinAddress(account.address(0, 0));
  final funding = BtcTransaction(
    inputs: [TxInput(txId: 'bb' * 32, txIndex: 0)],
    outputs: [
      TxOutput(
        amount: BigInt.from(100000),
        scriptPubKey: mine.baseAddress.toScriptPubKey(),
      ),
    ],
  );
  late SecureKey seed;

  setUp(() {
    seed = SodiumRuntime.instance.secureCopy(Uint8List.fromList(seedBytes));
  });
  tearDown(() => seed.dispose());

  UtxoSignRequest maliciousPsbt({int? sigHash}) {
    // Saída antes da entrada: a biblioteca não deixa mudar saídas depois
    // que uma entrada declara o tipo de assinatura.
    final psbt = PsbtBuilderV0.create()
      ..addOutput(
        PsbtTransactionOutput(
          amount: BigInt.from(99000),
          address: BitcoinAddress(
            'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
          ).baseAddress,
        ),
      )
      ..addInput(
        PsbtTransactionInput.witnessV0(
          outIndex: 0,
          txId: funding.txId(),
          amount: BigInt.from(100000),
          scriptPubKey: mine.baseAddress.toScriptPubKey(),
          nonWitnessUtxo: funding,
          sigHashType: sigHash,
        ),
      );
    return UtxoSignRequest(
      network: WalletNetwork.mainnet,
      psbtBase64: psbt.toBase64(),
      inputPaths: const [(chain: 0, index: 0)],
    );
  }

  for (final (name, sighash) in [
    ('SIGHASH_NONE', BitcoinOpCodeConst.sighashNone),
    ('SIGHASH_SINGLE', BitcoinOpCodeConst.sighashSingle),
    (
      'SIGHASH_ALL|ANYONECANPAY',
      BitcoinOpCodeConst.sighashAll | BitcoinOpCodeConst.sighashAnyoneCanPay,
    ),
  ]) {
    test('recusa PSBT que pede $name (redirecionamento após assinar)', () {
      final request = maliciousPsbt(sigHash: sighash);
      expect(
        () => BtcSigner.review(request, seed),
        throwsA(isA<BtcSendException>()),
      );
      expect(
        () => BtcSigner.sign(request, seed),
        throwsA(isA<BtcSendException>()),
      );
    });
  }

  test('PSBT sem tipo declarado é assinado com SIGHASH_ALL', () {
    final signed = BtcSigner.sign(maliciousPsbt(), seed);
    final tx = BtcTransaction.deserialize(
      BytesUtils.fromHexString(signed.txHex),
    );
    final signature = BytesUtils.fromHexString(tx.witnesses.single.stack[0]);
    expect(signature.last, BitcoinOpCodeConst.sighashAll);
  });

  test('PSBT com SIGHASH_ALL explícito é aceito', () {
    final signed = BtcSigner.sign(
      maliciousPsbt(sigHash: BitcoinOpCodeConst.sighashAll),
      seed,
    );
    expect(signed.txid, isNotEmpty);
  });

  test('arquivo de transferência continua íntegro após ida e volta', () {
    final request = maliciousPsbt();
    final decoded =
        TransferDocument.decode(request.encode()) as UtxoSignRequest;
    expect(decoded.psbtBase64, request.psbtBase64);
  });

  test('dust limit e send-all não quebram com uma única moeda', () {
    expect(BtcSend.dustLimit, BigInt.from(294));
  });
}
