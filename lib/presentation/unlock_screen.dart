import 'dart:convert';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sodium/sodium_sumo.dart';

import '../core/security/security.dart';
import '../features/network/wallet_network.dart';
import '../features/transfer/transfer_document.dart';
import '../features/wallet/address_check.dart';
import '../features/wallet/watch_only.dart';
import 'cold/sign_review_screen.dart';
import 'widgets/file_io.dart';
import 'widgets/page_frame.dart';
import 'widgets/secret_field.dart';

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
                'primeiros 500 endereços de recebimento e de troco do BTC). '
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
    final text = await pickTextFile();
    if (text == null || !mounted) return;
    try {
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
    return Scaffold(
      appBar: AppBar(title: const Text('Assinador frio (offline)')),
      body: PageFrame(
        children: wallet == null
            ? _unlockForm(context)
            : _session(context, wallet),
      ),
    );
  }

  List<Widget> _unlockForm(BuildContext context) {
    final theme = Theme.of(context);
    return [
      SegmentedButton<WalletNetwork>(
        segments: [
          for (final n in WalletNetwork.values)
            ButtonSegment(value: n, label: Text(n.label)),
        ],
        selected: {_network},
        onSelectionChanged: _busy
            ? null
            : (selection) => setState(() => _network = selection.first),
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
      const SizedBox(height: 24),
      Text('Chaves de Vida', style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(
        'Mesma quantidade e mesma ordem de sempre. Acentos, maiúsculas '
        'e espaços extras são ignorados.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
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
            icon: const Icon(Icons.add),
            label: const Text('Resposta'),
            onPressed: _busy
                ? null
                : () => setState(() => _answers.add(TextEditingController())),
          ),
          TextButton.icon(
            icon: const Icon(Icons.remove),
            label: const Text('Resposta'),
            onPressed: _busy || _answers.length <= 1
                ? null
                : () => setState(() => _answers.removeLast().dispose()),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            _error!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
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
    return [
      Card(
        child: ListTile(
          leading: const Icon(Icons.verified_user),
          title: Text('Carteira ${wallet.fingerprint}'),
          subtitle: Text(
            '${wallet.network.label}. Confira que a impressão digital é sempre '
            'a mesma: se mudar, alguma resposta ou palavra está diferente.',
          ),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        icon: const Icon(Icons.draw),
        label: const Text('Assinar transação (abrir arquivo)'),
        onPressed: _signFromFile,
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.save_alt),
        label: const Text('Salvar arquivo da carteira somente leitura'),
        onPressed: _saveWatchOnly,
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Conferir endereço', style: theme.textTheme.titleSmall),
              Text(
                'Antes de receber um valor alto, cole aqui o endereço que a '
                'carteira online mostrou. Uma máquina online comprometida '
                'poderia mostrar o endereço de outra pessoa.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _addressToCheck,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Endereço',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Conferir',
                    icon: const Icon(Icons.search),
                    onPressed: _checkAddress,
                  ),
                ),
                onSubmitted: (_) => _checkAddress(),
              ),
              if (_addressResult != null) ...[
                const SizedBox(height: 8),
                Text(
                  _addressResult!,
                  style: TextStyle(
                    color: _addressIsMine
                        ? Colors.green.shade400
                        : theme.colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      Text(
        'Dados somente-leitura: permitem VER o saldo em outro aparelho, '
        'nunca gastar.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      for (final asset in wallet.assets) AssetCard(asset: asset),
      const SizedBox(height: 8),
      Text(
        'Argon2id: ${_argonTime!.inMilliseconds} ms (${Argon2idParams.v1}). '
        'A sessão se encerra sozinha após ${idleTimeout.inMinutes} minutos '
        'sem uso.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 24),
      FilledButton.tonal(
        onPressed: _wipe,
        child: const Text('Encerrar sessão (apagar da memória)'),
      ),
    ];
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

  Future<void> _copy(WatchOnlyField field) async {
    await Clipboard.setData(ClipboardData(text: field.value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${field.label} copiado.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = widget.asset;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${asset.name} (${asset.ticker})',
              style: theme.textTheme.titleMedium,
            ),
            Text(asset.path, style: theme.textTheme.bodySmall),
            for (final field in asset.fields) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(field.label, style: theme.textTheme.labelLarge),
                  ),
                  if (field.sensitive)
                    IconButton(
                      tooltip: _revealSensitive ? 'Ocultar' : 'Mostrar',
                      icon: Icon(
                        _revealSensitive
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _revealSensitive = !_revealSensitive),
                    ),
                  if (!field.sensitive || _revealSensitive)
                    IconButton(
                      tooltip: 'Copiar',
                      icon: const Icon(Icons.copy),
                      onPressed: () => _copy(field),
                    ),
                ],
              ),
              if (!field.sensitive || _revealSensitive)
                SelectableText(
                  field.value,
                  style: const TextStyle(fontFamily: 'monospace'),
                )
              else
                Text(
                  'Oculta: não gasta, mas revela saldo e histórico.',
                  style: theme.textTheme.bodySmall,
                ),
            ],
            const SizedBox(height: 10),
            Text(asset.howToWatch, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
