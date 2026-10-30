import 'dart:convert';
import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

const _jsonGroup = XTypeGroup(
  label: 'BrainW4llet (JSON)',
  extensions: ['json'],
);

/// Ponte com o `MainActivity.kt`: o file_selector não tem "salvar arquivo" no
/// Android, então lá o diálogo "Salvar como" do sistema é aberto pelo código
/// nativo.
const _androidFiles = MethodChannel('com.brainw4llet.brainw4llet/files');

/// Abre um arquivo de texto escolhido pelo usuário (null = cancelou).
Future<String?> pickTextFile() async {
  final file = await openFile(acceptedTypeGroups: const [_jsonGroup]);
  return file?.readAsString();
}

/// Salva [content] onde o usuário escolher. Devolve o caminho (no Android, o
/// endereço `content://` do documento), ou null se ele cancelar.
Future<String?> saveTextFile(String suggestedName, String content) async {
  if (Platform.isAndroid) {
    return _androidFiles.invokeMethod<String>('saveText', {
      'name': suggestedName,
      'content': content,
    });
  }
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
