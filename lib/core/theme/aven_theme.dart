import 'package:flutter/material.dart';

/// Aven Browser — 4-color TV palette.
abstract final class AvenColors {
  static const background = Color(0xFF080A0B);
  static const panel = Color(0xFF080A0B);
  static const text = Color(0xFFF3F5F7);
  static const focus = Color(0xFF0B1838);

  static const accent = panel;
  static const accentBlue = panel;
  static const hover = focus;
  static const surface = panel;
  static const row = panel;
  static const ink = background;
  static const mist = text;
  static const teal = text;
  static const textMuted = Color(0x99F3F5F7);
  static const error = focus;
  static const danger = focus;
  static const scrim = Color(0x99080A0B);
  static const barrier = Color(0xB3080A0B);

  static ThemeData theme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      colorScheme: const ColorScheme.dark(
        primary: focus,
        secondary: panel,
        surface: panel,
        onPrimary: text,
        onSecondary: text,
        onSurface: text,
        error: focus,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: panel,
        titleTextStyle: TextStyle(
          color: text,
          fontFamily: 'Cal Sans',
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          color: textMuted,
          fontSize: 17,
          height: 1.4,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: text,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          minimumSize: const Size(120, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: text,
          backgroundColor: focus,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          minimumSize: const Size(120, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      dividerColor: Color(0x22F3F5F7),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: text),
        bodyMedium: TextStyle(color: text),
        bodySmall: TextStyle(color: textMuted),
        titleLarge: TextStyle(color: text),
        titleMedium: TextStyle(color: text),
        titleSmall: TextStyle(color: textMuted),
      ),
      iconTheme: const IconThemeData(color: text),
      focusColor: focus,
      hoverColor: focus.withValues(alpha: 0.2),
      splashColor: focus.withValues(alpha: 0.28),
      highlightColor: focus.withValues(alpha: 0.16),
      listTileTheme: const ListTileThemeData(
        iconColor: text,
        textColor: text,
        selectedColor: text,
        selectedTileColor: focus,
      ),
      fontFamily: 'sans-serif',
    );
  }
}

/// Shared TV focus zoom used by buttons, tiles, fields.
abstract final class AvenFocusMotion {
  static const scale = 1.08;
  static const duration = Duration(milliseconds: 160);
  static const curve = Curves.easeOutCubic;
}

class AvenFocusZoom extends StatelessWidget {
  const AvenFocusZoom({
    super.key,
    required this.focused,
    required this.child,
    this.scale = AvenFocusMotion.scale,
  });

  final bool focused;
  final Widget child;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: focused ? scale : 1,
      duration: AvenFocusMotion.duration,
      curve: AvenFocusMotion.curve,
      alignment: Alignment.center,
      child: child,
    );
  }
}
