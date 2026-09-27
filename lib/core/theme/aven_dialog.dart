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
    this.onCancel,
    this.onConfirm,
  });

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
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 520,
            maxWidth: 680,
          ),
          child: Material(
            color: AvenColors.panel.withValues(alpha: 0.98),
            elevation: 18,
            shadowColor: Colors.black87,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AvenColors.panel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AvenColors.text.withValues(alpha: 0.14),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AvenColors.text.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AvenColors.text.withValues(alpha: 0.16),
                            ),
                          ),
                          child: Icon(widget.icon, size: 28, color: AvenColors.text),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: const TextStyle(
                                  fontFamily: 'Cal Sans',
                                  fontSize: 28,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.3,
                                  height: 1.15,
                                  color: AvenColors.text,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                widget.message,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  height: 1.45,
                                  color: AvenColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: FocusTraversalOrder(
                            order: const NumericFocusOrder(1),
                            child: AvenDialogButton(
                              label: widget.confirmLabel,
                              focusNode: _confirmFocus,
                              primary: true,
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
        ),
      ),
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
  });

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
          final Color fill;
          if (focused) {
            fill = AvenColors.focus;
          } else if (primary) {
            fill = AvenColors.text.withValues(alpha: 0.10);
          } else {
            fill = AvenColors.text.withValues(alpha: 0.05);
          }
          final border = focused
              ? AvenColors.text.withValues(alpha: 0.45)
              : AvenColors.text.withValues(alpha: primary ? 0.22 : 0.14);
          return AvenFocusZoom(
            focused: focused,
            scale: 1.04,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  constraints: const BoxConstraints(minHeight: 54),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: border, width: focused ? 2.5 : 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AvenColors.text.withValues(alpha: focused ? 1 : 0.92),
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
