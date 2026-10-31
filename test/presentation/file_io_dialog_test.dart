import 'dart:io';

import 'package:brainw4llet/presentation/widgets/file_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Abre o diálogo da pasta do app e guarda o que ele devolver em [results].
Future<void> _open(
  WidgetTester tester,
  List<File> files,
  List<File?> results,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                results.add(
                  await showDialog<File>(
                    context: context,
                    builder: (_) => AppFolderDialog(
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
  testWidgets('lista os arquivos da pasta do app e devolve o escolhido', (
    tester,
  ) async {
    final results = <File?>[];
    await _open(tester, [
      File('/x/carteira.json'),
      File('/x/pedido.json'),
    ], results);

    expect(find.textContaining('NullPointerException'), findsOneWidget);
    expect(find.text('/sdcard/Android/data/app/files'), findsOneWidget);
    expect(find.text('carteira.json'), findsOneWidget);

    await tester.tap(find.text('pedido.json'));
    await tester.pumpAndSettle();

    expect(results.single?.path, '/x/pedido.json');
  });

  testWidgets('avisa quando a pasta está vazia e permite cancelar', (
    tester,
  ) async {
    final results = <File?>[];
    await _open(tester, const [], results);

    expect(
      find.text('Nenhum arquivo .json nesta pasta ainda.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(results.single, isNull);
  });
}
