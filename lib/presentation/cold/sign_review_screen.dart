import 'package:flutter/material.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../core/security/security.dart';
import '../../features/btc/btc_signer.dart';
import '../../features/evm/evm_send.dart';
import '../../features/sol/sol_send.dart';
import '../../features/transfer/transfer_document.dart';
import '../../features/wallet/amounts.dart';
import '../../features/xmr/xmr_signer.dart';
import '../widgets/file_io.dart';
import '../widgets/format.dart';
import '../theme/app_theme.dart';
import '../widgets/page_frame.dart';
import '../widgets/ui.dart';

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
        final XmrSignRequest request => _xmr(request, seed),
        final XmrKeyImageRequest request => _xmrKeyImages(request, seed),
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

  static String _fmtXmr(BigInt v) => '${Amounts.format(v, 12)} XMR';

  static PreparedSigning _xmr(XmrSignRequest request, SecureKey seed) {
    final review = XmrSigner.review(request, seed);
    return PreparedSigning(
      title: 'Assinar envio de Monero',
      rows: [
        ReviewRow('Enviar para', review.destination, emphasis: true),
        ReviewRow('Valor', _fmtXmr(review.amount), emphasis: true),
        ReviewRow('Taxa (calculada aqui)', _fmtXmr(review.fee)),
        if (review.change > BigInt.zero)
          ReviewRow('Troco (volta para você)', _fmtXmr(review.change)),
        ReviewRow('Moedas usadas', '${review.inputs}'),
      ],
      warning:
          'Depois de assinar, a assinatura é conferida aqui mesmo (CLSAG e '
          'Bulletproofs+). O arquivo assinado também leva as key images, para '
          'a carteira online saber o que foi gasto.',
      alerts: review.warnings,
      sign: () => XmrSigner.sign(request, seed),
    );
  }

  static PreparedSigning _xmrKeyImages(
    XmrKeyImageRequest request,
    SecureKey seed,
  ) => PreparedSigning(
    title: 'Gerar key images do Monero',
    rows: [
      ReviewRow('Moedas a conferir', '${request.knownOutputs.length}'),
      const ReviewRow(
        'O que é',
        'Key images permitem à carteira online saber quais moedas já foram '
            'gastas. Não permitem gastar nada.',
      ),
    ],
    sign: () => XmrSigner.keyImages(request, seed),
  );

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
  Widget build(BuildContext context) => ModeTheme(
    mode: AppMode.cold,
    child: Builder(builder: _build),
  );

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(context);
    final prepared = widget.prepared;
    // As duas primeiras linhas em destaque (destino e valor) viram o resumo.
    final main = prepared.rows.where((r) => r.emphasis).toList();
    final rest = prepared.rows.where((r) => !r.emphasis).toList();
    final blocked = prepared.alerts.isNotEmpty && !_alertsAccepted;
    return Scaffold(
      appBar: AppBar(title: Text(prepared.title)),
      body: PageFrame(
        children: [
          Text(
            'Confira com calma. Estes dados foram lidos da própria transação, '
            'não do que a carteira online declarou.',
            style: theme.textTheme.bodyMedium?.copyWith(color: p.muted),
          ),
          const SizedBox(height: 16),
          if (main.isNotEmpty)
            AppCard(
              glow: p.accent,
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, row) in main.indexed) ...[
                    if (i > 0) const SizedBox(height: 18),
                    Text(
                      row.label,
                      style: TextStyle(color: p.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    if (_looksLikeAmount(row.value))
                      AmountText(row.value, fontSize: 30)
                    else
                      SelectableText(
                        row.value,
                        style: AppTheme.mono(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          if (rest.isNotEmpty)
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                children: [
                  for (final (i, row) in rest.indexed) ...[
                    if (i > 0) Divider(color: p.outline),
                    KeyValueRow(row.label, row.value),
                  ],
                ],
              ),
            ),
          if (prepared.warning != null)
            Notice(kind: NoticeKind.info, text: prepared.warning),
          if (prepared.alerts.isNotEmpty)
            Notice(
              kind: NoticeKind.danger,
              title: 'ATENÇÃO',
              children: [
                for (final alert in prepared.alerts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $alert'),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: p.danger,
                  value: _alertsAccepted,
                  onChanged: (v) =>
                      setState(() => _alertsAccepted = v ?? false),
                  title: const Text('Entendi e quero assinar mesmo assim'),
                ),
              ],
            ),
          if (_error != null) Notice(kind: NoticeKind.danger, text: _error),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.draw_outlined),
            label: const Text('Assinar e salvar arquivo'),
            onPressed: _busy || blocked ? null : _signAndSave,
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  /// "0.01 BTC" → valor; endereços e textos longos não.
  static bool _looksLikeAmount(String value) =>
      RegExp(r'^[+\-−]?[\d.,]+ [A-Z]{2,5}$').hasMatch(value);
}
