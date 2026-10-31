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

/// Vira `true` depois que o modo compatível leu um arquivo: nesse aparelho a
/// leitura normal não funciona, então as próximas já começam por ele.
bool _androidCompatRead = false;

/// Abre um arquivo de texto escolhido pelo usuário (null = cancelou). Se o
/// sistema não conseguir ler o arquivo, lança [FormatException] com o motivo.
///
/// No Android, se o provedor de arquivos do sistema recusar a leitura (já
/// acontece no Waydroid), um diálogo oferece o modo compatível (escolher o
/// arquivo de novo, lido de outro jeito) ou abrir um arquivo da pasta do app.
Future<String?> pickTextFile(BuildContext context) async {
  if (!Platform.isAndroid) {
    final file = await openFile(acceptedTypeGroups: const [_jsonGroup]);
    return file?.readAsString();
  }
  try {
    return await _androidFiles.invokeMethod<String>('openText', {
      'compat': _androidCompatRead,
    });
  } on PlatformException catch (e) {
    final reason = e.message ?? e.code;
    if (e.code != 'read_failed') {
      throw FormatException('Não foi possível ler o arquivo: $reason');
    }
    if (!context.mounted) return null;
    return _recoverFailedRead(context, reason);
  }
}

Future<String?> _recoverFailedRead(BuildContext context, String reason) async {
  final dir =
      await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();
  final files = [
    for (final entry in dir.listSync())
      if (entry is File && entry.path.toLowerCase().endsWith('.json')) entry,
  ]..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  if (!context.mounted) return null;
  final choice = await showDialog<Object>(
    context: context,
    builder: (_) =>
        ReadFailedDialog(dir: dir.path, reason: reason, files: files),
  );
  if (choice is File) {
    if (await choice.length() > _maxBytes) {
      throw const FormatException(
        'Arquivo grande demais para ser do BrainW4llet.',
      );
    }
    return choice.readAsString();
  }
  if (choice != true) return null;
  try {
    final text = await _androidFiles.invokeMethod<String>('openText', {
      'compat': true,
    });
    if (text != null) _androidCompatRead = true;
    return text;
  } on PlatformException catch (e) {
    throw FormatException(
      'Não foi possível ler o arquivo: ${e.message ?? e.code}',
    );
  }
}

/// Diálogo mostrado quando o Android recusa a leitura. Devolve `true` para
/// tentar o modo compatível, um [File] da pasta do app, ou nada (cancelou).
/// Público só para o teste.
class ReadFailedDialog extends StatelessWidget {
  const ReadFailedDialog({
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
      title: const Text('Não deu para ler o arquivo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'O Android recusou a leitura ($reason). Isso acontece em '
              'alguns aparelhos e no Waydroid.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Modo compatível: escolha o arquivo de novo e o app tenta lê-lo '
              'de outro jeito.',
            ),
            if (files.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Ou abra um arquivo da pasta do app:'),
              const SizedBox(height: 4),
              SelectableText(
                dir,
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 12,
                ),
              ),
              for (final file in files)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(file.path.split('/').last),
                  onTap: () => Navigator.of(context).pop(file),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Modo compatível'),
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
