import 'package:flutter/material.dart';

/// Cores que o Material não cobre: superfícies em camadas, texto
/// secundário, estados (sucesso/alerta) e o gradiente da marca.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.raised,
    required this.high,
    required this.outline,
    required this.muted,
    required this.faint,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.accent,
    required this.accent2,
  });

  final Color background;
  final Color surface;

  /// Superfície dentro de um cartão (campos, endereço, linhas).
  final Color raised;
  final Color high;
  final Color outline;
  final Color muted;
  final Color faint;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  /// Acento do modo atual (menta = online, gelo = assinador frio).
  final Color accent;

  /// Segunda cor do gradiente da marca.
  final Color accent2;

  LinearGradient get brandGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accent2],
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>()!;

  @override
  AppPalette copyWith({Color? accent, Color? accent2}) => AppPalette(
    background: background,
    surface: surface,
    raised: raised,
    high: high,
    outline: outline,
    muted: muted,
    faint: faint,
    success: success,
    warning: warning,
    danger: danger,
    info: info,
    accent: accent ?? this.accent,
    accent2: accent2 ?? this.accent2,
  );

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      raised: l(raised, other.raised),
      high: l(high, other.high),
      outline: l(outline, other.outline),
      muted: l(muted, other.muted),
      faint: l(faint, other.faint),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      info: l(info, other.info),
      accent: l(accent, other.accent),
      accent2: l(accent2, other.accent2),
    );
  }
}

/// Modo do app: cada um tem seu acento, para nunca confundir o assinador
/// frio com a carteira online.
enum AppMode { online, cold }

abstract final class AppTheme {
  static const String font = 'Inter';
  static const String monoFont = 'JetBrainsMono';

  static const double radius = 20;
  static const double radiusSmall = 12;

  static const _dark = AppPalette(
    background: Color(0xFF07090F),
    surface: Color(0xFF0E121B),
    raised: Color(0xFF151A26),
    high: Color(0xFF1D2433),
    outline: Color(0xFF232B3C),
    muted: Color(0xFF9AA3B5),
    faint: Color(0xFF677085),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    info: Color(0xFF60A5FA),
    accent: Color(0xFF5CE1B4),
    accent2: Color(0xFF8B7CFF),
  );

  static const _light = AppPalette(
    background: Color(0xFFF4F6FA),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFF1F3F8),
    high: Color(0xFFE6EAF1),
    outline: Color(0xFFDDE2EB),
    muted: Color(0xFF586177),
    faint: Color(0xFF8A93A6),
    success: Color(0xFF15A35C),
    warning: Color(0xFFC27C0E),
    danger: Color(0xFFDC3B3B),
    info: Color(0xFF2563EB),
    accent: Color(0xFF0E9F6E),
    accent2: Color(0xFF6C5CE7),
  );

  static AppPalette palette(Brightness brightness, AppMode mode) {
    final base = brightness == Brightness.dark ? _dark : _light;
    return switch ((mode, brightness)) {
      (AppMode.online, _) => base,
      (AppMode.cold, Brightness.dark) => base.copyWith(
        accent: const Color(0xFF8AB8FF),
        accent2: const Color(0xFFB59CFF),
      ),
      (AppMode.cold, Brightness.light) => base.copyWith(
        accent: const Color(0xFF2F6FE0),
        accent2: const Color(0xFF7A5CE0),
      ),
    };
  }

  static ThemeData dark({AppMode mode = AppMode.online}) =>
      build(Brightness.dark, mode);

  static ThemeData light({AppMode mode = AppMode.online}) =>
      build(Brightness.light, mode);

  static ThemeData build(Brightness brightness, AppMode mode) {
    final p = palette(brightness, mode);
    final dark = brightness == Brightness.dark;
    final onAccent = dark ? const Color(0xFF04140E) : Colors.white;
    final text = dark ? const Color(0xFFEEF1F7) : const Color(0xFF0B1020);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.accent,
      onPrimary: mode == AppMode.cold && dark
          ? const Color(0xFF06142B)
          : onAccent,
      primaryContainer: p.accent.withValues(alpha: 0.16),
      onPrimaryContainer: p.accent,
      secondary: p.accent2,
      onSecondary: Colors.white,
      tertiary: p.warning,
      onTertiary: Colors.black,
      tertiaryContainer: p.warning.withValues(alpha: 0.16),
      onTertiaryContainer: p.warning,
      error: p.danger,
      onError: Colors.white,
      errorContainer: p.danger.withValues(alpha: 0.14),
      onErrorContainer: dark
          ? const Color(0xFFFFC9C9)
          : const Color(0xFF7A1414),
      surface: p.surface,
      onSurface: text,
      onSurfaceVariant: p.muted,
      surfaceContainerLowest: p.background,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.raised,
      surfaceContainerHighest: p.high,
      outline: p.outline,
      outlineVariant: p.outline,
      inverseSurface: text,
      onInverseSurface: p.surface,
      shadow: Colors.black,
      scrim: Colors.black,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: font,
      scaffoldBackgroundColor: p.background,
      extensions: [p],
    );
    final t = base.textTheme;
    final textTheme = t
        .copyWith(
          displaySmall: t.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -1.2,
          ),
          headlineMedium: t.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
          headlineSmall: t.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          titleLarge: t.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          bodySmall: t.bodySmall?.copyWith(color: p.muted, height: 1.45),
          bodyMedium: t.bodyMedium?.copyWith(height: 1.45),
          bodyLarge: t.bodyLarge?.copyWith(height: 1.5),
        )
        .apply(bodyColor: text, displayColor: text);

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 16);
    const buttonText = TextStyle(
      fontFamily: font,
      fontSize: 15,
      fontWeight: FontWeight.w600,
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 20),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: p.outline),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.outline, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: buttonShape,
          padding: buttonPadding,
          textStyle: buttonText,
          minimumSize: const Size(0, 52),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: buttonShape,
          padding: buttonPadding,
          textStyle: buttonText,
          minimumSize: const Size(0, 52),
          foregroundColor: text,
          side: BorderSide(color: p.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: buttonShape,
          textStyle: buttonText.copyWith(fontSize: 14),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: p.muted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.raised,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: TextStyle(color: p.muted),
        floatingLabelStyle: TextStyle(color: p.accent),
        hintStyle: TextStyle(color: p.faint),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.outline),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.outline.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.accent, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.danger),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: p.surface,
          selectedBackgroundColor: p.accent.withValues(alpha: 0.16),
          selectedForegroundColor: p.accent,
          foregroundColor: p.muted,
          side: BorderSide(color: p.outline),
          textStyle: buttonText.copyWith(fontSize: 14),
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: p.high,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: p.outline),
        ),
        labelColor: text,
        unselectedLabelColor: p.muted,
        labelStyle: buttonText.copyWith(fontSize: 14),
        unselectedLabelStyle: buttonText.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        overlayColor: WidgetStatePropertyAll(p.accent.withValues(alpha: 0.06)),
        splashBorderRadius: BorderRadius.circular(999),
        tabAlignment: TabAlignment.start,
        labelPadding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        iconColor: p.muted,
        collapsedIconColor: p.faint,
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStatePropertyAll(p.outline),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.high,
        linearMinHeight: 6,
        borderRadius: BorderRadius.circular(999),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.high,
        contentTextStyle: TextStyle(fontFamily: font, color: text),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.outline),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.high,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.outline),
        ),
        textStyle: TextStyle(fontFamily: font, color: text, fontSize: 12),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Texto monoespaçado com algarismos tabulares (endereços e valores).
  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
  }) => TextStyle(
    fontFamily: monoFont,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Aplica o acento de um modo à subárvore (ex.: azul-gelo no assinador).
class ModeTheme extends StatelessWidget {
  const ModeTheme({super.key, required this.mode, required this.child});

  final AppMode mode;
  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
    data: AppTheme.build(Theme.of(context).brightness, mode),
    child: child,
  );
}
