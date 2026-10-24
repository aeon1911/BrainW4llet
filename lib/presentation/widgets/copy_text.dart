import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Texto monoespaçado selecionável com botão de copiar.
class CopyableText extends StatelessWidget {
  const CopyableText(this.text, {super.key, this.label});

  final String text;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SelectableText(
            text,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
        IconButton(
          tooltip: 'Copiar',
          icon: const Icon(Icons.copy),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${label ?? 'Texto'} copiado.')),
            );
          },
        ),
      ],
    );
  }
}
