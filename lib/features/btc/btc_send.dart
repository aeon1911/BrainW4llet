import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';

import '../transfer/transfer_document.dart';
import 'btc_account.dart';
import 'btc_wallet_state.dart';

/// Erro de validação do envio, com mensagem pronta para o usuário.
final class BtcSendException implements Exception {
  const BtcSendException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Plano de envio calculado antes de montar o PSBT.
final class BtcSendPlan {
  const BtcSendPlan({
    required this.destination,
    required this.amount,
    required this.fee,
    required this.inputs,
    required this.change,
    required this.feeRate,
  });

  final BitcoinBaseAddress destination;
  final BigInt amount;
  final BigInt fee;
  final List<BtcOwnedUtxo> inputs;

  /// Valor do troco (zero = sem saída de troco).
  final BigInt change;
  final int feeRate;
}

/// Monta envios na carteira online. Não tem acesso a nenhuma chave privada:
/// produz um PSBT que o assinador frio assina.
abstract final class BtcSend {
  /// Limite de poeira do Bitcoin (P2WPKH); outras moedas: ver a conta.
  static final BigInt dustLimit = BigInt.from(294);

  /// Tamanho virtual (vB) estimado de uma transação P2WPKH.
  static int estimateVsize(int inputs, int outputs) =>
      BtcAccount.estimateP2wpkhSize(inputs, outputs);

  static BitcoinBaseAddress parseAddress(String text, UtxoAccount account) {
    try {
      return account.parseAddress(text);
    } on Object {
      throw BtcSendException(
        'Endereço ${account.coin.name} inválido para esta rede.',
      );
    }
  }

  /// Escolhe as moedas (maiores primeiro, só confirmadas) e calcula taxa e
  /// troco. [amount] nulo = enviar tudo.
  static BtcSendPlan plan({
    required BtcWalletState state,
    required UtxoAccount account,
    required String destination,
    required BigInt? amount,
    required int feeRate,
  }) {
    final to = parseAddress(destination, account);
    if (feeRate < 1) throw const BtcSendException('Taxa mínima: 1 sat/vB.');
    final available = [
      for (final u in state.utxos)
        if (u.confirmed) u,
    ]..sort((a, b) => b.value.compareTo(a.value));
    if (available.isEmpty) {
      throw const BtcSendException('Não há saldo confirmado para enviar.');
    }

    BigInt feeFor(int inputs, int outputs) =>
        BigInt.from(account.estimateSize(inputs, outputs) * feeRate);

    if (amount == null) {
      final total = available.fold(BigInt.zero, (s, u) => s + u.value);
      final fee = feeFor(available.length, 1);
      final send = total - fee;
      if (send < account.dustLimit) {
        throw const BtcSendException('Saldo insuficiente para pagar a taxa.');
      }
      return BtcSendPlan(
        destination: to,
        amount: send,
        fee: fee,
        inputs: available,
        change: BigInt.zero,
        feeRate: feeRate,
      );
    }

    if (amount < account.dustLimit) {
      throw BtcSendException(
        'Valor mínimo: ${account.dustLimit} unidades (satoshis/duffs).',
      );
    }
    final selected = <BtcOwnedUtxo>[];
    var total = BigInt.zero;
    for (final utxo in available) {
      selected.add(utxo);
      total += utxo.value;
      final feeWithChange = feeFor(selected.length, 2);
      final change = total - amount - feeWithChange;
      if (change >= account.dustLimit) {
        return BtcSendPlan(
          destination: to,
          amount: amount,
          fee: feeWithChange,
          inputs: selected,
          change: change,
          feeRate: feeRate,
        );
      }
      final feeNoChange = feeFor(selected.length, 1);
      if (total - amount >= feeNoChange) {
        // Sobra pequena demais para troco: vai junto da taxa.
        return BtcSendPlan(
          destination: to,
          amount: amount,
          fee: total - amount,
          inputs: selected,
          change: BigInt.zero,
          feeRate: feeRate,
        );
      }
    }
    throw const BtcSendException('Saldo confirmado insuficiente.');
  }

  /// Monta o PSBT. Busca as transações de origem completas (non-witness
  /// UTXO) para o assinador poder conferir os valores das entradas.
  static Future<UtxoSignRequest> buildRequest({
    required BtcSendPlan plan,
    required BtcWalletState state,
    required UtxoAccount account,
    required Future<String> Function(String txid) rawTransaction,
  }) async {
    final rawTxs = await Future.wait(
      plan.inputs.map((u) => rawTransaction(u.txid)),
    );
    final psbt = PsbtBuilderV0.create();
    psbt.addUtxos([
      for (var i = 0; i < plan.inputs.length; i++)
        _psbtUtxo(plan.inputs[i], rawTxs[i].trim(), account.scriptType),
    ]);
    psbt.addOutput(
      PsbtTransactionOutput(amount: plan.amount, address: plan.destination),
    );
    BtcPath? changePath;
    if (plan.change > BigInt.zero) {
      changePath = state.nextChange;
      final changeAddress = account.parseAddress(
        account.address(changePath.chain, changePath.index),
      );
      psbt.addOutput(
        PsbtTransactionOutput(amount: plan.change, address: changeAddress),
      );
    }
    return UtxoSignRequest(
      coin: account.coin,
      network: account.network,
      psbtBase64: psbt.toBase64(),
      inputPaths: [for (final u in plan.inputs) u.path],
      changePath: changePath,
    );
  }

  static PsbtUtxo _psbtUtxo(
    BtcOwnedUtxo utxo,
    String rawTxHex,
    BitcoinAddressType scriptType,
  ) {
    final tx = BtcTransaction.deserialize(BytesUtils.fromHexString(rawTxHex));
    if (tx.txId() != utxo.txid) {
      throw const BtcSendException(
        'O servidor devolveu uma transação de origem que não confere.',
      );
    }
    final scriptPubKey = tx.outputs[utxo.vout].scriptPubKey;
    if (tx.outputs[utxo.vout].amount != utxo.value) {
      throw const BtcSendException(
        'Valor da moeda diverge entre servidor e transação de origem.',
      );
    }
    return PsbtUtxo(
      utxo: BitcoinUtxo(
        txHash: utxo.txid,
        value: utxo.value,
        vout: utxo.vout,
        scriptType: scriptType,
        blockHeight: 0,
      ),
      tx: tx,
      scriptPubKey: scriptPubKey,
    );
  }
}
