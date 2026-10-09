import 'package:flutter/services.dart';

/// Which APK is running. Set from the Android product flavor before [runApp].
abstract final class AvenFlavor {
  static bool isMobile = false;

  static Future<void> load() async {
    try {
      final flavor = await const MethodChannel('dev.furina.avenbrowser/input')
          .invokeMethod<String>('flavor');
      isMobile = flavor == 'mobile';
    } catch (_) {
      isMobile = false;
    }
  }
}
