import 'package:flutter/material.dart';

import 'new_seed_screen.dart';
import 'online/online_wallet_screen.dart';
import 'theme/app_theme.dart';
import 'unlock_screen.dart';
import 'widgets/ui.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(context);
    final cold = AppTheme.palette(theme.brightness, AppMode.cold);
    void open(Widget screen) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));

    final online = _ModeCard(
      key: const Key('home-online'),
      color: p.accent,
      icon: Icons.account_balance_wallet_outlined,
      title: 'Carteira online',
      subtitle:
          'Saldo, histórico, receber, montar envios e transmitir. '
          'Use no aparelho com internet.',
      tags: const ['Sem chaves', 'Somente leitura'],
      onTap: () => open(const OnlineWalletScreen()),
    );
    final signer = _ModeCard(
      key: const Key('home-cold'),
      color: cold.accent,
      icon: Icons.shield_outlined,
      title: 'Assinador frio (offline)',
      subtitle:
          'Seed + Chaves de Vida. Exporta a carteira somente leitura e '
          'assina transações. Use sem internet.',
      tags: const ['Offline', 'Argon2id'],
      onTap: () => open(const UnlockScreen()),
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 40 : 20,
                    wide ? 32 : 16,
                    wide ? 40 : 20,
                    32,
                  ),
                  children: [
                    Row(
                      children: [
                        const BrandMark(size: 40),
                        const SizedBox(width: 12),
                        Text(
                          'BrainW4llet',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Pill(
                          'Nada gravado aqui',
                          icon: Icons.memory_rounded,
                          color: p.muted,
                        ),
                      ],
                    ),
                    SizedBox(height: wide ? 56 : 36),
                    Text(
                      'Suas chaves nunca\ntocam a internet.',
                      style:
                          (wide
                                  ? theme.textTheme.displaySmall
                                  : theme.textTheme.headlineMedium)
                              ?.copyWith(height: 1.12),
                    ),
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Text(
                        'Funciona como o Electrum: as chaves só existem no '
                        'assinador frio (aparelho offline); a carteira online '
                        'vê saldos, monta envios e transmite, sem nunca ter '
                        'chave. Entre os dois, arquivos.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: p.muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    _FlowStrip(online: p.accent, cold: cold.accent),
                    const SizedBox(height: 28),
                    if (wide)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: online),
                            const SizedBox(width: 16),
                            Expanded(child: signer),
                          ],
                        ),
                      )
                    else ...[
                      online,
                      signer,
                    ],
                    AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      onTap: () => open(const NewSeedScreen()),
                      child: Row(
                        children: [
                          IconBadge(
                            Icons.auto_awesome_outlined,
                            color: p.accent2,
                            size: 40,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Gerar nova seed',
                                  style: theme.textTheme.titleMedium,
                                ),
                                Text(
                                  '24 palavras aleatórias para uma carteira '
                                  'nova.',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: p.faint),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 18,
                      runSpacing: 10,
                      children: [
                        for (final (icon, text) in const [
                          (Icons.cloud_off_rounded, 'Assinatura offline'),
                          (Icons.delete_sweep_outlined, 'Apagado ao sair'),
                          (Icons.hub_outlined, 'BTC · ETH · SOL · DASH · XMR'),
                        ])
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 16, color: p.faint),
                              const SizedBox(width: 6),
                              Text(text, style: theme.textTheme.bodySmall),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Nada é gravado neste aparelho. Ao sair do assinador, '
                      'tudo é apagado da memória.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: p.faint,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Diagrama do fluxo: assinador (offline) ⇄ arquivo ⇄ carteira online.
class _FlowStrip extends StatelessWidget {
  const _FlowStrip({required this.online, required this.cold});

  final Color online;
  final Color cold;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    Widget node(IconData icon, String label, Color color) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconBadge(icon, color: color, size: 42),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: p.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    Widget link() => Expanded(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          children: [
            Expanded(child: Divider(color: p.outline, thickness: 1.5)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.swap_horiz_rounded, size: 18, color: p.faint),
            ),
            Expanded(child: Divider(color: p.outline, thickness: 1.5)),
          ],
        ),
      ),
    );
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Row(
        children: [
          node(Icons.shield_outlined, 'Assinador', cold),
          link(),
          node(Icons.description_outlined, 'Arquivo', p.accent2),
          link(),
          node(Icons.public_rounded, 'Online', online),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> tags;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(context);
    return AppCard(
      glow: color,
      onTap: onTap,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon, color: color, size: 48),
              const Spacer(),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: color,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(color: p.muted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final t in tags) Pill(t, color: color)],
          ),
        ],
      ),
    );
  }
}
