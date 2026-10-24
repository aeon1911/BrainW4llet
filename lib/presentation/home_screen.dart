import 'package:flutter/material.dart';

import 'new_seed_screen.dart';
import 'unlock_screen.dart';
import 'widgets/page_frame.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('BrainW4llet')),
      body: PageFrame(
        children: [
          Text(
            'Cold wallet sem persistência: nada é gravado neste aparelho. '
            'A carteira é a combinação da seed de 24 palavras com as suas '
            'Chaves de Vida.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.lock_open),
            label: const Text('Abrir carteira'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const UnlockScreen()),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.casino_outlined),
            label: const Text('Gerar nova seed'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const NewSeedScreen()),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Mantenha este aparelho em modo avião. Ao sair do app, tudo é '
            'apagado da memória.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
