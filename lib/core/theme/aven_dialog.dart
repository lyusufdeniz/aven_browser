import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'aven_theme.dart';

/// Confirm / prompt dialog using the same 4-color TV surface as chrome.
class AvenConfirmDialog extends StatefulWidget {
  const AvenConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
    this.icon = Icons.help_outline,
    this.autofocusConfirm = false,
    this.destructive = false,
    this.onCancel,
    this.onConfirm,
  });

  /// Confirm turns red when focused (quit, delete).
  final bool destructive;

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final IconData icon;
  final bool autofocusConfirm;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  @override
  State<AvenConfirmDialog> createState() => _AvenConfirmDialogState();
}

class _AvenConfirmDialogState extends State<AvenConfirmDialog> {
  late final FocusNode _cancelFocus = FocusNode(debugLabel: 'dialog-cancel');
  late final FocusNode _confirmFocus = FocusNode(debugLabel: 'dialog-confirm');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (widget.autofocusConfirm ? _confirmFocus : _cancelFocus).requestFocus();
    });
  }

  @override
  void dispose() {
    _cancelFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _cancel() {
    (widget.onCancel ?? () => Navigator.of(context).pop(false))();
  }

  void _confirm() {
    (widget.onConfirm ?? () => Navigator.of(context).pop(true))();
  }

  KeyEventResult _onCancelKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      _confirmFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    if (_isActivate(key)) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onConfirmKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      _cancelFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.handled;
    }
    if (_isActivate(key)) {
      _confirm();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _isActivate(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space;
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Center(
        child: AvenDialogEntrance(
          child: AvenDialogPanel(
            maxWidth: 620,
            padding: const EdgeInsets.fromLTRB(44, 40, 44, 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: AvenDialogBadge(icon: widget.icon, alert: widget.destructive)),
                const SizedBox(height: 22),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Cal Sans',
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    height: 1.15,
                    color: AvenColors.text,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.message,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.45,
                    color: AvenColors.textMuted,
                  ),
                ),
                const SizedBox(height: 34),
                Row(
                  children: [
                    Expanded(
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(0),
                        child: AvenDialogButton(
                          label: widget.cancelLabel,
                          focusNode: _cancelFocus,
                          onKeyEvent: _onCancelKey,
                          onPressed: _cancel,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(1),
                        child: AvenDialogButton(
                          label: widget.confirmLabel,
                          focusNode: _confirmFocus,
                          primary: true,
                          destructive: widget.destructive,
                          onKeyEvent: _onConfirmKey,
                          onPressed: _confirm,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades and grows a TV dialog in, so it does not just pop onto the page.
class AvenDialogEntrance extends StatelessWidget {
  const AvenDialogEntrance({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
      ),
    );
  }
}

/// TV dialog surface: rounded slate card with a soft top light and a deep shadow.
class AvenDialogPanel extends StatelessWidget {
  const AvenDialogPanel({
    super.key,
    required this.child,
    this.maxWidth = 620,
    this.padding = const EdgeInsets.all(32),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(AvenColors.panel, AvenColors.text, 0.06)!,
              AvenColors.panel,
            ],
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AvenColors.text.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 64,
              offset: const Offset(0, 24),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Round icon at the top of a TV dialog.
class AvenDialogBadge extends StatelessWidget {
  const AvenDialogBadge({super.key, required this.icon, this.alert = false});

  final IconData icon;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final tone = alert ? AvenColors.live : AvenColors.text;
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tone.withValues(alpha: 0.10),
        border: Border.all(color: tone.withValues(alpha: 0.22), width: 1.5),
        boxShadow: [BoxShadow(color: tone.withValues(alpha: 0.12), blurRadius: 32)],
      ),
      child: Icon(icon, size: 40, color: tone),
    );
  }
}

/// Dialog action matching menu bar focus treatment (panel + focus fill).
class AvenDialogButton extends StatelessWidget {
  const AvenDialogButton({
    super.key,
    required this.label,
    required this.focusNode,
    required this.onKeyEvent,
    required this.onPressed,
    this.primary = false,
    this.destructive = false,
  });

  final bool destructive;
  final String label;
  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode node, KeyEvent event) onKeyEvent;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: onKeyEvent,
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          final Color fill = focused
              ? (destructive ? AvenColors.live : AvenColors.focusFill)
              : primary
                  ? AvenColors.text.withValues(alpha: 0.16)
                  : AvenColors.elevated;
          final Color ink = focused
              ? (destructive ? Colors.white : AvenColors.onFocus)
              : AvenColors.text;
          return AvenFocusZoom(
            focused: focused,
            scale: 1.04,
            borderRadius: 30,
            showHalo: false,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(30),
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                child: AnimatedContainer(
                  duration: AvenFocusMotion.duration,
                  curve: AvenFocusMotion.curve,
                  constraints: const BoxConstraints(minHeight: 60),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: !focused && primary
                          ? AvenColors.text.withValues(alpha: 0.22)
                          : Colors.transparent,
                    ),
                    boxShadow: focused
                        ? [BoxShadow(color: fill.withValues(alpha: 0.35), blurRadius: 22)]
                        : const [],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
