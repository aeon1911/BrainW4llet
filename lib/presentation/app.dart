import 'package:flutter/material.dart';

import '../core/security/security.dart';
import 'home_screen.dart';
import 'theme/app_theme.dart';

class BrainW4lletApp extends StatefulWidget {
  const BrainW4lletApp({super.key});

  @override
  State<BrainW4lletApp> createState() => _BrainW4lletAppState();
}

class _BrainW4lletAppState extends State<BrainW4lletApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Cada tela com segredos se registra no SessionGuard e se apaga sozinha;
    // a carteira online (sem chaves) continua aberta.
    SessionGuard.instance.attach();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BrainW4llet',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      builder: (context, child) => _PrivacyCover(child: child!),
      home: const HomeScreen(),
    );
  }
}

/// Cobre a tela inteira enquanto o app não está em primeiro plano, para o
/// snapshot do seletor de apps não capturar nada.
class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SessionGuard.instance.obscured,
      builder: (context, obscured, _) => Stack(
        children: [
          child,
          if (obscured)
            const Positioned.fill(
              key: Key('privacy-cover'),
              child: ColoredBox(
                color: Color(0xFF07090F),
                child: Center(
                  child: Icon(
                    Icons.lock_rounded,
                    size: 56,
                    color: Color(0xFF3A4458),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
