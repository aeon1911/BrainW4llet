import 'package:flutter/material.dart';

import '../widgets/copy_text.dart';

/// Uma linha do histórico, já formatada.
final class HistoryRow {
  const HistoryRow({
    required this.id,
    required this.amount,
    required this.incoming,
    required this.when,
    required this.explorerUrl,
    this.failed = false,
  });

  final String id;
  final String amount;
  final bool incoming;
  final String when;
  final String explorerUrl;
  final bool failed;
}

/// Estado de uma moeda depois de consultar a rede.
final class ChainSnapshot<T> {
  const ChainSnapshot({
    required this.balance,
    required this.receiveAddress,
    required this.history,
    required this.raw,
    this.pending,
    this.receiveNote,
    this.historyError,
  });

  final String balance;
  final String? pending;
  final String receiveAddress;
  final String? receiveNote;
  final List<HistoryRow> history;
  final String? historyError;

  /// Dados completos para a tela de envio (ex.: UTXOs do Bitcoin).
  final T raw;
}

/// Aba de uma moeda: saldo, receber, histórico e enviar.
class ChainTab<T> extends StatefulWidget {
  const ChainTab({super.key, required this.load, required this.onSend});

  final Future<ChainSnapshot<T>> Function() load;

  /// Abre a tela de envio; devolve true se um arquivo foi criado.
  final Future<void> Function(BuildContext context, ChainSnapshot<T> snapshot)
  onSend;

  @override
  State<ChainTab<T>> createState() => _ChainTabState<T>();
}

class _ChainTabState<T> extends State<ChainTab<T>>
    with AutomaticKeepAliveClientMixin {
  Future<ChainSnapshot<T>>? _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  void _refresh() => setState(() => _future = widget.load());

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return FutureBuilder<ChainSnapshot<T>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${snap.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _refresh,
                    child: const Text('Tentar de novo'),
                  ),
                ],
              ),
            ),
          );
        }
        final data = snap.data!;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Saldo', style: theme.textTheme.labelLarge),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Atualizar',
                              icon: const Icon(Icons.refresh),
                              onPressed: _refresh,
                            ),
                          ],
                        ),
                        SelectableText(
                          data.balance,
                          style: theme.textTheme.headlineSmall,
                        ),
                        if (data.pending != null)
                          Text(data.pending!, style: theme.textTheme.bodySmall),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          icon: const Icon(Icons.north_east),
                          label: const Text('Enviar'),
                          onPressed: () async {
                            await widget.onSend(context, data);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Receber', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 4),
                        CopyableText(data.receiveAddress, label: 'Endereço'),
                        if (data.receiveNote != null)
                          Text(
                            data.receiveNote!,
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Histórico', style: theme.textTheme.titleMedium),
                if (data.historyError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      data.historyError!,
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else if (data.history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Nenhuma transação ainda.'),
                  ),
                for (final row in data.history) _HistoryTile(row: row),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.row});

  final HistoryRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = row.failed
        ? theme.colorScheme.error
        : row.incoming
        ? Colors.green.shade400
        : theme.colorScheme.onSurface;
    return Card(
      child: ExpansionTile(
        leading: Icon(
          row.failed
              ? Icons.error_outline
              : row.incoming
              ? Icons.south_west
              : Icons.north_east,
          color: color,
        ),
        title: Text(
          row.failed ? '${row.amount} (falhou)' : row.amount,
          style: TextStyle(color: color, fontFamily: 'monospace'),
        ),
        subtitle: Text(row.when),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CopyableText(row.id, label: 'Identificador'),
                CopyableText(row.explorerUrl, label: 'Link do explorador'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
