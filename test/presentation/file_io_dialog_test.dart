import 'package:brainw4llet/presentation/widgets/file_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Abre o diálogo de leitura que falhou e guarda o que ele devolver em
/// [results].
Future<void> _open(WidgetTester tester, List<bool?> results) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                results.add(
                  await showDialog<bool>(
                    context: context,
                    builder: (_) =>
                        const ReadFailedDialog(reason: 'NullPointerException'),
                  ),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mostra o motivo da falha e não fala de pasta nenhuma', (
    tester,
  ) async {
    await _open(tester, <bool?>[]);

    expect(find.text('Não deu para ler o arquivo'), findsOneWidget);
    expect(find.textContaining('NullPointerException'), findsOneWidget);
    expect(find.textContaining('pasta'), findsNothing);
  });

  testWidgets('Escolher de novo devolve true', (tester) async {
    final results = <bool?>[];
    await _open(tester, results);

    await tester.tap(find.text('Escolher de novo'));
    await tester.pumpAndSettle();

    expect(results.single, true);
  });

  testWidgets('Cancelar não devolve nada', (tester) async {
    final results = <bool?>[];
    await _open(tester, results);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(results.single, isNull);
  });
}
