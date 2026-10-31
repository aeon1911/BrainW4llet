import 'dart:io';

import 'package:brainw4llet/presentation/widgets/file_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Abre o diálogo de leitura que falhou e guarda o que ele devolver em
/// [results].
Future<void> _open(
  WidgetTester tester,
  List<File> files,
  List<Object?> results,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                results.add(
                  await showDialog<Object>(
                    context: context,
                    builder: (_) => ReadFailedDialog(
                      dir: '/sdcard/Android/data/app/files',
                      reason: 'NullPointerException',
                      files: files,
                    ),
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
  testWidgets('mostra o motivo e devolve o arquivo da pasta do app escolhido', (
    tester,
  ) async {
    final results = <Object?>[];
    await _open(tester, [
      File('/x/carteira.json'),
      File('/x/pedido.json'),
    ], results);

    expect(find.textContaining('NullPointerException'), findsOneWidget);
    expect(find.text('/sdcard/Android/data/app/files'), findsOneWidget);
    expect(find.text('carteira.json'), findsOneWidget);

    await tester.tap(find.text('pedido.json'));
    await tester.pumpAndSettle();

    expect(results.single, isA<File>());
    expect((results.single! as File).path, '/x/pedido.json');
  });

  testWidgets('sem arquivos na pasta do app, não fala da pasta', (
    tester,
  ) async {
    final results = <Object?>[];
    await _open(tester, const [], results);

    expect(find.textContaining('Modo compatível:'), findsOneWidget);
    expect(find.textContaining('pasta do app'), findsNothing);
    expect(find.text('/sdcard/Android/data/app/files'), findsNothing);
  });

  testWidgets('o botão Modo compatível devolve true', (tester) async {
    final results = <Object?>[];
    await _open(tester, const [], results);

    await tester.tap(find.text('Modo compatível'));
    await tester.pumpAndSettle();

    expect(results.single, true);
  });

  testWidgets('Cancelar não devolve nada', (tester) async {
    final results = <Object?>[];
    await _open(tester, const [], results);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(results.single, isNull);
  });
}
