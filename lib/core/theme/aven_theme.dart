import 'package:flutter/material.dart';

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
