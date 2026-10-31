import 'dart:convert';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sodium/sodium_sumo.dart';

import '../core/security/security.dart';
import '../features/network/wallet_network.dart';
import '../features/transfer/transfer_document.dart';
import '../features/wallet/address_check.dart';
import '../features/wallet/watch_only.dart';
import 'cold/sign_review_screen.dart';
import 'theme/app_theme.dart';
import 'theme/coins.dart';
import 'widgets/copy_text.dart';
import 'widgets/file_io.dart';
import 'widgets/page_frame.dart';
import 'widgets/secret_field.dart';
import 'widgets/ui.dart';

/// Assinador frio: seed + Chaves de Vida → Argon2id → seed BIP-39.
///
/// Os campos são limpos assim que a derivação começa. A seed BIP-39 fica em
/// memória protegida (libsodium) só enquanto a sessão estiver aberta, para
/// assinar; ao encerrar ou sair do primeiro plano, tudo é apagado.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  static const _initialAnswers = 3;

  /// Sem nenhuma interação por esse tempo, a sessão é encerrada sozinha.
  static const idleTimeout = Duration(minutes: 10);

  final _mnemonic = TextEditingController();
  final List<TextEditingController> _answers = [
    for (var i = 0; i < _initialAnswers; i++) TextEditingController(),
  ];

  WalletNetwork _network = WalletNetwork.mainnet;
  bool _busy = false;
  String? _error;
  SecureKey? _seed;
  WatchOnlyWallet? _wallet;
  Duration? _argonTime;
  Timer? _idleTimer;
  final _addressToCheck = TextEditingController();
  String? _addressResult;
  bool _addressIsMine = false;

  @override
  void initState() {
    super.initState();
    SessionGuard.instance.register(_wipe);
  }

  @override
  void dispose() {
    SessionGuard.instance.unregister(_wipe);
    _clearSecrets();
    _addressToCheck.dispose();
    _mnemonic.dispose();
    for (final c in _answers) {
      c.dispose();
    }
    super.dispose();
  }

  /// Apaga seed e campos; seguro de chamar em qualquer momento.
  void _clearSecrets() {
    _mnemonic.clear();
    for (final c in _answers) {
      c.clear();
    }
    _seed?.dispose();
    _seed = null;
    _wallet = null;
    _argonTime = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    _addressResult = null;
  }

  /// Reinicia o relógio de inatividade (só com a sessão aberta).
  void _touch() {
    if (_seed == null) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () {
      // Avisa todas as telas com segredos (inclusive a revisão aberta).
      SessionGuard.instance.endSession();
      if (mounted) {
        _snack('Sessão encerrada por inatividade. Tudo foi apagado.');
      }
    });
  }

  void _checkAddress() {
    final wallet = _wallet;
    if (wallet == null) return;
    final found = findAddress(wallet, _addressToCheck.text);
    setState(() {
      _addressIsMine = found != null;
      _addressResult = found == null
          ? 'NÃO pertence a esta carteira (conferidos ETH, SOL, XMR e os '
                'primeiros 500 endereços de recebimento e de troco do BTC e da '
                'Dash). '
                'Não receba nada nele.'
          : 'É seu: ${found.description}.';
    });
  }

  void _wipe() {
    _clearSecrets();
    if (mounted) setState(() {});
  }

  Future<void> _derive() async {
    final mnemonic = _mnemonic.text;
    final answers = [for (final c in _answers) c.text];
    _wipe();
    setState(() {
      _busy = true;
      _error = null;
    });

    SecureKey? lifeKey;
    SecureKey? seed;
    try {
      final problem = Bip39Seed.describeProblem(mnemonic);
      if (problem != null) throw ArgumentError(problem);
      final stopwatch = Stopwatch()..start();
      lifeKey = await LifeKeysPassphrase().derive(answers);
      stopwatch.stop();
      seed = Bip39Seed.deriveSeed(mnemonic: mnemonic, lifeKey: lifeKey);
      final wallet = WatchOnlyWallet.fromSeed(seed, _network);
      if (!mounted) return;
      setState(() {
        _seed = seed;
        seed = null; // agora pertence à sessão
        _wallet = wallet;
        _argonTime = stopwatch.elapsed;
      });
      _touch();
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = '${e.message}');
    } on Exception {
      // Sem detalhes: mensagens de exceção podem conter dados de entrada.
      if (mounted) {
        setState(() => _error = 'Falha na derivação (memória insuficiente?).');
      }
    } finally {
      lifeKey?.dispose();
      seed?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _saveWatchOnly() async {
    final wallet = _wallet!;
    final path = await saveTextFile(
      'carteira-somente-leitura-${wallet.fingerprint}.json',
      const JsonEncoderPretty().convert(wallet.toJson()),
    );
    if (path != null && mounted) {
      _snack('Arquivo salvo. Abra-o na carteira online.');
    }
  }

  Future<void> _signFromFile() async {
    final seed = _seed;
    if (seed == null) return;
    try {
      final text = await pickTextFile(context);
      if (text == null || !mounted) return;
      final document = TransferDocument.decode(text);
      if (document.network != _network) {
        throw FormatException(
          'O arquivo é da rede "${document.network.label}", mas a sessão '
          'está na rede "${_network.label}".',
        );
      }
      final prepared = PreparedSigning.from(document, seed);
      final path = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => SignReviewScreen(prepared: prepared)),
      );
      if (path != null && mounted) {
        _snack(
          'Transação assinada e salva. Leve o arquivo para a carteira '
          'online e transmita.',
        );
      }
    } on Object catch (e) {
      // Arquivo malformado não pode derrubar o assinador.
      if (mounted) _snack('$e'.replaceFirst('FormatException: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _wallet;
    return ModeTheme(
      mode: AppMode.cold,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Assinador frio'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Pill(
                  'Offline',
                  icon: Icons.cloud_off_rounded,
                  color: AppPalette.of(context).accent,
                ),
              ),
            ],
          ),
          body: PageFrame(
            children: wallet == null
                ? _unlockForm(context)
                : _session(context, wallet),
          ),
        ),
      ),
    );
  }

  List<Widget> _unlockForm(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(context);
    return [
      const SizedBox(height: 4),
      Text('Destravar', style: theme.textTheme.headlineSmall),
      const SizedBox(height: 6),
      Text(
        'Seed + Chaves de Vida, passadas pelo Argon2id, abrem a sua carteira. '
        'Nada é gravado; '
        'ao sair, tudo é apagado da memória.',
        style: theme.textTheme.bodyMedium?.copyWith(color: p.muted),
      ),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<WalletNetwork>(
          showSelectedIcon: false,
          segments: [
            for (final n in WalletNetwork.values)
              ButtonSegment(value: n, label: Text(n.label)),
          ],
          selected: {_network},
          onSelectionChanged: _busy
              ? null
              : (selection) => setState(() => _network = selection.first),
        ),
      ),
      const SizedBox(height: 16),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _StepTitle(
              step: 1,
              title: 'Seed',
              subtitle: '24 palavras, separadas por espaço.',
            ),
            const SizedBox(height: 16),
            SecretField(
              controller: _mnemonic,
              label: 'Seed (24 palavras, separadas por espaço)',
              maxLines: 4,
              // Digitar 24 palavras às cegas quase garante erro; o aparelho
              // frio fica sozinho com você. O olho oculta se preferir.
              initiallyVisible: true,
            ),
          ],
        ),
      ),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _StepTitle(
              step: 2,
              title: 'Chaves de Vida',
              subtitle:
                  'Mesma quantidade e mesma ordem de sempre. Acentos, '
                  'maiúsculas e espaços extras são ignorados.',
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < _answers.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SecretField(
                  controller: _answers[i],
                  label: 'Resposta ${i + 1}',
                  textInputAction: i == _answers.length - 1
                      ? TextInputAction.done
                      : TextInputAction.next,
                ),
              ),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Resposta'),
                  onPressed: _busy
                      ? null
                      : () => setState(
                          () => _answers.add(TextEditingController()),
                        ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.remove_rounded),
                  label: const Text('Resposta'),
                  onPressed: _busy || _answers.length <= 1
                      ? null
                      : () => setState(() => _answers.removeLast().dispose()),
                ),
              ],
            ),
          ],
        ),
      ),
      if (_error != null) Notice(kind: NoticeKind.danger, text: _error),
      const SizedBox(height: 4),
      FilledButton(
        onPressed: _busy ? null : _derive,
        child: _busy
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Derivando (Argon2id 512 MiB)…'),
                ],
              )
            : const Text('Derivar'),
      ),
    ];
  }

  List<Widget> _session(BuildContext context, WatchOnlyWallet wallet) {
    final theme = Theme.of(context);
    final p = AppPalette.of(context);
    return [
      AppCard(
        glow: p.accent,
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(Icons.verified_user_outlined, color: p.success),
                const Spacer(),
                Pill(wallet.network.label, color: p.accent),
              ],
            ),
            const SizedBox(height: 18),
            Text('Carteira', style: TextStyle(color: p.muted)),
            SelectableText(
              wallet.fingerprint,
              style: AppTheme.mono(
                fontSize: 32,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${wallet.network.label}. Confira que a impressão digital é '
              'sempre a mesma: se mudar, alguma resposta ou palavra está '
              'diferente.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      FilledButton.icon(
        icon: const Icon(Icons.draw_outlined),
        label: const Text('Assinar transação (abrir arquivo)'),
        onPressed: _signFromFile,
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        icon: const Icon(Icons.save_alt_rounded),
        label: const Text('Salvar arquivo da carteira somente leitura'),
        onPressed: _saveWatchOnly,
      ),
      const SizedBox(height: 8),
      const SectionTitle('Conferir endereço'),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Antes de receber um valor alto, cole aqui o endereço que a '
              'carteira online mostrou. Uma máquina online comprometida '
              'poderia mostrar o endereço de outra pessoa.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _addressToCheck,
              autocorrect: false,
              enableSuggestions: false,
              style: AppTheme.mono(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Endereço',
                suffixIcon: IconButton(
                  tooltip: 'Conferir',
                  icon: const Icon(Icons.search_rounded),
                  onPressed: _checkAddress,
                ),
              ),
              onSubmitted: (_) => _checkAddress(),
            ),
            if (_addressResult != null) ...[
              const SizedBox(height: 12),
              Notice(
                kind: _addressIsMine ? NoticeKind.success : NoticeKind.danger,
                text: _addressResult,
              ),
            ],
          ],
        ),
      ),
      const SectionTitle('Dados somente leitura'),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        child: Text(
          'Dados somente-leitura: permitem VER o saldo em outro aparelho, '
          'nunca gastar.',
          style: theme.textTheme.bodyMedium?.copyWith(color: p.muted),
        ),
      ),
      for (final asset in wallet.assets) AssetCard(asset: asset),
      const SizedBox(height: 8),
      Text(
        'Argon2id: ${_argonTime!.inMilliseconds} ms (${Argon2idParams.v1}). '
        'A sessão se encerra sozinha após ${idleTimeout.inMinutes} minutos '
        'sem uso.',
        style: theme.textTheme.bodySmall?.copyWith(color: p.faint),
      ),
      const SizedBox(height: 20),
      FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
          backgroundColor: p.danger.withValues(alpha: 0.14),
          foregroundColor: p.danger,
        ),
        icon: const Icon(Icons.power_settings_new_rounded),
        onPressed: _wipe,
        label: const Text('Encerrar sessão (apagar da memória)'),
      ),
    ];
  }
}

/// Número do passo + título + explicação.
class _StepTitle extends StatelessWidget {
  const _StepTitle({
    required this.step,
    required this.title,
    required this.subtitle,
  });

  final int step;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            '$step',
            style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// JSON indentado para o arquivo da carteira.
final class JsonEncoderPretty {
  const JsonEncoderPretty();

  String convert(Object? value) =>
      const JsonEncoder.withIndent('  ').convert(value);
}

class AssetCard extends StatefulWidget {
  const AssetCard({super.key, required this.asset});

  final WatchOnlyAsset asset;

  @override
  State<AssetCard> createState() => _AssetCardState();
}

class _AssetCardState extends State<AssetCard> {
  bool _revealSensitive = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(context);
    final asset = widget.asset;
    final coin = CoinStyle.fromTicker(asset.ticker);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (coin != null) ...[
                CoinAvatar(coin, size: 36),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${asset.name} (${asset.ticker})',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      asset.path,
                      style: AppTheme.mono(fontSize: 11.5, color: p.faint),
                    ),
                  ],
                ),
              ),
            ],
          ),
          for (final field in asset.fields) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    field.label,
                    style: TextStyle(
                      color: p.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (field.sensitive) ...[
                  Pill('Sensível', color: p.warning),
                  IconButton(
                    tooltip: _revealSensitive ? 'Ocultar' : 'Mostrar',
                    icon: Icon(
                      _revealSensitive
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _revealSensitive = !_revealSensitive),
                  ),
                ],
              ],
            ),
            if (!field.sensitive || _revealSensitive)
              CopyableText(field.value, label: field.label)
            else
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: p.raised,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(color: p.outline),
                ),
                child: Text(
                  'Oculta: não gasta, mas revela saldo e histórico.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
          const SizedBox(height: 12),
          Text(asset.howToWatch, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
