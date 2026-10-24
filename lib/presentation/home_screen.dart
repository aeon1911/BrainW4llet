import 'package:flutter/material.dart';

import 'new_seed_screen.dart';
import 'online/online_wallet_screen.dart';
import 'unlock_screen.dart';
import 'widgets/page_frame.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void open(Widget screen) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    return Scaffold(
      appBar: AppBar(title: const Text('BrainW4llet')),
      body: PageFrame(
        children: [
          Text(
            'Funciona como o Electrum: as chaves só existem no assinador frio '
            '(aparelho offline); a carteira online vê saldos, monta envios e '
            'transmite, sem nunca ter chave. Entre os dois, arquivos.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          _Entry(
            icon: Icons.account_balance_wallet,
            title: 'Carteira online',
            subtitle:
                'Saldo, histórico, receber, montar envios e transmitir. '
                'Use no aparelho com internet.',
            onTap: () => open(const OnlineWalletScreen()),
          ),
          _Entry(
            icon: Icons.lock,
            title: 'Assinador frio (offline)',
            subtitle:
                'Seed + Chaves de Vida. Exporta a carteira somente '
                'leitura e assina transações. Use sem internet.',
            onTap: () => open(const UnlockScreen()),
          ),
          _Entry(
            icon: Icons.casino_outlined,
            title: 'Gerar nova seed',
            subtitle: '24 palavras aleatórias para uma carteira nova.',
            onTap: () => open(const NewSeedScreen()),
          ),
          const SizedBox(height: 24),
          Text(
            'Nada é gravado neste aparelho. Ao sair do assinador, tudo é '
            'apagado da memória.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
