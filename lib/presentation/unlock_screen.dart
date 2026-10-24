import 'package:flutter/material.dart';
import 'package:sodium/sodium_sumo.dart';

import '../core/security/security.dart';
import '../features/wallet/address_preview.dart';
import 'widgets/page_frame.dart';
import 'widgets/secret_field.dart';

/// Seed + Chaves de Vida → Argon2id → seed BIP-39 → endereços.
///
/// Os campos são limpos assim que a derivação começa; a tela só guarda
/// endereços públicos e o tempo do Argon2id (para calibrar o custo).
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  static const _initialAnswers = 3;

  final _mnemonic = TextEditingController();
  final List<TextEditingController> _answers = [
    for (var i = 0; i < _initialAnswers; i++) TextEditingController(),
  ];

  bool _busy = false;
  String? _error;
  AddressPreview? _preview;
  Duration? _argonTime;

  @override
  void initState() {
    super.initState();
    SessionGuard.instance.register(_wipe);
  }

  @override
  void dispose() {
    SessionGuard.instance.unregister(_wipe);
    _wipe();
    _mnemonic.dispose();
    for (final c in _answers) {
      c.dispose();
    }
    super.dispose();
  }

  void _wipe() {
    _mnemonic.clear();
    for (final c in _answers) {
      c.clear();
    }
    _preview = null;
    _argonTime = null;
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
      if (!Bip39Seed.isValid(mnemonic)) {
        throw ArgumentError('Seed inválida: confira as palavras e a ordem.');
      }
      final stopwatch = Stopwatch()..start();
      lifeKey = await LifeKeysPassphrase().derive(answers);
      stopwatch.stop();
      seed = Bip39Seed.deriveSeed(mnemonic: mnemonic, lifeKey: lifeKey);
      final preview = AddressPreview.fromSeed(seed);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _argonTime = stopwatch.elapsed;
      });
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

  void _endSession() => setState(_wipe);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Abrir carteira')),
      body: PageFrame(
        children: [
          if (preview == null) ...[
            SecretField(
              controller: _mnemonic,
              label: 'Seed (24 palavras, separadas por espaço)',
              maxLines: 4,
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
                      : () => setState(
                          () => _answers.add(TextEditingController()),
                        ),
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
          ] else ...[
            _AddressTile(
              title: 'Ethereum / EVM',
              path: AddressPreview.ethereumPath,
              address: preview.ethereum,
            ),
            _AddressTile(
              title: 'Bitcoin (SegWit nativo)',
              path: AddressPreview.bitcoinPath,
              address: preview.bitcoin,
            ),
            const SizedBox(height: 8),
            Text(
              'Argon2id: ${_argonTime!.inMilliseconds} ms '
              '(${Argon2idParams.v1})',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: _endSession,
              child: const Text('Encerrar sessão'),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile({
    required this.title,
    required this.path,
    required this.address,
  });

  final String title;
  final String path;
  final String address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            Text(path, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            SelectableText(
              address,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}
