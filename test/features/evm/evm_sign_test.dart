import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:brainw4llet/core/security/security.dart';
import 'package:brainw4llet/features/evm/evm_send.dart';
import 'package:brainw4llet/features/network/wallet_network.dart';
import 'package:brainw4llet/features/transfer/transfer_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/on_chain.dart';
import 'package:sodium/sodium_sumo.dart';

// Conferido em Python: pré-imagem = transação não assinada, ecrecover da
// assinatura devolve 0x9858…da94, low-S e hash Keccak da transação.
const _from = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94';
const _expectedSigned =
    '0x02f87301078459682f008506fc23ac0082520894000000000000000000000000000000000000dead881111d67bb1bb000080c080a02a113a762b86d5c68794b73209a8d781e5b9d851a789805691d99bb4af9fb1dda055393535ba8ab72b3359c3c05f4e8f935fcaddc7035e0e419415514694f4d3b4';
const _expectedHash =
    '0xdd49f9c6a871e1d04f8df67d3de35a98d3567969a04361cf801161ab53492352';

EvmSignRequest _request({
  int chainId = 1,
  List<int> data = const [],
  WalletNetwork network = WalletNetwork.mainnet,
  String from = _from,
}) {
  final tx = ETHTransaction(
    type: ETHTransactionType.eip1559,
    to: ETHAddress('0x000000000000000000000000000000000000dEaD'),
    nonce: 7,
    gasLimit: BigInt.from(21000),
    maxFeePerGas: BigInt.from(30000000000),
    maxPriorityFeePerGas: BigInt.from(1500000000),
    data: data,
    value: BigInt.parse('1230000000000000000'),
    chainId: BigInt.from(chainId),
  );
  final request = EvmSignRequest(
    network: network,
    unsignedTxHex: BytesUtils.toHexString(tx.serialized, prefix: '0x'),
    from: from,
  );
  return TransferDocument.decode(request.encode()) as EvmSignRequest;
}

void main() {
  late SecureKey seed;

  setUp(() {
    final bytes = Bip39SeedGenerator(
      Mnemonic.fromString('${'abandon ' * 11}about'),
    ).generate();
    seed = SodiumRuntime.instance.secureCopy(Uint8List.fromList(bytes));
  });
  tearDown(() => seed.dispose());

  test('revisão mostra destino, valor e taxa máxima', () {
    final review = EvmSend.review(_request()).$2;
    expect(review.to, '0x000000000000000000000000000000000000dEaD');
    expect(review.value, BigInt.parse('1230000000000000000'));
    expect(review.maxFee, BigInt.from(21000 * 30000000000));
    expect(review.nonce, 7);
  });

  test('assinatura confere com a verificação independente', () {
    final signed = EvmSend.sign(_request(), seed);
    expect(signed.signedTxHex, _expectedSigned);
    expect(signed.txHash, _expectedHash);
  });

  test('recusa rede trocada (chainId diferente da rede do arquivo)', () {
    expect(
      () => EvmSend.review(_request(chainId: 11155111)),
      throwsA(isA<EvmSendException>()),
    );
  });

  test('recusa chamada de contrato nesta versão', () {
    expect(
      () => EvmSend.review(_request(data: [0xa9, 0x05, 0x9c, 0xbb])),
      throwsA(isA<EvmSendException>()),
    );
  });

  test('recusa remetente que não é desta seed', () {
    expect(
      () => EvmSend.sign(
        _request(from: '0x000000000000000000000000000000000000bEEF'),
        seed,
      ),
      throwsA(isA<EvmSendException>()),
    );
  });
}
