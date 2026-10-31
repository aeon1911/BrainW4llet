import 'dart:convert';
import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _jsonGroup = XTypeGroup(
  label: 'BrainW4llet (JSON)',
  extensions: ['json'],
);

/// Ponte com o `MainActivity.kt`: o file_selector não tem "salvar arquivo" no
/// Android, e o "abrir" dele derruba o app se o provedor de arquivos do sistema
/// falhar. Lá, os seletores do sistema são abertos pelo código nativo.
const _androidFiles = MethodChannel('com.brainw4llet.brainw4llet/files');

/// Vira `true` depois que o modo compatível leu um arquivo: nesse aparelho a
/// leitura normal não funciona, então as próximas já começam por ele. (No
/// Waydroid, o código nativo já começa pelo modo compatível.)
bool _androidCompatRead = false;

/// Abre um arquivo de texto escolhido pelo usuário (null = cancelou). Se o
/// sistema não conseguir ler o arquivo, lança [FormatException] com o motivo.
///
/// No Android, se o provedor de arquivos do sistema recusar a leitura, um
/// diálogo oferece escolher o arquivo de novo, no modo compatível (lido de
/// outro jeito).
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
    final retry = await showDialog<bool>(
      context: context,
      builder: (_) => ReadFailedDialog(reason: reason),
    );
    if (retry != true) return null;
    try {
      final text = await _androidFiles.invokeMethod<String>('openText', {
        'compat': true,
      });
      if (text != null) _androidCompatRead = true;
      return text;
    } on PlatformException catch (retryError) {
      throw FormatException(
        'Não foi possível ler o arquivo: '
        '${retryError.message ?? retryError.code}',
      );
    }
  }
}

/// Diálogo mostrado quando o Android recusa a leitura. Devolve `true` para
/// escolher o arquivo de novo, no modo compatível. Público só para o teste.
class ReadFailedDialog extends StatelessWidget {
  const ReadFailedDialog({super.key, required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Não deu para ler o arquivo'),
      content: Text(
        'O Android recusou a leitura ($reason). Escolha o arquivo de novo: o '
        'app vai tentar lê-lo de outro jeito.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Escolher de novo'),
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
