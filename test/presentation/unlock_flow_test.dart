import 'package:brainw4llet/core/security/security.dart';
import 'package:brainw4llet/presentation/unlock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _deriveWith(
  WidgetTester tester,
  String mnemonic,
  List<String> answers,
) async {
  // Tela alta o bastante para o formulário inteiro caber sem rolar.
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), mnemonic);
  for (final (i, answer) in answers.indexed) {
    await tester.enterText(fields.at(i + 1), answer);
  }
  final button = find.text('Derivar');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);

  // O Argon2id roda num isolate de verdade: precisa de tempo real.
  await tester.runAsync(() async {
    for (var i = 0; i < 600; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      if (find.text('Derivar').evaluate().isNotEmpty &&
          !find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
        break;
      }
    }
  });
  await tester.pump();
}

String _screenTexts() => find
    .byType(Text)
    .evaluate()
    .map((e) => (e.widget as Text).data)
    .whereType<String>()
    .join(' | ');

void main() {
  testWidgets('seed gerada + respostas livres abrem a carteira', (
    tester,
  ) async {
    final words = Bip39Seed.generateMnemonic().join(' ');
    await tester.pumpWidget(const MaterialApp(home: UnlockScreen()));
    await _deriveWith(tester, words, ['Zeca', 'Rua das Flores', 'Marcos']);

    printOnFailure('TELA: ${_screenTexts()}');
    expect(find.textContaining('bc1q'), findsOneWidget);
    expect(find.text('Bitcoin (BTC)'), findsOneWidget);
    // A lista é preguiçosa: rola até o fim para construir o resto.
    await tester.scrollUntilVisible(
      find.textContaining('Argon2id:'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Monero (XMR)'), findsOneWidget);
    expect(
      find.text('Oculta: não gasta, mas revela saldo e histórico.'),
      findsOneWidget,
    );
  });

  testWidgets('seed com palavra errada mostra a posição do erro', (
    tester,
  ) async {
    final words = Bip39Seed.generateMnemonic()..[6] = 'abacaxi';
    await tester.pumpWidget(const MaterialApp(home: UnlockScreen()));
    await _deriveWith(tester, words.join(' '), ['a', 'b', 'c']);

    printOnFailure('TELA: ${_screenTexts()}');
    expect(find.textContaining('nº 7'), findsOneWidget);
    expect(find.textContaining('bc1q'), findsNothing);
  });
}
