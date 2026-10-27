import 'package:flutter/material.dart';

import '../core/security/security.dart';
import 'theme/app_theme.dart';
import 'widgets/page_frame.dart';
import 'widgets/ui.dart';

/// Mostra uma seed nova uma única vez. Nada é guardado: sair da tela (ou do
/// app) descarta as palavras.
class NewSeedScreen extends StatefulWidget {
  const NewSeedScreen({super.key});

  @override
  State<NewSeedScreen> createState() => _NewSeedScreenState();
}

class _NewSeedScreenState extends State<NewSeedScreen> {
  List<String> _words = Bip39Seed.generateMnemonic();

  @override
  void initState() {
    super.initState();
    SessionGuard.instance.register(_wipe);
  }

  @override
  void dispose() {
    SessionGuard.instance.unregister(_wipe);
    _words = const [];
    super.dispose();
  }

  // `String` não pode ser zerada; soltar as referências é o que está ao
  // alcance do Dart. A tela também se fecha.
  void _wipe() {
    _words = const [];
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) => ModeTheme(
    mode: AppMode.cold,
    child: Builder(builder: _build),
  );

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nova seed')),
      body: PageFrame(
        maxWidth: 720,
        children: [
          const Notice(
            kind: NoticeKind.warning,
            title: 'Só aparece uma vez',
            text:
                'Anote as 24 palavras, em ordem, em papel ou metal. Nunca '
                'fotografe nem digite em outro aparelho. Sem esta seed E as '
                'suas Chaves de Vida, os fundos não podem ser recuperados.',
          ),
          const SizedBox(height: 4),
          AppCard(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 560
                    ? 4
                    : constraints.maxWidth >= 340
                    ? 3
                    : 2;
                final itemWidth =
                    (constraints.maxWidth - (columns - 1) * 8) / columns;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _words.length; i++)
                      Container(
                        width: itemWidth,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: p.raised,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: p.outline),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 26,
                              child: Text(
                                '${i + 1}.',
                                style: AppTheme.mono(
                                  fontSize: 12,
                                  color: p.faint,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _words[i],
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: AppTheme.mono(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Já anotei — apagar da tela'),
          ),
        ],
      ),
    );
  }
}
