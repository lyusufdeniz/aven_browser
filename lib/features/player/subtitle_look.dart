import 'package:flutter/material.dart';

import '../../data/settings_store.dart';

/// Draws one subtitle line with the viewer's [SubtitleStyle].
class SubtitleLook extends StatelessWidget {
  const SubtitleLook({super.key, required this.text, required this.style});

  final String text;
  final SubtitleStyle style;

  double get _fontSize => switch (style.size) {
        'small' => 18,
        'large' => 28,
        'xlarge' => 34,
        _ => 22,
      };

  Color get _box => switch (style.background) {
        'none' => Colors.transparent,
        'solid' => Colors.black,
        _ => const Color(0xA6000000),
      };

  Color get _ink =>
      style.color == 'yellow' ? const Color(0xFFFFE14D) : Colors.white;

  @override
  Widget build(BuildContext context) {
    final bare = style.background == 'none';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _box,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: _fontSize,
            height: 1.25,
            fontWeight: FontWeight.w500,
            color: _ink,
            // Without a box, an outline keeps text readable on bright video.
            shadows: bare
                ? const [
                    Shadow(blurRadius: 3, color: Colors.black),
                    Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}
