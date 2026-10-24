import 'dart:convert';

import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter/material.dart';
import 'package:on_chain/on_chain.dart';

import '../../features/btc/btc_account.dart';
import '../../features/sol/sol_send.dart';
import '../../features/transfer/transfer_document.dart';
import '../widgets/copy_text.dart';
import '../widgets/file_io.dart';
import '../widgets/format.dart';
import '../widgets/page_frame.dart';
import 'online_services.dart';

/// Abre a transação assinada pelo assinador frio, mostra o que ela faz e
/// transmite para a rede.
class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key, required this.services});

  final OnlineServices services;

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  TransferDocument? _document;
  List<String> _summary = const [];
  bool _busy = false;
  String? _error;
  String? _resultId;
  String? _resultUrl;

  Future<void> _open() async {
    final text = await pickTextFile();
    if (text == null) return;
    setState(() {
      _error = null;
      _document = null;
      _resultId = null;
    });
    try {
      final document = TransferDocument.decode(text);
      if (document.network != widget.services.wallet.network) {
        throw FormatException(
          'A transação é da rede "${document.network.label}", mas a carteira '
          'aberta é da rede "${widget.services.wallet.network.label}".',
        );
      }
      setState(() {
        _summary = _describe(document);
        _document = document;
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on Object catch (e) {
      setState(() => _error = 'Arquivo inválido: $e');
    }
  }

  List<String> _describe(TransferDocument document) {
    final services = widget.services;
    switch (document) {
      case final UtxoSignedTransaction doc:
        if (doc.coin == UtxoCoin.dash && !services.hasDash) {
          throw const FormatException('Esta carteira não tem Dash nesta rede.');
        }
        final tx = BtcTransaction.deserialize(
          BytesUtils.fromHexString(doc.txHex),
        );
        final network = UtxoAccount.addressNetworkFor(doc.coin, doc.network);
        return [
          '${doc.coin.name} · txid ${shorten(doc.txid)}',
          for (final out in tx.outputs)
            '→ ${BitcoinScriptUtils.generateAddressFromScriptPubKey(out.scriptPubKey).toAddress(network)}: '
                '${formatUtxo(doc.coin, out.amount)}',
        ];
      case final EvmSignedTransaction doc:
        final tx = ETHTransaction.fromSerialized(
          BytesUtils.fromHexString(doc.signedTxHex),
        );
        return [
          'Ethereum · hash ${shorten(doc.txHash)}',
          '→ ${tx.to?.address}: ${formatEth(tx.value)}',
        ];
      case final SolSignedTransaction doc:
        final bytes = base64Decode(doc.txBase64);
        // Reaproveita o decodificador do assinador: também confere que o
        // pagador é esta carteira.
        final review = SolSend.review(
          SolSignRequest(
            network: doc.network,
            messageBase64: base64Encode(bytes.sublist(65)),
            from: services.wallet.solAddress,
          ),
        );
        return [
          'Solana · ${shorten(doc.signature)}',
          '→ ${review.to}: ${formatSol(review.lamports)}',
        ];
      default:
        throw const FormatException(
          'Este arquivo é um pedido de assinatura, não uma transação '
          'assinada. Assine-o primeiro no assinador frio.',
        );
    }
  }

  Future<void> _broadcast() async {
    final services = widget.services;
    final endpoints = services.endpoints;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (id, url) = switch (_document!) {
        final UtxoSignedTransaction doc => switch (doc.coin) {
          UtxoCoin.bitcoin => (
            await services.esplora.broadcast(doc.txHex),
            endpoints.btcExplorerTx,
          ),
          UtxoCoin.dash => (
            await services.dash!.broadcast(doc.txHex),
            endpoints.dashExplorerTx!,
          ),
        },
        final EvmSignedTransaction doc => (
          await services.evm.broadcast(doc.signedTxHex),
          endpoints.evmExplorerTx,
        ),
        final SolSignedTransaction doc => (
          await services.sol.broadcast(doc.txBase64),
          endpoints.solExplorerTx,
        ),
        _ => throw StateError('tipo inesperado'),
      };
      final suffix = switch (_document) {
        SolSignedTransaction() => endpoints.solExplorerSuffix,
        UtxoSignedTransaction(coin: UtxoCoin.dash) =>
          endpoints.dashExplorerSuffix,
        _ => '',
      };
      setState(() {
        _resultId = id;
        _resultUrl = '$url$id$suffix';
      });
    } on Exception catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Transmitir transação assinada')),
      body: PageFrame(
        children: [
          if (_resultId != null) ...[
            Icon(Icons.check_circle, size: 48, color: Colors.green.shade400),
            const SizedBox(height: 8),
            Text(
              'Transmitida! Acompanhe a confirmação no explorador:',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            CopyableText(_resultId!, label: 'Identificador'),
            CopyableText(_resultUrl!, label: 'Link'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Voltar à carteira'),
            ),
          ] else ...[
            Text(
              'Abra o arquivo que o assinador frio salvou '
              '(btc-, dash-, eth- ou sol-assinada.json).',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.file_open),
              label: const Text('Abrir transação assinada'),
              onPressed: _busy ? null : _open,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (_document != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in _summary)
                        SelectableText(
                          line,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.send),
                label: Text(_busy ? 'Transmitindo…' : 'Transmitir agora'),
                onPressed: _busy ? null : _broadcast,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
