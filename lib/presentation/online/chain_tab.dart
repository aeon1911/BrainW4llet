import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/coins.dart';
import '../widgets/copy_text.dart';
import '../widgets/ui.dart';

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
  const ChainTab({
    super.key,
    required this.coin,
    required this.load,
    required this.onSend,
  });

  final CoinStyle coin;
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
    final p = AppPalette.of(context);
    return FutureBuilder<ChainSnapshot<T>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CoinAvatar(widget.coin, size: 48),
                const SizedBox(height: 20),
                const SizedBox(width: 140, child: LinearProgressIndicator()),
                const SizedBox(height: 12),
                Text('Consultando a rede…', style: TextStyle(color: p.muted)),
              ],
            ),
          );
        }
        if (snap.hasError) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Notice(
                      kind: NoticeKind.danger,
                      title: 'Não foi possível consultar a rede',
                      text: '${snap.error}',
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: _refresh,
                      label: const Text('Tentar de novo'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final data = snap.data!;
        final hero = BalanceHero(
          coin: widget.coin,
          balance: data.balance,
          pills: [
            if (data.pending != null)
              Pill(
                data.pending!,
                icon: Icons.schedule_rounded,
                color: p.warning,
              ),
          ],
          onRefresh: _refresh,
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.north_east_rounded),
              label: const Text('Enviar'),
              onPressed: () async {
                await widget.onSend(context, data);
              },
            ),
          ],
        );
        final receive = ReceiveCard(
          address: data.receiveAddress,
          note: data.receiveNote,
        );
        final history = HistoryCard(
          title: 'Histórico',
          error: data.historyError,
          empty: 'Nenhuma transação ainda.',
          rows: [for (final row in data.history) _HistoryTile(row: row)],
        );
        return TwoPane(left: [hero, receive], right: [history]);
      },
    );
  }
}

/// Uma coluna no celular; duas no desktop (saldo à esquerda, lista à
/// direita).
class TwoPane extends StatelessWidget {
  const TwoPane({super.key, required this.left, required this.right});

  final List<Widget> left;
  final List<Widget> right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [...left, ...right],
              ),
            ),
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 420,
                    child: ListView(
                      padding: const EdgeInsets.only(top: 8, bottom: 32),
                      children: left,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(top: 8, bottom: 32),
                      children: right,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Cartão principal: moeda, saldo grande e ações.
class BalanceHero extends StatelessWidget {
  const BalanceHero({
    super.key,
    required this.coin,
    required this.balance,
    required this.actions,
    this.pills = const [],
    this.footer = const [],
    this.onRefresh,
    this.label = 'Saldo',
  });

  final CoinStyle coin;
  final String balance;
  final String label;
  final List<Widget> pills;
  final List<Widget> footer;
  final List<Widget> actions;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    return AppCard(
      glow: coin.color,
      padding: const EdgeInsets.fromLTRB(22, 20, 14, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CoinAvatar(coin, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(coin.label, style: theme.textTheme.titleMedium),
                    Text(label, style: TextStyle(color: p.muted, fontSize: 13)),
                  ],
                ),
              ),
              if (onRefresh != null)
                IconButton(
                  tooltip: 'Atualizar',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: onRefresh,
                ),
            ],
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AmountText(balance),
          ),
          if (pills.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: pills),
          ],
          ...footer,
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                for (final (i, a) in actions.indexed) ...[
                  if (i > 0) const SizedBox(width: 10),
                  i == 0 ? Expanded(child: a) : a,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Endereço de recebimento com QR.
class ReceiveCard extends StatelessWidget {
  const ReceiveCard({super.key, required this.address, this.note});

  final String address;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.south_west_rounded, size: 18, color: p.accent),
              const SizedBox(width: 8),
              Text('Receber', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 18),
          Center(child: QrView(address, size: 188)),
          const SizedBox(height: 18),
          CopyableText(address, label: 'Endereço'),
          if (note != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.verified_user_outlined,
                    size: 16,
                    color: p.faint,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(note!, style: theme.textTheme.bodySmall)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Lista de movimentos dentro de um cartão.
class HistoryCard extends StatelessWidget {
  const HistoryCard({
    super.key,
    required this.title,
    required this.rows,
    required this.empty,
    this.error,
  });

  final String title;
  final List<Widget> rows;
  final String empty;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title),
        if (error != null)
          Notice(kind: NoticeKind.warning, text: error)
        else if (rows.isEmpty)
          AppCard(
            child: Column(
              children: [
                Icon(Icons.inbox_outlined, size: 36, color: p.faint),
                const SizedBox(height: 10),
                Text(empty, style: TextStyle(color: p.muted)),
              ],
            ),
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final (i, row) in rows.indexed) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Divider(color: p.outline),
                    ),
                  row,
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Linha de movimento: ícone de direção, título, data e valor.
class MovementTile extends StatelessWidget {
  const MovementTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.incoming,
    this.failed = false,
    this.muted = false,
    this.details = const [],
  });

  final String title;
  final String subtitle;
  final String amount;
  final bool incoming;
  final bool failed;

  /// Esmaecida (ex.: moeda Monero já gasta).
  final bool muted;
  final List<Widget> details;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final color = failed
        ? p.danger
        : muted
        ? p.faint
        : incoming
        ? p.success
        : Theme.of(context).colorScheme.onSurface;
    final iconColor = failed
        ? p.danger
        : (incoming && !muted ? p.success : p.muted);
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(
          failed
              ? Icons.error_outline_rounded
              : incoming
              ? Icons.south_west_rounded
              : Icons.north_east_rounded,
          color: iconColor,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Text(subtitle, style: TextStyle(color: p.muted, fontSize: 13)),
      trailing: Text(
        amount,
        style: AppTheme.mono(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      children: details,
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.row});

  final HistoryRow row;

  @override
  Widget build(BuildContext context) {
    return MovementTile(
      title: row.failed
          ? 'Falhou'
          : row.incoming
          ? 'Recebido'
          : 'Enviado',
      subtitle: row.when,
      amount: row.amount,
      incoming: row.incoming,
      failed: row.failed,
      details: [
        CopyableText(row.id, label: 'Identificador'),
        CopyableText(row.explorerUrl, label: 'Link do explorador'),
      ],
    );
  }
}
