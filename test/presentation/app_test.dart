import 'package:brainw4llet/core/security/security.dart';
import 'package:brainw4llet/presentation/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => SessionGuard.debugIsPhoneOverride = null);

  testWidgets('tela inicial e cobertura ao sair do primeiro plano (celular)', (
    tester,
  ) async {
    SessionGuard.debugIsPhoneOverride = true;
    await tester.pumpWidget(const BrainW4lletApp());
    expect(find.text('Carteira online'), findsOneWidget);
    expect(find.byKey(const Key('privacy-cover')), findsNothing);

    SessionGuard.instance.didChangeAppLifecycleState(
      AppLifecycleState.inactive,
    );
    await tester.pump();
    expect(find.byKey(const Key('privacy-cover')), findsOneWidget);

    SessionGuard.instance.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(const Key('privacy-cover')), findsNothing);
  });

  testWidgets('ir para segundo plano apaga a seed gerada e volta ao início', (
    tester,
  ) async {
    await tester.pumpWidget(const BrainW4lletApp());
    await tester.scrollUntilVisible(find.text('Gerar nova seed'), 200);
    await tester.tap(find.text('Gerar nova seed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('24.'), findsOneWidget);

    SessionGuard.instance.didChangeAppLifecycleState(AppLifecycleState.paused);
    SessionGuard.instance.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('24.'), findsNothing);
    expect(find.text('Carteira online'), findsOneWidget);
  });
}
