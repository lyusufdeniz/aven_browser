import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/aven_strings.dart';
import '../../core/theme/aven_theme.dart';
import '../../platform/web_input.dart';

/// Phone as a remote for Aven on the TV: keys, a touchpad for the TV cursor
/// and typing straight into the TV's search box or page field.
class TvRemotePage extends StatefulWidget {
  const TvRemotePage({super.key, required this.name, required this.host, required this.port});

  final String name;
  final String host;
  final int port;

  @override
  State<TvRemotePage> createState() => _TvRemotePageState();
}

class _TvRemotePageState extends State<TvRemotePage> {
  final _text = TextEditingController();
  Offset _pendingMove = Offset.zero;
  double _pendingScroll = 0;
  Timer? _flush;
  bool _lost = false;
  int _fingers = 0;
  Offset? _lastFocal;

  // Phone finger pixels feel slow on a 1080p TV; scale them up.
  static const _moveGain = 1.8;
  static const _scrollGain = 2.4;

  @override
  void dispose() {
    _flush?.cancel();
    _text.dispose();
    unawaited(WebInput.closeTvRemote());
    super.dispose();
  }

  Future<void> _send(Map<String, Object?> payload) async {
    final ok = await WebInput.sendTvRemote(widget.host, widget.port, payload);
    if (!mounted || ok == !_lost) return;
    setState(() => _lost = !ok);
  }

  void _key(String key) {
    HapticFeedback.selectionClick();
    unawaited(_send({'cmd': 'key', 'key': key}));
  }

  // Moves are batched so a drag sends ~25 small steps a second, not hundreds.
  void _queueFlush() {
    _flush ??= Timer(const Duration(milliseconds: 40), () {
      _flush = null;
      final move = _pendingMove;
      final scroll = _pendingScroll;
      _pendingMove = Offset.zero;
      _pendingScroll = 0;
      if (move != Offset.zero) {
        unawaited(_send({'cmd': 'move', 'dx': move.dx, 'dy': move.dy}));
      }
      if (scroll != 0) unawaited(_send({'cmd': 'scroll', 'dy': scroll}));
    });
  }

  void _sendText({bool submit = true}) {
    final text = _text.text;
    if (text.isEmpty && !submit) return;
    unawaited(_send({'cmd': 'text', 'text': text, 'submit': submit}));
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final ink = AvenTone.text(context);
    return Scaffold(
      backgroundColor: AvenTone.background(context),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Icon(Icons.tv, size: 20, color: ink),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
            ),
            if (_lost)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AvenColors.live.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(avenText('aven_remote_lost')),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      decoration: InputDecoration(
                        hintText: avenText('aven_remote_type'),
                        filled: true,
                        fillColor: AvenTone.elevated(context),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: ink,
                      foregroundColor: AvenTone.background(context),
                    ),
                    onPressed: _sendText,
                    tooltip: avenText('aven_remote_send'),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    unawaited(_send({'cmd': 'click'}));
                  },
                  onScaleStart: (details) {
                    _fingers = details.pointerCount;
                    _lastFocal = details.localFocalPoint;
                  },
                  onScaleUpdate: (details) {
                    final last = _lastFocal;
                    _lastFocal = details.localFocalPoint;
                    _fingers = details.pointerCount;
                    if (last == null) return;
                    final delta = details.localFocalPoint - last;
                    if (_fingers >= 2) {
                      _pendingScroll += -delta.dy * _scrollGain;
                    } else {
                      _pendingMove += delta * _moveGain;
                    }
                    _queueFlush();
                  },
                  onScaleEnd: (_) {
                    _lastFocal = null;
                    _fingers = 0;
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AvenTone.elevated(context),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.touch_app_outlined, size: 32, color: AvenTone.textMuted(context)),
                            const SizedBox(height: 10),
                            Text(
                              avenText('aven_remote_touchpad'),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AvenTone.textMuted(context)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _DPad(onKey: _key),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundKey(icon: Icons.arrow_back, label: avenText('aven_back'), onTap: () => _key('back')),
                  _RoundKey(
                    icon: Icons.play_arrow,
                    label: '${avenText('aven_play')} / ${avenText('aven_pause')}',
                    onTap: () => _key('play'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DPad extends StatelessWidget {
  const _DPad({required this.onKey});

  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    final ring = AvenTone.elevated(context);
    Widget arrow(IconData icon, String key, Alignment at) {
      return Align(
        alignment: at,
        child: IconButton(
          iconSize: 34,
          padding: const EdgeInsets.all(12),
          onPressed: () => onKey(key),
          icon: Icon(icon),
        ),
      );
    }

    return Center(
      child: SizedBox(
        width: 200,
        height: 200,
        child: DecoratedBox(
          decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
          child: Stack(
            children: [
              arrow(Icons.keyboard_arrow_up, 'up', Alignment.topCenter),
              arrow(Icons.keyboard_arrow_down, 'down', Alignment.bottomCenter),
              arrow(Icons.keyboard_arrow_left, 'left', Alignment.centerLeft),
              arrow(Icons.keyboard_arrow_right, 'right', Alignment.centerRight),
              Center(
                child: Material(
                  color: AvenTone.text(context),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => onKey('ok'),
                    child: SizedBox(
                      width: 76,
                      height: 76,
                      child: Center(
                        child: Text(
                          'OK',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AvenTone.background(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundKey extends StatelessWidget {
  const _RoundKey({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: AvenTone.elevated(context),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 60, height: 60, child: Icon(icon, size: 26)),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 12, color: AvenTone.textMuted(context))),
      ],
    );
  }
}
