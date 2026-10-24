import 'package:flutter/material.dart';

import '../core/security/security.dart';
import 'home_screen.dart';

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
    SessionGuard.instance
      ..attach()
      ..register(_backToHome);
  }

  @override
  void dispose() {
    SessionGuard.instance.unregister(_backToHome);
    super.dispose();
  }

  // Ao sair do primeiro plano, nenhuma tela com dados sensíveis sobrevive.
  void _backToHome() =>
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BrainW4llet',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D6B),
          brightness: Brightness.dark,
        ),
      ),
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
              child: ColoredBox(
                color: Color(0xFF0B1512),
                child: Center(
                  child: Icon(Icons.lock, size: 64, color: Colors.white38),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
