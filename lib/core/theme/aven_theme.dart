import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Phone appearance. `system` follows the device, `light` is white, `dark` stays black.
final avenThemeChoice = ValueNotifier<String>('system');

ThemeMode avenThemeMode(String choice) {
  return switch (choice) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

/// Aven Browser — black / gray / light TV palette (no accent blue).
abstract final class AvenColors {
  static const background = Color(0xFF080A0B);
  static const panel = Color(0xFF080A0B);
  static const text = Color(0xFFF3F5F7);
  /// Slightly lifted surface for fills — same family as [background], not blue.
  static const elevated = Color(0xFF141618);

  static const accent = panel;
  static const accentBlue = panel;
  static const focus = elevated;
  static const hover = elevated;
  static const surface = panel;
  static const row = panel;
  static const ink = background;
  static const mist = text;
  static const teal = text;
  static const textMuted = Color(0x99F3F5F7);
  static const error = text;
  static const danger = text;
  static const scrim = Color(0x99080A0B);
  static const barrier = Color(0xB3080A0B);

  static ThemeData theme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      colorScheme: const ColorScheme.dark(
        primary: text,
        secondary: panel,
        surface: panel,
        onPrimary: background,
        onSecondary: text,
        onSurface: text,
        error: text,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: text,
        circularTrackColor: Color(0x33F3F5F7),
        linearTrackColor: Color(0x33F3F5F7),
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
          backgroundColor: elevated,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          minimumSize: const Size(120, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      dividerColor: const Color(0x22F3F5F7),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: text),
        bodyMedium: TextStyle(color: text),
        bodySmall: TextStyle(color: textMuted),
        titleLarge: TextStyle(color: text),
        titleMedium: TextStyle(color: text),
        titleSmall: TextStyle(color: textMuted),
      ),
      iconTheme: const IconThemeData(color: text),
      focusColor: text.withValues(alpha: 0.18),
      hoverColor: text.withValues(alpha: 0.10),
      splashColor: text.withValues(alpha: 0.14),
      highlightColor: text.withValues(alpha: 0.08),
      listTileTheme: const ListTileThemeData(
        iconColor: text,
        textColor: text,
        selectedColor: text,
        selectedTileColor: elevated,
      ),
      fontFamily: 'sans-serif',
    );
  }

  static const lightBackground = Color(0xFFFFFFFF);
  static const lightElevated = Color(0xFFF2F3F5);
  static const lightText = Color(0xFF1C1C1E);
  static const lightTextMuted = Color(0x991C1C1E);

  static ThemeData lightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,
      canvasColor: lightBackground,
      colorScheme: const ColorScheme.light(
        primary: lightText,
        secondary: lightElevated,
        surface: lightBackground,
        onPrimary: lightBackground,
        onSecondary: lightText,
        onSurface: lightText,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: lightText,
        linearTrackColor: Color(0x221C1C1E),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: lightBackground,
        titleTextStyle: TextStyle(
          color: lightText,
          fontFamily: 'Cal Sans',
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          color: lightTextMuted,
          fontSize: 17,
          height: 1.4,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: lightText,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: lightBackground,
          backgroundColor: lightText,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      dividerColor: const Color(0x221C1C1E),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: lightText),
        bodyMedium: TextStyle(color: lightText),
        bodySmall: TextStyle(color: lightTextMuted),
        titleLarge: TextStyle(color: lightText),
        titleMedium: TextStyle(color: lightText),
        titleSmall: TextStyle(color: lightTextMuted),
      ),
      iconTheme: const IconThemeData(color: lightText),
      listTileTheme: const ListTileThemeData(
        iconColor: lightText,
        textColor: lightText,
      ),
      fontFamily: 'sans-serif',
    );
  }
}

/// Colors that follow the active phone theme. TV stays on [AvenColors].
abstract final class AvenTone {
  static bool dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color background(BuildContext context) =>
      dark(context) ? AvenColors.background : AvenColors.lightBackground;

  static Color elevated(BuildContext context) =>
      dark(context) ? AvenColors.elevated : AvenColors.lightElevated;

  static Color text(BuildContext context) =>
      dark(context) ? AvenColors.text : AvenColors.lightText;

  static Color textMuted(BuildContext context) =>
      dark(context) ? AvenColors.textMuted : AvenColors.lightTextMuted;

  static SystemUiOverlayStyle overlay(BuildContext context) {
    return dark(context) ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;
  }
}

/// Shared TV focus motion — outline aligned to the control shape.
abstract final class AvenFocusMotion {
  static const scale = 1.03;
  static const duration = Duration(milliseconds: 160);
  static const curve = Curves.easeOutCubic;
}

/// Focus ring painted **inset** so parent clips never shave the corners.
class AvenFocusZoom extends StatelessWidget {
  const AvenFocusZoom({
    super.key,
    required this.focused,
    required this.child,
    this.scale = AvenFocusMotion.scale,
    this.borderRadius = 12,
    this.showHalo = true,
  });

  final bool focused;
  final Widget child;
  final double scale;
  final double borderRadius;
  final bool showHalo;

  static const _inset = 2.0;
  static const _stroke = 2.0;

  @override
  Widget build(BuildContext context) {
    final body = !showHalo
        ? child
        : Stack(
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(borderRadius),
                child: child,
              ),
              Positioned(
                left: _inset,
                top: _inset,
                right: _inset,
                bottom: _inset,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: AvenFocusMotion.duration,
                    curve: AvenFocusMotion.curve,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        (borderRadius - _inset)
                            .clamp(0, borderRadius)
                            .toDouble(),
                      ),
                      border: Border.all(
                        color: focused
                            ? AvenColors.text.withValues(alpha: 0.82)
                            : Colors.transparent,
                        width: _stroke,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );

    return AnimatedScale(
      scale: focused ? scale : 1,
      duration: AvenFocusMotion.duration,
      curve: AvenFocusMotion.curve,
      alignment: Alignment.center,
      child: body,
    );
  }
}
