import 'package:flutter/widgets.dart';

/// Encerra a sessão sensível quando o app sai do primeiro plano.
///
/// - `inactive`: só cobre a tela (evita que o snapshot do seletor de apps
///   capture seed ou endereços), sem apagar nada, porque o iOS também entra
///   nesse estado ao abrir a Central de Controle ou o Face ID.
/// - `hidden`, `paused`, `detached`: cobre a tela e chama todos os
///   [register]ados para descartarem seus segredos.
final class SessionGuard with WidgetsBindingObserver {
  SessionGuard._();

  static final SessionGuard instance = SessionGuard._();

  final Set<VoidCallback> _wipers = {};

  /// `true` enquanto a tela deve ficar coberta.
  final ValueNotifier<bool> obscured = ValueNotifier(false);

  bool _attached = false;

  void attach() {
    if (_attached) return;
    WidgetsBinding.instance.addObserver(this);
    _attached = true;
  }

  void register(VoidCallback wipe) => _wipers.add(wipe);

  void unregister(VoidCallback wipe) => _wipers.remove(wipe);

  /// Descarta todos os segredos registrados.
  void endSession() {
    for (final wipe in List.of(_wipers)) {
      wipe();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        obscured.value = false;
      case AppLifecycleState.inactive:
        obscured.value = true;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        obscured.value = true;
        endSession();
    }
  }
}
