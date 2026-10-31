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
import '../theme/app_theme.dart';
import '../widgets/page_frame.dart';
import '../widgets/ui.dart';
import 'online_services.dart';
import '../../features/xmr/xmr_wallet.dart';
import 'xmr_tab.dart';

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
    try {
      final text = await pickTextFile();
      if (text == null) return;
      setState(() {
        _error = null;
        _document = null;
        _resultId = null;
      });
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
            'para ${BitcoinScriptUtils.generateAddressFromScriptPubKey(out.scriptPubKey).toAddress(network)}: '
                '${formatUtxo(doc.coin, out.amount)}',
        ];
      case final EvmSignedTransaction doc:
        final tx = ETHTransaction.fromSerialized(
          BytesUtils.fromHexString(doc.signedTxHex),
        );
        return [
          'Ethereum · hash ${shorten(doc.txHash)}',
          'para ${tx.to?.address}: ${formatEth(tx.value)}',
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
          'para ${review.to}: ${formatSol(review.lamports)}',
        ];
      case final XmrSignedTransaction doc:
        return [
          'Monero · ${shorten(doc.txHash)}',
          '${doc.keyImages.length} key image(s) serão importadas.',
        ];
      case final XmrKeyImages doc:
        return [
          'Key images do Monero: ${doc.keyImages.length}',
          'Nada é transmitido; só atualiza o saldo.',
        ];
      default:
        throw const FormatException(
          'Este arquivo é um pedido de assinatura, não uma transação '
          'assinada. Assine-o primeiro no assinador frio.',
        );
    }
  }

  /// Usa o mesmo cache da aba Monero (transmite e importa key images).
  Future<String> _withXmr(Future<String> Function(XmrWatcher) action) async {
    final watcher = await openXmrWatcher(widget.services);
    try {
      final created = widget.services.wallet.createdAt ?? DateTime.now();
      await watcher.open(created);
      return await action(watcher);
    } finally {
      watcher.close();
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
        final XmrSignedTransaction doc => (
          await _withXmr((w) => w.broadcast(doc)),
          endpoints.xmrExplorerTx,
        ),
        final XmrKeyImages doc => (
          await _withXmr((w) async {
            await w.importKeyImages(doc.keyImages);
            return 'key images importadas';
          }),
          '',
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
        _resultUrl = url.isEmpty ? null : '$url$id$suffix';
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
    final p = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Transmitir transação assinada')),
      body: PageFrame(
        children: [
          if (_resultId != null) ...[
            const SizedBox(height: 12),
            IconBadge(Icons.check_rounded, color: p.success, size: 64),
            const SizedBox(height: 18),
            Text(
              'Transmitida! Acompanhe a confirmação no explorador:',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            CopyableText(_resultId!, label: 'Identificador'),
            if (_resultUrl != null) CopyableText(_resultUrl!, label: 'Link'),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Voltar à carteira'),
            ),
          ] else ...[
            Text(
              'Abra o arquivo que o assinador frio salvou '
              '(btc-, dash-, eth-, sol- ou xmr-assinada.json, ou as key images do '
              'Monero).',
              style: theme.textTheme.bodyMedium?.copyWith(color: p.muted),
            ),
            const SizedBox(height: 16),
            AppCard(
              onTap: _busy ? null : _open,
              glow: p.accent,
              padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
              child: Column(
                children: [
                  Icon(Icons.file_open_outlined, size: 32, color: p.accent),
                  const SizedBox(height: 10),
                  Text(
                    'Abrir transação assinada',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            if (_error != null) Notice(kind: NoticeKind.danger, text: _error),
            if (_document != null) ...[
              const SectionTitle('Conteúdo'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in _summary)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: SelectableText(
                          line,
                          style: AppTheme.mono(
                            fontSize: 13.5,
                            height: 1.5,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.cell_tower_rounded),
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
