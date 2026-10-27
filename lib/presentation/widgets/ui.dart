import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../theme/app_theme.dart';
import '../theme/coins.dart';

/// Cartão base: superfície com borda sutil, opcionalmente clicável ou com
/// um brilho de cor (ex.: a cor da moeda) no canto.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.glow,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? glow;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final radius = BorderRadius.circular(AppTheme.radius);
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: radius,
          border: Border.all(color: p.outline),
          gradient: glow == null
              ? null
              : RadialGradient(
                  center: const Alignment(-1, -1),
                  radius: 1.4,
                  colors: [
                    Color.alphaBlend(glow!.withValues(alpha: 0.16), p.surface),
                    Color.alphaBlend(glow!.withValues(alpha: 0.05), p.surface),
                    p.surface,
                  ],
                  stops: const [0, 0.5, 1],
                ),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Título de seção em caixa alta discreta, com ação opcional à direita.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                color: p.faint,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

enum NoticeKind { info, warning, danger, success }

/// Aviso em linha (no fluxo, não em pop-up), com ícone e cor do tipo.
class Notice extends StatelessWidget {
  const Notice({
    super.key,
    required this.kind,
    this.title,
    this.text,
    this.children = const [],
  });

  final NoticeKind kind;
  final String? title;
  final String? text;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final (color, icon) = switch (kind) {
      NoticeKind.info => (p.info, Icons.info_outline_rounded),
      NoticeKind.warning => (p.warning, Icons.warning_amber_rounded),
      NoticeKind.danger => (p.danger, Icons.gpp_maybe_outlined),
      NoticeKind.success => (p.success, Icons.verified_outlined),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      // Material próprio: um ListTile dentro do aviso (ex.: caixa de
      // confirmação) precisa dele para desenhar o toque.
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        title!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: color,
                        ),
                      ),
                    ),
                  if (text != null)
                    Text(
                      text!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.88,
                        ),
                      ),
                    ),
                  ...children,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta curta de status.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon});

  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final c = color ?? p.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              color: c,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Círculo com o ícone e a cor da moeda.
class CoinAvatar extends StatelessWidget {
  const CoinAvatar(this.coin, {super.key, this.size = 40});

  final CoinStyle coin;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(coin.color, Colors.white, 0.18)!,
            Color.lerp(coin.color, Colors.black, 0.18)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: coin.color.withValues(alpha: 0.35),
            blurRadius: size / 3,
            offset: Offset(0, size / 12),
          ),
        ],
      ),
      child: Icon(coin.icon, color: Colors.white, size: size * 0.56),
    );
  }
}

/// Ícone dentro de um quadrado arredondado tingido.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.color, this.size = 44});

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppPalette.of(context).accent;
    // Align: dentro de um ListView o quadrado não estica até a borda.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: 1,
      heightFactor: 1,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(size * 0.32),
          border: Border.all(color: c.withValues(alpha: 0.25)),
        ),
        child: Icon(icon, color: c, size: size * 0.5),
      ),
    );
  }
}

/// Marca do app: chave estilizada num quadrado com o gradiente do modo.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: p.brandGradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: p.accent.withValues(alpha: 0.35),
            blurRadius: size / 2,
            offset: Offset(0, size / 10),
          ),
        ],
      ),
      child: Icon(
        Icons.key_rounded,
        color: const Color(0xFF07090F),
        size: size * 0.55,
      ),
    );
  }
}

/// Valor grande: número em destaque e o ticker menor e esmaecido.
class AmountText extends StatelessWidget {
  const AmountText(this.formatted, {super.key, this.fontSize = 34, this.color});

  /// Ex.: "0.04821930 BTC".
  final String formatted;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final space = formatted.lastIndexOf(' ');
    final number = space < 0 ? formatted : formatted.substring(0, space);
    final unit = space < 0 ? '' : formatted.substring(space + 1);
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return SelectableText.rich(
      TextSpan(
        children: [
          TextSpan(
            text: number,
            style: AppTheme.mono(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: c,
              height: 1.1,
            ).copyWith(letterSpacing: -fontSize * 0.03),
          ),
          if (unit.isNotEmpty)
            TextSpan(
              text: '  $unit',
              style: TextStyle(
                fontSize: fontSize * 0.45,
                fontWeight: FontWeight.w600,
                color: p.muted,
              ),
            ),
        ],
      ),
    );
  }
}

/// Uma linha rótulo → valor (revisões, detalhes).
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(
    this.label,
    this.value, {
    super.key,
    this.mono = true,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool mono;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: TextStyle(color: p.muted, fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: SelectableText(
              value,
              textAlign: TextAlign.end,
              style: mono
                  ? AppTheme.mono(
                      fontSize: 14,
                      color: onSurface,
                      fontWeight: emphasis ? FontWeight.w600 : null,
                    )
                  : TextStyle(
                      fontSize: 14,
                      color: onSurface,
                      fontWeight: emphasis ? FontWeight.w600 : null,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// QR code desenhado localmente (nenhum serviço externo).
class QrView extends StatelessWidget {
  const QrView(this.data, {super.key, this.size = 200});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = QrImage(
      QrCode(
        payload: QrPayload.fromString(data),
        errorCorrectLevel: QrErrorCorrectLevel.medium,
      ),
    );
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.06),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Semantics(
        label: 'QR code do endereço',
        child: CustomPaint(painter: _QrPainter(image)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);

  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    final cell = size.width / n;
    final paint = Paint()
      ..color = const Color(0xFF07090F)
      ..isAntiAlias = false;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (image.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}
