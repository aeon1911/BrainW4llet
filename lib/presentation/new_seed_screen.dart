import 'package:flutter/material.dart';

import '../core/security/security.dart';
import 'widgets/page_frame.dart';

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
    _wipe();
    super.dispose();
  }

  // `String` não pode ser zerada; soltar as referências é o que está ao
  // alcance do Dart.
  void _wipe() => _words = const [];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nova seed')),
      body: PageFrame(
        children: [
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Anote as 24 palavras, em ordem, em papel ou metal. Nunca '
                'fotografe nem digite em outro aparelho. Sem esta seed E as '
                'suas Chaves de Vida, os fundos não podem ser recuperados.',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 420 ? 3 : 2;
              final itemWidth =
                  (constraints.maxWidth - (columns - 1) * 8) / columns;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _words.length; i++)
                    SizedBox(
                      width: itemWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.dividerColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Text(
                            '${(i + 1).toString().padLeft(2)}. ${_words[i]}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Já anotei — apagar da tela'),
          ),
        ],
      ),
    );
  }
}
