import 'package:flutter/material.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../core/security/security.dart';
import '../../features/btc/btc_signer.dart';
import '../../features/evm/evm_send.dart';
import '../../features/sol/sol_send.dart';
import '../../features/transfer/transfer_document.dart';
import '../widgets/file_io.dart';
import '../widgets/format.dart';
import '../widgets/page_frame.dart';

/// Uma linha da revisão.
final class ReviewRow {
  const ReviewRow(this.label, this.value, {this.emphasis = false});

  final String label;
  final String value;
  final bool emphasis;
}

/// Pedido de assinatura já validado, pronto para revisão.
final class PreparedSigning {
  const PreparedSigning({
    required this.title,
    required this.rows,
    required this.sign,
    this.warning,
    this.alerts = const [],
  });

  final String title;
  final List<ReviewRow> rows;
  final String? warning;

  /// Situações anormais: exigem confirmação explícita antes de assinar.
  final List<String> alerts;
  final TransferDocument Function() sign;

  /// Valida o pedido e calcula tudo a partir da própria transação. Lança
  /// exceções com mensagem pronta para o usuário.
  static PreparedSigning from(TransferDocument document, SecureKey seed) =>
      switch (document) {
        final UtxoSignRequest request => _btc(request, seed),
        final EvmSignRequest request => _evm(request, seed),
        final SolSignRequest request => _sol(request, seed),
        _ => throw const FormatException(
          'Este arquivo não é um pedido de assinatura.',
        ),
      };

  static PreparedSigning _btc(UtxoSignRequest request, SecureKey seed) {
    final review = BtcSigner.review(request, seed);
    final coin = request.coin;
    String fmt(BigInt v) => formatUtxo(coin, v);
    return PreparedSigning(
      title: 'Assinar envio de ${coin.name}',
      rows: [
        for (final out in review.outputs)
          ReviewRow(
            out.isChange ? 'Troco (volta para você)' : 'Enviar para',
            '${out.address}\n${fmt(out.amount)}',
            emphasis: !out.isChange,
          ),
        ReviewRow(
          'Taxa da rede',
          '${fmt(review.fee)} '
              '(~${review.feeRate.toStringAsFixed(1)} ${coin.feeUnit})',
        ),
        ReviewRow(
          'Total que sai da carteira',
          fmt(review.sending + review.fee),
          emphasis: true,
        ),
      ],
      alerts: review.warnings,
      sign: () => BtcSigner.sign(request, seed),
    );
  }

  static PreparedSigning _evm(EvmSignRequest request, SecureKey seed) {
    final review = EvmSend.review(request).$2;
    return PreparedSigning(
      title: 'Assinar envio de Ethereum',
      rows: [
        ReviewRow('Enviar para', review.to, emphasis: true),
        ReviewRow('Valor', formatEth(review.value), emphasis: true),
        ReviewRow('Taxa máxima', formatEth(review.maxFee)),
        ReviewRow('Rede', review.chainId == 1 ? 'Ethereum' : 'Sepolia (teste)'),
        ReviewRow('Nonce', '${review.nonce}'),
      ],
      alerts: review.warnings,
      sign: () => EvmSend.sign(request, seed),
    );
  }

  static PreparedSigning _sol(SolSignRequest request, SecureKey seed) {
    final review = SolSend.review(request);
    return PreparedSigning(
      title: 'Assinar envio de Solana',
      rows: [
        ReviewRow('Enviar para', review.to, emphasis: true),
        ReviewRow('Valor', formatSol(review.lamports), emphasis: true),
        ReviewRow('Taxa', formatSol(review.fee)),
      ],
      warning:
          'Transações Solana expiram em cerca de 1 minuto: assine e '
          'transmita logo. Se expirar, gere o pedido de novo.',
      sign: () => SolSend.sign(request, seed),
    );
  }
}

/// Mostra exatamente o que será assinado e salva a transação assinada.
class SignReviewScreen extends StatefulWidget {
  const SignReviewScreen({super.key, required this.prepared});

  final PreparedSigning prepared;

  @override
  State<SignReviewScreen> createState() => _SignReviewScreenState();
}

class _SignReviewScreenState extends State<SignReviewScreen> {
  bool _busy = false;
  bool _alertsAccepted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SessionGuard.instance.register(_close);
  }

  @override
  void dispose() {
    SessionGuard.instance.unregister(_close);
    super.dispose();
  }

  void _close() {
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _signAndSave() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final signed = widget.prepared.sign();
      final path = await saveTextFile(
        signed.suggestedFileName,
        signed.encode(),
      );
      if (!mounted) return;
      if (path != null) Navigator.of(context).pop(path);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prepared = widget.prepared;
    return Scaffold(
      appBar: AppBar(title: Text(prepared.title)),
      body: PageFrame(
        children: [
          Text(
            'Confira com calma. Estes dados foram lidos da própria transação, '
            'não do que a carteira online declarou.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          for (final row in prepared.rows)
            Card(
              child: ListTile(
                title: Text(row.label, style: theme.textTheme.labelLarge),
                subtitle: SelectableText(
                  row.value,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: row.emphasis ? FontWeight.bold : null,
                  ),
                ),
              ),
            ),
          if (prepared.warning != null) ...[
            const SizedBox(height: 8),
            Text(
              prepared.warning!,
              style: TextStyle(color: theme.colorScheme.tertiary),
            ),
          ],
          if (prepared.alerts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ATENÇÃO',
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    for (final alert in prepared.alerts)
                      Text(
                        '• $alert',
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _alertsAccepted,
                      onChanged: (v) =>
                          setState(() => _alertsAccepted = v ?? false),
                      title: Text(
                        'Entendi e quero assinar mesmo assim',
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.draw),
            label: const Text('Assinar e salvar arquivo'),
            onPressed: _busy || (prepared.alerts.isNotEmpty && !_alertsAccepted)
                ? null
                : _signAndSave,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }
}
