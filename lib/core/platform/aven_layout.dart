import 'package:flutter/widgets.dart';

/// Shared form-factor helpers for TV + phone.
abstract final class AvenLayout {
  /// Side-by-side chrome (settings / library) needs room.
  static bool isCompact(BuildContext context) {
    return MediaQuery.sizeOf(context).shortestSide < 600 ||
        MediaQuery.sizeOf(context).width < 720;
  }
}
