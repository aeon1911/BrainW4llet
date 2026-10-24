import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:on_chain/on_chain.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../core/security/memory.dart';
import '../network/endpoints.dart';
import '../network/wallet_network.dart';
import '../transfer/transfer_document.dart';
import 'evm_client.dart';

/// Erro de validação, com mensagem pronta para o usuário.
final class EvmSendException implements Exception {
  const EvmSendException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// O que o assinador frio mostra antes de assinar.
final class EvmReview {
  const EvmReview({
    required this.to,
    required this.value,
    required this.maxFee,
    required this.nonce,
    required this.chainId,
    required this.gasLimit,
    required this.maxFeePerGas,
    required this.maxPriorityFeePerGas,
  });

  static final BigInt _gwei = BigInt.from(1000000000);

  final BigInt gasLimit;
  final BigInt maxFeePerGas;
  final BigInt maxPriorityFeePerGas;

  /// Alertas para o usuário confirmar explicitamente antes de assinar.
  List<String> get warnings => [
    if (gasLimit != EvmSend.transferGas)
      'Limite de gás incomum para uma transferência simples: $gasLimit.',
    if (maxFeePerGas > BigInt.from(500) * _gwei)
      'Preço máximo de gás anormal: ${maxFeePerGas ~/ _gwei} gwei.',
    if (maxPriorityFeePerGas > BigInt.from(50) * _gwei)
      'Gorjeta anormal: ${maxPriorityFeePerGas ~/ _gwei} gwei.',
    if (value > BigInt.zero && maxFee * BigInt.from(10) > value)
      'A taxa máxima passa de 10% do valor enviado.',
  ];

  final String to;
  final BigInt value;

  /// Taxa máxima possível (gasLimit × maxFeePerGas); a real costuma ser menor.
  final BigInt maxFee;
  final int nonce;
  final int chainId;
}

/// Envio de ETH nativo (fase 1: sem tokens nem contratos).
abstract final class EvmSend {
  static final BigInt transferGas = BigInt.from(21000);

  static ETHAddress parseAddress(String text) {
    try {
      return ETHAddress(text.trim());
    } on Exception {
      throw const EvmSendException('Endereço Ethereum inválido.');
    }
  }

  /// Lado online: monta a transação EIP-1559 sem assinatura.
  /// [amount] nulo = enviar tudo (saldo menos a taxa máxima).
  static Future<EvmSignRequest> buildRequest({
    required WalletNetwork network,
    required String from,
    required String to,
    required BigInt? amount,
    required EvmClient client,
  }) async {
    final destination = parseAddress(to);
    await client.checkChain();
    final balance = await client.balance(from);
    final nonce = await client.nonce(from);
    final fees = await client.fees();
    final maxFee = transferGas * fees.maxFeePerGas;
    final value = amount ?? balance - maxFee;
    if (value <= BigInt.zero) {
      throw const EvmSendException('Saldo insuficiente para pagar a taxa.');
    }
    if (value + maxFee > balance) {
      throw const EvmSendException(
        'Saldo insuficiente para o valor mais a taxa máxima.',
      );
    }
    final tx = ETHTransaction(
      type: ETHTransactionType.eip1559,
      from: ETHAddress(from),
      to: destination,
      nonce: nonce,
      gasLimit: transferGas,
      maxFeePerGas: fees.maxFeePerGas,
      maxPriorityFeePerGas: fees.maxPriorityFee,
      data: const [],
      value: value,
      chainId: BigInt.from(client.chainId),
    );
    return EvmSignRequest(
      network: network,
      unsignedTxHex: BytesUtils.toHexString(tx.serialized, prefix: '0x'),
      from: from,
    );
  }

  /// Lado frio: decodifica e valida a transação sem confiar nos metadados.
  static (ETHTransaction, EvmReview) review(EvmSignRequest request) {
    final ETHTransaction tx;
    try {
      tx = ETHTransaction.fromSerialized(
        BytesUtils.fromHexString(request.unsignedTxHex),
      );
    } on Exception {
      throw const EvmSendException('Transação Ethereum inválida.');
    }
    final expectedChain = Endpoints.defaults(request.network).evmChainId;
    if (tx.chainId != BigInt.from(expectedChain)) {
      throw EvmSendException(
        'A transação é da rede ${tx.chainId}, esperado $expectedChain.',
      );
    }
    if (tx.type != ETHTransactionType.eip1559) {
      throw const EvmSendException('Só transações EIP-1559 são aceitas.');
    }
    if (tx.accessList?.isNotEmpty ?? false) {
      throw const EvmSendException('Lista de acesso inesperada. Recusado.');
    }
    if (tx.data.isNotEmpty || tx.to == null) {
      throw const EvmSendException(
        'Por segurança, esta versão só assina transferências simples de ETH '
        '(sem contrato).',
      );
    }
    return (
      tx,
      EvmReview(
        to: tx.to!.address,
        value: tx.value,
        maxFee: tx.gasLimit * (tx.maxFeePerGas ?? BigInt.zero),
        nonce: tx.nonce,
        chainId: expectedChain,
        gasLimit: tx.gasLimit,
        maxFeePerGas: tx.maxFeePerGas ?? BigInt.zero,
        maxPriorityFeePerGas: tx.maxPriorityFeePerGas ?? BigInt.zero,
      ),
    );
  }

  /// Lado frio: assina com a chave de m/44'/60'/0'/0/0.
  static EvmSignedTransaction sign(EvmSignRequest request, SecureKey seed) {
    final (tx, _) = review(request);
    final signed = seed.runUnlockedSync((bytes) {
      final raw = Bip44.fromSeed(
        bytes,
        Bip44Coins.ethereum,
      ).deriveDefaultPath.privateKey.raw;
      try {
        final key = ETHPrivateKey.fromBytes(raw);
        if (key.publicKey().toAddress().address.toLowerCase() !=
            request.from.toLowerCase()) {
          throw const EvmSendException(
            'O remetente não é desta carteira (seed, respostas ou rede '
            'diferentes).',
          );
        }
        return tx.signedSerialized(key.sign(tx.serialized));
      } finally {
        wipeBytes(raw);
      }
    });
    return EvmSignedTransaction(
      network: request.network,
      signedTxHex: BytesUtils.toHexString(signed, prefix: '0x'),
      txHash: BytesUtils.toHexString(
        QuickCrypto.keccack256Hash(signed),
        prefix: '0x',
      ),
    );
  }
}
