import 'dart:convert';

import 'package:file_selector/file_selector.dart';

const _jsonGroup = XTypeGroup(
  label: 'BrainW4llet (JSON)',
  extensions: ['json'],
);

/// Abre um arquivo de texto escolhido pelo usuário (null = cancelou).
Future<String?> pickTextFile() async {
  final file = await openFile(acceptedTypeGroups: const [_jsonGroup]);
  return file?.readAsString();
}

/// Salva [content] onde o usuário escolher. Devolve o caminho, ou null se
/// ele cancelar.
Future<String?> saveTextFile(String suggestedName, String content) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [_jsonGroup],
  );
  if (location == null) return null;
  await XFile.fromData(
    utf8.encode(content),
    mimeType: 'application/json',
    name: suggestedName,
  ).saveTo(location.path);
  return location.path;
}
