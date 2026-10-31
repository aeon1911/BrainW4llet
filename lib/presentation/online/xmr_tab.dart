import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/transfer/transfer_document.dart';
import '../../features/wallet/amounts.dart';
import '../../features/wallet/watch_only.dart';
import '../../features/xmr/xmr_wallet.dart';
import '../theme/app_theme.dart';
import '../theme/coins.dart';
import '../widgets/copy_text.dart';
import '../widgets/ui.dart';
import 'chain_tab.dart';
import 'send_screens.dart';
import '../widgets/file_io.dart';
import '../widgets/page_frame.dart';
import 'online_services.dart';

String formatXmr(BigInt piconero) => '${Amounts.format(piconero, 12)} XMR';

/// Cria o observador Monero com o cache no diretório de dados do app.
Future<XmrWatcher> openXmrWatcher(OnlineServices services) async {
  final wallet = services.wallet;
  final dir = await getApplicationSupportDirectory();
  return XmrWatcher(
    address: wallet.xmrAddress!,
    viewKeyHex: wallet.xmrViewKey!,
    network: wallet.network,
    nodeUrl: services.endpoints.xmrNode,
    store: XmrCacheStore(dir),
  );
}

/// Aba Monero: varre a blockchain com a view key (no seu computador),
/// mostra saldo e monta envios. Sem chave de gasto.
class XmrTab extends StatefulWidget {
  const XmrTab({super.key, required this.services});

  final OnlineServices services;

  @override
  State<XmrTab> createState() => _XmrTabState();
}

class _XmrTabState extends State<XmrTab> with AutomaticKeepAliveClientMixin {
  XmrWatcher? _watcher;
  bool _syncing = false;
  int? _current;
  int? _target;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  WatchOnlyWallet get _wallet => widget.services.wallet;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _watcher?.close();
    super.dispose();
  }

  DateTime get _defaultStart =>
      _wallet.createdAt ??
      DateTime.now().toUtc().subtract(const Duration(days: 30));

  Future<void> _start({DateTime? rescanFrom}) async {
    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      final watcher = _watcher ??= await openXmrWatcher(widget.services);
      if (rescanFrom != null) {
        await watcher.rescanFrom(rescanFrom);
      } else if (watcher.cache == null) {
        await watcher.open(_defaultStart);
      }
      await watcher.sync(
        onProgress: (current, target) {
          if (mounted) {
            setState(() {
              _current = current;
              _target = target;
            });
          }
        },
      );
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _exportKeyImageRequest() async {
    final request = _watcher!.keyImageRequest();
    final path = await saveTextFile(
      request.suggestedFileName,
      request.encode(),
    );
    if (path != null) {
      _snack('Pedido salvo. Abra no assinador frio e use "Assinar transação".');
    }
  }

  Future<void> _importKeyImages() async {
    try {
      final text = await pickTextFile();
      if (text == null) return;
      final doc = TransferDocument.decode(text);
      if (doc is! XmrKeyImages || doc.network != _wallet.network) {
        throw const FormatException(
          'Não é um arquivo de key images desta rede.',
        );
      }
      await _watcher!.importKeyImages(doc.keyImages);
      setState(() {});
      _snack('Key images importadas: saldo atualizado.');
    } on Object catch (e) {
      _snack('$e'.replaceFirst('FormatException: ', ''));
    }
  }

  Future<void> _pickRescanDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2014, 4, 18),
      lastDate: DateTime.now(),
      initialDate: _defaultStart.toLocal(),
      helpText: 'Procurar Monero recebido desde',
    );
    if (date != null) await _start(rescanFrom: date);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = AppPalette.of(context);
    final watcher = _watcher;
    final cache = watcher?.cache;
    final balance = cache == null ? null : watcher!.balance();
    final status = <Widget>[
      if (_syncing)
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.radar_rounded, size: 18, color: p.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _target == null
                          ? 'Conectando ao nó…'
                          : 'Varrendo blocos com a view key: '
                                '${_current ?? '…'} de $_target',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: _target == null || _current == null
                    ? null
                    : _progress(cache, _current!, _target!),
              ),
              const SizedBox(height: 12),
              Text(
                'A primeira vez pode levar vários minutos (cerca de 3 '
                'min por dia de histórico). O progresso fica salvo.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      if (_error != null)
        Notice(
          kind: NoticeKind.danger,
          text: _error,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _syncing ? null : _start,
                child: const Text('Tentar de novo'),
              ),
            ),
          ],
        ),
    ];
    if (balance == null) {
      return TwoPane(left: status, right: const []);
    }
    final hero = BalanceHero(
      coin: CoinStyle.xmr,
      balance: formatXmr(balance.unlocked),
      label: 'Saldo desbloqueado',
      onRefresh: _syncing ? null : _start,
      pills: [
        if (balance.locked > BigInt.zero)
          Pill(
            'Bloqueado: ${formatXmr(balance.locked)}',
            icon: Icons.lock_clock_outlined,
            color: p.warning,
          ),
        Pill(
          'Bloco ${cache!.scannedHeight}',
          icon: Icons.layers_outlined,
          color: p.muted,
        ),
      ],
      footer: [
        if (balance.unknownSpentState > 0) ...[
          const SizedBox(height: 14),
          Notice(
            kind: NoticeKind.warning,
            text:
                '${balance.unknownSpentState} moeda(s) sem key image: '
                'se você gastou Monero fora deste app, sincronize as '
                'key images para o saldo ficar exato.',
          ),
        ],
      ],
      actions: [
        FilledButton.icon(
          icon: const Icon(Icons.north_east_rounded),
          label: const Text('Enviar'),
          onPressed: _syncing
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => XmrSendScreen(watcher: watcher!),
                  ),
                ),
        ),
        PopupMenuButton<VoidCallback>(
          tooltip: 'Mais ações',
          enabled: !_syncing,
          onSelected: (action) => action(),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _exportKeyImageRequest,
              child: const Text('Pedir key images'),
            ),
            PopupMenuItem(
              value: _importKeyImages,
              child: const Text('Importar key images'),
            ),
            PopupMenuItem(
              value: _pickRescanDate,
              child: const Text('Varrer desde outra data'),
            ),
          ],
          child: Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.outline),
            ),
            child: Icon(Icons.more_horiz_rounded, color: p.muted),
          ),
        ),
      ],
    );
    final receive = ReceiveCard(
      address: _wallet.xmrAddress!,
      note:
          'Confira-o no assinador frio antes de receber valores altos. '
          'Pagamentos levam 10 confirmações (~20 min) para poderem ser '
          'gastos.',
    );
    final outputs = HistoryCard(
      title: 'Moedas recebidas',
      empty: 'Nenhuma ainda.',
      rows: [
        for (final o in cache.outputs.reversed)
          MovementTile(
            title: o.spent ? 'Gasta' : 'Recebida',
            subtitle: 'bloco ${o.height}',
            amount: formatXmr(o.amount),
            incoming: true,
            muted: o.spent,
            details: [
              CopyableText(
                '${widget.services.endpoints.xmrExplorerTx}${o.txHash}',
                label: 'Link do explorador',
              ),
            ],
          ),
      ],
    );
    return TwoPane(left: [...status, hero, receive], right: [outputs]);
  }

  double _progress(XmrCache? cache, int current, int target) {
    final start = cache?.restoreHeight ?? current;
    final span = target - start;
    return span <= 0 ? 1 : ((current - start) / span).clamp(0, 1).toDouble();
  }
}

/// Monta o pedido de envio Monero (decoys escolhidos aqui, assinatura no
/// assinador frio).
class XmrSendScreen extends StatefulWidget {
  const XmrSendScreen({super.key, required this.watcher});

  final XmrWatcher watcher;

  @override
  State<XmrSendScreen> createState() => _XmrSendScreenState();
}

class _XmrSendScreenState extends State<XmrSendScreen> {
  final _destination = TextEditingController();
  final _amount = TextEditingController();
  bool _sendAll = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _destination.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = await widget.watcher.buildRequest(
        destination: _destination.text,
        amount: _sendAll ? null : Amounts.parse(_amount.text, 12),
      );
      final path = await saveTextFile(
        request.suggestedFileName,
        request.encode(),
      );
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pedido salvo. Leve ao assinador frio, assine e traga de volta '
              'para transmitir.',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on Object catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = widget.watcher.balance();
    return Scaffold(
      appBar: AppBar(title: const Text('Enviar Monero')),
      body: PageFrame(
        children: [
          AvailableCard(formatXmr(balance.unlocked)),
          const SizedBox(height: 8),
          TextField(
            controller: _destination,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Endereço de destino'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            enabled: !_busy && !_sendAll,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor (XMR)'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enviar tudo (saldo menos a taxa)'),
            value: _sendAll,
            onChanged: _busy ? null : (v) => setState(() => _sendAll = v),
          ),
          const Notice(
            kind: NoticeKind.info,
            text:
                'A taxa exata é calculada pelo assinador frio e aparece na '
                'revisão antes de assinar.',
          ),
          if (_error != null) Notice(kind: NoticeKind.danger, text: _error),
          FilledButton.icon(
            icon: const Icon(Icons.save_alt),
            label: Text(
              _busy ? 'Buscando decoys no nó…' : 'Criar arquivo para assinar',
            ),
            onPressed: _busy ? null : _create,
          ),
        ],
      ),
    );
  }
}
