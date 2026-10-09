import 'package:flutter/widgets.dart';

import 'aven_flavor.dart';

/// Shared form-factor helpers for TV + phone.
abstract final class AvenLayout {
  /// Phone uses a single scrolling column. TV keeps the side-by-side panels
  /// even when the 1080p emulator reports a short logical height.
  static bool isCompact(BuildContext context) {
    if (!AvenFlavor.isMobile) return false;
    return MediaQuery.sizeOf(context).shortestSide < 600 ||
        MediaQuery.sizeOf(context).width < 720;
  }
}
