import 'dart:io';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:brainw4llet/core/security/security.dart';
import 'package:brainw4llet/features/network/wallet_network.dart';
import 'package:brainw4llet/features/transfer/transfer_document.dart';
import 'package:brainw4llet/features/xmr/xmr_keys.dart';
import 'package:brainw4llet/features/xmr/xmr_signer.dart';
import 'package:brainw4llet/features/xmr/xmr_wallet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monero_dart/monero_dart.dart';
import 'package:sodium/sodium_sumo.dart';

// Envio Monero de ponta a ponta, sem rede: uma saída real é criada para a
// seed (como um remetente faria), cercada de 15 decoys, assinada pelo
// XmrSigner e conferida do lado de quem recebe.

const _network = WalletNetwork.testnet;
const _ringSize = 16;
const _realPosition = 5;

/// Resposta típica de `get_fee_estimate` (piconero por byte).
const _feeEstimate = <String, Object?>{
  'fee': '20000',
  'fees': ['20000', '80000', '320000', '4000000'],
  'quantization_mask': '10000',
  'status': 'OK',
  'untrusted': false,
};

final _xmr = BigInt.from(10).pow(12);

List<int> _seed(String mnemonic) =>
    Bip39SeedGenerator(Mnemonic.fromString(mnemonic)).generate();

final _ourSeed = _seed('${'abandon ' * 11}about');
final _otherSeed = _seed('${'zoo ' * 11}wrong');

MoneroAccountKeys _keys(List<int> seed) =>
    XmrKeys.keys(XmrKeys.fullAccount(seed, _network), _network);

SecureKey _secure(List<int> seed) =>
    SodiumRuntime.instance.secureCopy(Uint8List.fromList(seed));

/// Saída de [amount] para [owner], como a carteira online a encontraria
/// com a view key.
({MoneroLockedPayment payment, List<int> commitment}) _incoming(
  MoneroAccountKeys owner,
  BigInt amount, {
  required BigInt globalIndex,
  bool coinbase = false,
}) {
  final txSecret = MoneroPrivateKey.fromBytes(RCT.skGenVar());
  final txPublic = txSecret.publicKey;
  final address = MoneroAddress(owner.account.primaryAddress);
  final out = MoneroTransactionHelper.generateOutputEpemeralKeys(
    txSecretKey: txSecret,
    txPublicKey: txPublic,
    address: address,
    outIndex: 0,
  );
  final derivation = MoneroTransactionHelper.isAccountOut(
    viewSecretKey: owner.account.privVkey,
    txPubkey: txPublic.key,
    outIndex: 0,
    viewTag: null,
  )!;
  final mask = RCT.skGenVar();
  return (
    payment: MoneroLockedPayment(
      output: MoneroLockedOutput(
        amount: amount,
        mask: mask,
        derivation: derivation,
        outputPublicKey: out.txOut.getPublicKeyBytes()!,
        accountIndex: const MoneroSubIndex.unsafe(),
        unlockTime: BigInt.zero,
        realIndex: 0,
        coinbase: coinbase,
      ),
      txPubkey: txPublic.key,
      paymentId: null,
      encryptedPaymentid: null,
      globalIndex: globalIndex,
    ),
    commitment: RCT.commit(xmrAmount: amount, mask: mask),
  );
}

/// Anel de [_ringSize] membros com a saída real na posição [_realPosition],
/// índices globais crescentes.
SpendablePayment<MoneroLockedPayment> _spendable(
  ({MoneroLockedPayment payment, List<int> commitment}) real, {
  List<int>? ringCommitment,
  bool shuffle = false,
}) {
  final realIndex = real.payment.globalIndex;
  final outs = [
    for (var i = 0; i < _ringSize; i++)
      i == _realPosition
          ? OutsEntery(
              index: realIndex,
              key: CtKey(
                dest: real.payment.output.outputPublicKey,
                mask: ringCommitment ?? real.commitment,
              ),
            )
          : OutsEntery(
              index: realIndex + BigInt.from((i - _realPosition) * 37),
              key: CtKey(dest: RCT.pkGenVar(), mask: RCT.pkGenVar()),
            ),
  ];
  var position = _realPosition;
  if (shuffle) {
    final first = outs.removeAt(0);
    outs.add(first);
    position -= 1;
  }
  return SpendablePayment(
    payment: real.payment,
    outs: outs,
    realOutIndex: position,
  );
}

XmrSignRequest _request(
  List<SpendablePayment<MoneroLockedPayment>> sources, {
  required String destination,
  required BigInt amount,
}) => XmrSignRequest(
  network: _network,
  sources: [for (final s in sources) BytesUtils.toHexString(s.serialize())],
  knownOutputs: [
    for (final s in sources) BytesUtils.toHexString(s.payment.serialize()),
  ],
  destinations: [(address: destination, amount: amount)],
  feeEstimate: _feeEstimate,
);

/// Valores que [owner] consegue decifrar na transação, por saída.
List<BigInt> _received(MoneroTransaction tx, MoneroAccountKeys owner) => [
  for (var i = 0; i < tx.vout.length; i++)
    ?MoneroTransactionHelper.getLockedOutputs(
      realIndex: i,
      tx: tx,
      account: owner,
    )?.amount,
];

void main() {
  final ours = _keys(_ourSeed);
  final other = _keys(_otherSeed);
  final destination = other.account.primaryAddress;

  test('envio com troco: assina, verifica e o destinatário recebe o valor', () {
    final input = _incoming(ours, _xmr, globalIndex: BigInt.from(4_000_000));
    final amount = BigInt.from(250_000_000_000); // 0,25 XMR
    final request = _request(
      [_spendable(input)],
      destination: destination,
      amount: amount,
    );
    // Passa pelo arquivo, como no fluxo real.
    final decoded = TransferDocument.decode(request.encode()) as XmrSignRequest;

    final seed = _secure(_ourSeed);
    addTearDown(seed.dispose);
    final review = XmrSigner.review(decoded, seed);
    expect(review.amount, amount);
    expect(review.inputs, 1);
    expect(review.inputsTotal, _xmr);
    expect(review.fee, greaterThan(BigInt.zero));
    expect(review.fee, lessThan(BigInt.from(100_000_000))); // < 0,0001 XMR
    expect(review.change, _xmr - amount - review.fee);
    expect(review.warnings, isEmpty);

    final signed = XmrSigner.sign(decoded, seed);
    final tx = MoneroTransaction.deserialize(
      BytesUtils.fromHexString(signed.txHex),
    );
    expect(tx.getTxHash(), signed.txHash);
    expect(tx.vin, hasLength(1));
    expect(tx.vout, hasLength(2));
    expect(tx.signature.cast<RCTSignature>().signature.txnFee, review.fee);
    expect(_received(tx, other), [amount]);
    expect(_received(tx, ours), [review.change]);

    // Key image devolvida = a da entrada gasta na transação.
    final keyImage =
        signed.keyImages[BytesUtils.toHexString(
          input.payment.output.outputPublicKey,
        )];
    final txIn = tx.vin.single as TxinToKey;
    expect(keyImage, BytesUtils.toHexString(txIn.keyImage.keyImage));

    // O arquivo assinado sobrevive à ida e volta.
    final back =
        TransferDocument.decode(signed.encode()) as XmrSignedTransaction;
    expect(back.txHex, signed.txHex);
  });

  test('enviar tudo (valor 0) com duas entradas: sem troco', () {
    final a = _incoming(ours, _xmr, globalIndex: BigInt.from(3_000_000));
    final b = _incoming(
      ours,
      BigInt.from(500_000_000_000),
      globalIndex: BigInt.from(3_100_000),
    );
    final request = _request(
      [_spendable(a), _spendable(b)],
      destination: destination,
      amount: BigInt.zero,
    );
    final seed = _secure(_ourSeed);
    addTearDown(seed.dispose);
    final review = XmrSigner.review(request, seed);
    final total = _xmr + BigInt.from(500_000_000_000);
    expect(review.inputs, 2);
    expect(review.change, BigInt.zero);
    expect(review.amount, total - review.fee);

    final signed = XmrSigner.sign(request, seed);
    final tx = MoneroTransaction.deserialize(
      BytesUtils.fromHexString(signed.txHex),
    );
    expect(tx.vin, hasLength(2));
    expect(tx.signature.cast<RCTSignature>().signature.txnFee, review.fee);
    expect(_received(tx, other), [review.amount]);
    expect(signed.keyImages, hasLength(2));
  });

  test('entrada de outra seed é recusada', () {
    final theirs = _incoming(other, _xmr, globalIndex: BigInt.from(5_000_000));
    final seed = _secure(_ourSeed);
    addTearDown(seed.dispose);
    expect(
      () => XmrSigner.review(
        _request(
          [_spendable(theirs)],
          destination: destination,
          amount: BigInt.one,
        ),
        seed,
      ),
      throwsA(
        isA<XmrSignException>().having(
          (e) => e.message,
          'mensagem',
          contains('não pertence'),
        ),
      ),
    );
  });

  test('anel sem a saída real é recusado', () {
    final input = _incoming(ours, _xmr, globalIndex: BigInt.from(6_000_000));
    final spendable = _spendable(input);
    final tampered = SpendablePayment(
      payment: spendable.payment,
      outs: [
        for (final (i, o) in spendable.outs.indexed)
          i == _realPosition
              ? OutsEntery(
                  index: o.index,
                  key: CtKey(dest: RCT.pkGenVar(), mask: o.key.mask),
                )
              : o,
      ],
      realOutIndex: _realPosition,
    );
    final seed = _secure(_ourSeed);
    addTearDown(seed.dispose);
    expect(
      () => XmrSigner.review(
        _request([tampered], destination: destination, amount: BigInt.one),
        seed,
      ),
      throwsA(isA<XmrSignException>()),
    );
  });

  test('valor declarado que não bate com o commitment do anel é recusado', () {
    final input = _incoming(ours, _xmr, globalIndex: BigInt.from(7_000_000));
    // Online diz 1 XMR, mas o commitment no anel é de 0,1 XMR.
    final wrong = RCT.commit(
      xmrAmount: BigInt.from(100_000_000_000),
      mask: input.payment.output.mask,
    );
    final seed = _secure(_ourSeed);
    addTearDown(seed.dispose);
    expect(
      () => XmrSigner.review(
        _request(
          [_spendable(input, ringCommitment: wrong)],
          destination: destination,
          amount: BigInt.one,
        ),
        seed,
      ),
      throwsA(
        isA<XmrSignException>().having(
          (e) => e.message,
          'mensagem',
          contains('valor'),
        ),
      ),
    );
  });

  test('anel fora de ordem ou do tamanho errado é recusado', () {
    final input = _incoming(ours, _xmr, globalIndex: BigInt.from(8_000_000));
    final seed = _secure(_ourSeed);
    addTearDown(seed.dispose);
    final shuffled = _spendable(input, shuffle: true);
    final small = SpendablePayment(
      payment: input.payment,
      outs: [shuffled.outs[_realPosition - 1]],
      realOutIndex: 0,
    );
    for (final bad in [shuffled, small]) {
      expect(
        () => XmrSigner.review(
          _request([bad], destination: destination, amount: BigInt.one),
          seed,
        ),
        throwsA(
          isA<XmrSignException>().having(
            (e) => e.message,
            'mensagem',
            contains('anel'),
          ),
        ),
      );
    }
  });

  test('destino na rede principal é recusado num pedido da stagenet', () {
    final input = _incoming(ours, _xmr, globalIndex: BigInt.from(9_000_000));
    final mainnet = XmrKeys.fullAccount(
      _otherSeed,
      WalletNetwork.mainnet,
    ).primaryAddress;
    final seed = _secure(_ourSeed);
    addTearDown(seed.dispose);
    expect(
      () => XmrSigner.review(
        _request([_spendable(input)], destination: mainnet, amount: BigInt.one),
        seed,
      ),
      throwsA(isA<XmrSignException>()),
    );
  });

  test('taxa inflada pela carteira online gera alerta na revisão', () {
    final input = _incoming(ours, _xmr, globalIndex: BigInt.from(9_500_000));
    final request = XmrSignRequest(
      network: _network,
      sources: [BytesUtils.toHexString(_spendable(input).serialize())],
      knownOutputs: const [],
      destinations: [(address: destination, amount: BigInt.from(10).pow(10))],
      feeEstimate: {..._feeEstimate, 'fee': '20000000'},
    );
    final seed = _secure(_ourSeed);
    addTearDown(seed.dispose);
    expect(XmrSigner.review(request, seed).warnings, isNotEmpty);
  });

  test('recompensa de mineração só desbloqueia com 60 confirmações', () {
    final watcher = XmrWatcher(
      address: ours.account.primaryAddress,
      viewKeyHex: BytesUtils.toHexString(ours.account.privateViewKey.raw),
      network: _network,
      nodeUrl: 'http://127.0.0.1:1',
      store: XmrCacheStore(Directory.systemTemp),
    );
    addTearDown(watcher.close);
    XmrOwnedOutput owned(String key, {required bool coinbase}) {
      final p = _incoming(
        ours,
        _xmr,
        globalIndex: BigInt.one,
        coinbase: coinbase,
      ).payment;
      return XmrOwnedOutput(
        outputKey: key,
        txHash: key,
        amount: _xmr,
        height: 1000,
        paymentHex: BytesUtils.toHexString(p.serialize()),
      );
    }

    watcher
      ..cache = XmrCache(
        address: ours.account.primaryAddress,
        network: _network,
        restoreHeight: 900,
        scannedHeight: 1030,
        outputs: [owned('a', coinbase: false), owned('b', coinbase: true)],
      )
      ..tipHeight = 1030;
    expect(watcher.spendable().map((o) => o.outputKey), ['a']);
    expect(watcher.balance().locked, _xmr);
    watcher.tipHeight = 1060;
    expect(watcher.spendable(), hasLength(2));
  });
}
