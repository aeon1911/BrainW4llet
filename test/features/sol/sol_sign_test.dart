import 'dart:convert';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:brainw4llet/core/security/security.dart';
import 'package:brainw4llet/features/network/wallet_network.dart';
import 'package:brainw4llet/features/sol/sol_send.dart';
import 'package:brainw4llet/features/transfer/transfer_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/solana/solana.dart';
import 'package:sodium/sodium_sumo.dart';

// Conferido em Python: parser independente da mensagem legacy e verificação
// Ed25519 da assinatura sobre os bytes exatos que vão para a rede.
const _from = 'HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk';
const _to = '9eaiUBgyT7EY1go2qrCmdRZMisYkGdtrrem3TgP9WSDb';
const _blockhash = 'EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N';
const _expectedTx =
    'AaLT/lyB/sSh0dLcv1CbowyMfFXOMpGbp7zbJlIej9pz8tNsDDYRHnbnrQXLRbbqIryiaTwLOJc//LbNEidhZAEBAAED8DYnYkanW53jNJ7UKxXiMvZRj8IPX81PHWToH5vSWPeAfhtj58JBxyRI6PnwXmXUIepAzq5A9HyjR/fXnDjQ5gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAzEkOkozS44c7s0P8ldozF5ymD02/RsLDbpEpnVXU5rkBAgIAAQwCAAAAFc1bBwAAAAA=';
const _expectedSignature =
    '4FpMPKWNrsDbCS9vV7o6cGfU6odRQa2cGXrXYSxFWpj98ezuntSLoLnLGy2rDxk9h6dYG5VCzUsXLe3zDV5xUfGU';

SolSignRequest _request(List<int> message, {String from = _from}) =>
    TransferDocument.decode(
          SolSignRequest(
            network: WalletNetwork.mainnet,
            messageBase64: base64Encode(message),
            from: from,
          ).encode(),
        )
        as SolSignRequest;

List<int> _transfer({String from = _from}) => SolSend.transferMessage(
  from: SolAddress(from),
  to: SolAddress(_to),
  lamports: BigInt.from(123456789),
  blockhash: _blockhash,
);

void main() {
  late SecureKey seed;

  setUp(() {
    final bytes = Bip39SeedGenerator(
      Mnemonic.fromString('${'abandon ' * 11}about'),
    ).generate();
    seed = SodiumRuntime.instance.secureCopy(Uint8List.fromList(bytes));
  });
  tearDown(() => seed.dispose());

  test('revisão decodifica origem, destino e valor', () {
    final review = SolSend.review(_request(_transfer()));
    expect(review.from, _from);
    expect(review.to, _to);
    expect(review.lamports, BigInt.from(123456789));
  });

  test('assinatura confere com a verificação independente', () {
    final signed = SolSend.sign(_request(_transfer()), seed);
    expect(signed.txBase64, _expectedTx);
    expect(signed.signature, _expectedSignature);
  });

  test('recusa remetente que não é desta seed', () {
    final other = _transfer(from: _to);
    expect(
      () => SolSend.sign(_request(other, from: _to), seed),
      throwsA(isA<SolSendException>()),
    );
  });

  test('recusa metadado "from" diferente do pagador da mensagem', () {
    expect(
      () => SolSend.review(_request(_transfer(), from: _to)),
      throwsA(isA<SolSendException>()),
    );
  });

  test('recusa instrução que não é transferência simples', () {
    final message = SolanaTransaction(
      instructions: [
        SystemProgram.assign(
          layout: SystemAssignLayout(programId: SolAddress(_to)),
          account: SolAddress(_from),
        ),
      ],
      recentBlockhash: SolAddress(_blockhash),
      payerKey: SolAddress(_from),
      type: TransactionType.legacy,
    ).serializeMessage();
    expect(
      () => SolSend.review(_request(message)),
      throwsA(isA<SolSendException>()),
    );
  });
}
