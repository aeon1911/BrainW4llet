import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Texto monoespaçado selecionável, numa caixa com botão de copiar.
class CopyableText extends StatelessWidget {
  const CopyableText(this.text, {super.key, this.label});

  final String text;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      decoration: BoxDecoration(
        color: p.raised,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: p.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: AppTheme.mono(
                fontSize: 13.5,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copiar',
            icon: const Icon(Icons.content_copy_rounded, size: 20),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${label ?? 'Texto'} copiado.')),
              );
            },
          ),
        ],
      ),
    );
  }
}
