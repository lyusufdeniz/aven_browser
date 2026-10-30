import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/aven_flavor.dart';

/// Phone appearance. `system` follows the device, `light` is white, `dark` stays black.
final avenThemeChoice = ValueNotifier<String>('system');

ThemeMode avenThemeMode(String choice) {
  return switch (choice) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

/// Aven Browser TV palette — slate black surfaces, light focus pills and
/// white for progress, toggles and primary actions (no blue accent).
abstract final class AvenColors {
  static const background = Color(0xFF131418);
  static const panel = Color(0xFF1A1B20);
  /// Darker strip for side rails and nav columns.
  static const rail = Color(0xFF0E0F12);
  static const text = Color(0xFFF1F3F7);
  /// Lifted surface for cells, keys and secondary buttons.
  static const elevated = Color(0xFF2A2D35);

  /// Focused row / key / tab: light pill with dark content.
  static const focusFill = Color(0xFFE6E9F0);
  static const onFocus = Color(0xFF15171C);

  /// Progress bars, toggles, cursors and primary buttons.
  static const accent = text;
  static const live = Color(0xFFE5484D);

  static const focus = elevated;
  static const hover = elevated;
  static const surface = panel;
  static const row = panel;
  static const ink = background;
  static const mist = text;
  static const teal = text;
  static const textMuted = Color(0x99F1F3F7);
  static const error = live;
  static const danger = live;
  static const scrim = Color(0x99131418);
  static const barrier = Color(0xB30B0C0F);

  /// Phone dark mode keeps the original pure black look.
  static const phoneBackground = Color(0xFF080A0B);
  static const phoneElevated = Color(0xFF141618);
  static const phoneText = Color(0xFFF3F5F7);
  static const phoneTextMuted = Color(0x99F3F5F7);

  static ThemeData theme() {
    final tv = !AvenFlavor.isMobile;
    final bg = tv ? background : phoneBackground;
    final fg = tv ? text : phoneText;
    final lifted = tv ? elevated : phoneElevated;
    final highlight = tv ? accent : phoneText;
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      colorScheme: ColorScheme.dark(
        primary: highlight,
        secondary: tv ? panel : phoneBackground,
        surface: tv ? panel : phoneBackground,
        onPrimary: tv ? onFocus : phoneBackground,
        onSecondary: fg,
        onSurface: fg,
        error: tv ? live : phoneText,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: highlight,
        circularTrackColor: fg.withValues(alpha: 0.2),
        linearTrackColor: fg.withValues(alpha: 0.2),
      ),
      switchTheme: tv
          ? SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? onFocus
                    : textMuted,
              ),
              trackColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? accent
                    : elevated,
              ),
              trackOutlineColor:
                  const WidgetStatePropertyAll(Colors.transparent),
            )
          : null,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: highlight,
        selectionColor: highlight.withValues(alpha: 0.35),
        selectionHandleColor: highlight,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tv ? panel : phoneBackground,
        titleTextStyle: TextStyle(
          color: fg,
          fontFamily: 'Cal Sans',
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          color: fg.withValues(alpha: 0.6),
          fontSize: 17,
          height: 1.4,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: fg,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          minimumSize: const Size(120, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: tv ? onFocus : fg,
          backgroundColor: tv ? accent : lifted,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          minimumSize: const Size(120, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      dividerColor: fg.withValues(alpha: 0.13),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: fg),
        bodyMedium: TextStyle(color: fg),
        bodySmall: TextStyle(color: fg.withValues(alpha: 0.6)),
        titleLarge: TextStyle(color: fg),
        titleMedium: TextStyle(color: fg),
        titleSmall: TextStyle(color: fg.withValues(alpha: 0.6)),
      ),
      iconTheme: IconThemeData(color: fg),
      focusColor: fg.withValues(alpha: 0.18),
      hoverColor: fg.withValues(alpha: 0.10),
      splashColor: fg.withValues(alpha: 0.14),
      highlightColor: fg.withValues(alpha: 0.08),
      listTileTheme: ListTileThemeData(
        iconColor: fg,
        textColor: fg,
        selectedColor: fg,
        selectedTileColor: lifted,
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

  static Color background(BuildContext context) => !dark(context)
      ? AvenColors.lightBackground
      : AvenFlavor.isMobile
          ? AvenColors.phoneBackground
          : AvenColors.background;

  static Color elevated(BuildContext context) => !dark(context)
      ? AvenColors.lightElevated
      : AvenFlavor.isMobile
          ? AvenColors.phoneElevated
          : AvenColors.elevated;

  static Color text(BuildContext context) => !dark(context)
      ? AvenColors.lightText
      : AvenFlavor.isMobile
          ? AvenColors.phoneText
          : AvenColors.text;

  static Color textMuted(BuildContext context) => !dark(context)
      ? AvenColors.lightTextMuted
      : AvenFlavor.isMobile
          ? AvenColors.phoneTextMuted
          : AvenColors.textMuted;

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
