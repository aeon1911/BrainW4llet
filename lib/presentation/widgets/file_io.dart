import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _jsonGroup = XTypeGroup(
  label: 'BrainW4llet (JSON)',
  extensions: ['json'],
);

/// Tamanho máximo de um arquivo de transferência (o código nativo usa o mesmo).
const _maxBytes = 8 * 1024 * 1024;

/// Ponte com o `MainActivity.kt`: o file_selector não tem "salvar arquivo" no
/// Android, e o "abrir" dele derruba o app se o provedor de arquivos do sistema
/// falhar. Lá, os seletores do sistema são abertos pelo código nativo.
const _androidFiles = MethodChannel('com.brainw4llet.brainw4llet/files');

/// Abre um arquivo de texto escolhido pelo usuário (null = cancelou). Se o
/// sistema não conseguir ler o arquivo, lança [FormatException] com o motivo.
///
/// No Android, se o provedor de arquivos do sistema recusar a leitura (já
/// acontece no Waydroid), oferece abrir um arquivo da pasta do próprio app, que
/// não passa por ele.
Future<String?> pickTextFile(BuildContext context) async {
  if (!Platform.isAndroid) {
    final file = await openFile(acceptedTypeGroups: const [_jsonGroup]);
    return file?.readAsString();
  }
  try {
    return await _androidFiles.invokeMethod<String>('openText');
  } on PlatformException catch (e) {
    final reason = e.message ?? e.code;
    if (e.code != 'read_failed') {
      throw FormatException('Não foi possível ler o arquivo: $reason');
    }
    if (!context.mounted) return null;
    return _pickFromAppFolder(context, reason);
  }
}

/// Lista os `.json` da pasta do app (`Android/data/<pacote>/files`), onde o app
/// lê sem pedir nada ao provedor de arquivos do sistema.
Future<String?> _pickFromAppFolder(BuildContext context, String reason) async {
  final dir =
      await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();
  final files = [
    for (final entry in dir.listSync())
      if (entry is File && entry.path.toLowerCase().endsWith('.json')) entry,
  ]..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  if (!context.mounted) return null;
  final chosen = await showDialog<File>(
    context: context,
    builder: (_) =>
        AppFolderDialog(dir: dir.path, reason: reason, files: files),
  );
  if (chosen == null) return null;
  if (await chosen.length() > _maxBytes) {
    throw const FormatException(
      'Arquivo grande demais para ser do BrainW4llet.',
    );
  }
  return chosen.readAsString();
}

/// Diálogo que lista os arquivos da pasta do app (público só para o teste).
class AppFolderDialog extends StatelessWidget {
  const AppFolderDialog({
    super.key,
    required this.dir,
    required this.reason,
    required this.files,
  });

  final String dir;
  final String reason;
  final List<File> files;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Abrir da pasta do app'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'O Android não deixou ler o arquivo escolhido ($reason). '
              'Copie o arquivo para a pasta abaixo e abra-o daqui:',
            ),
            const SizedBox(height: 8),
            SelectableText(
              dir,
              style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (files.isEmpty)
              const Text('Nenhum arquivo .json nesta pasta ainda.')
            else
              for (final file in files)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(file.path.split('/').last),
                  onTap: () => Navigator.of(context).pop(file),
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
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
