import 'package:flutter/services.dart';

/// Sends remote-control clicks into the Android WebView.
///
/// The cursor itself is drawn by Flutter. A tap has to become a real
/// [MotionEvent] on the WebView, otherwise the page never sees it.
class WebInput {
  static const _channel = MethodChannel('com.avenbrowser/input');

  Future<void> tap(double x, double y, {bool screen = false}) {
    return _channel.invokeMethod<void>('tap', {'x': x, 'y': y, 'screen': screen});
  }

  Future<void> lockFocus() {
    return _channel.invokeMethod<void>('lockFocus');
  }

  /// Lets the page take keyboard focus after a click without pulling focus
  /// away from the address bar.
  Future<void> prepareForInput() {
    return _channel.invokeMethod<void>('prepareForInput');
  }

  Future<void> focusForTyping() {
    return _channel.invokeMethod<void>('focusForTyping');
  }

  Future<String?> webViewVersion() {
    return _channel.invokeMethod<String>('webViewVersion');
  }

  /// Forces the WebView texture to present a frame.
  ///
  /// After a navigation the surface can stay gray until the next Flutter
  /// composite, which is why moving the cursor makes the page appear.
  Future<void> refreshSurface() {
    return _channel.invokeMethod<void>('refreshSurface');
  }

  /// Pause WebView rendering/timers while the external player is open.
  Future<void> pauseWebView() {
    return _channel.invokeMethod<void>('pauseWebView');
  }

  Future<void> resumeWebView() {
    return _channel.invokeMethod<void>('resumeWebView');
  }

  /// While the start page or floating menu covers the page, touches there
  /// must not move keyboard focus into the WebView.
  Future<void> setChromeOpen(bool open) {
    return _channel.invokeMethod<void>('setChromeOpen', {'open': open});
  }

  Future<void> showKeyboard() {
    return _channel.invokeMethod<void>('showKeyboard');
  }

  /// Keeps keyboard focus inside the page while a text field there is active.
  Future<void> setPageTyping(bool typing) {
    return _channel.invokeMethod<void>('setPageTyping', {'typing': typing});
  }

  /// Attaches a listener for calls that start on the Android side.
  void setHandler(Future<dynamic> Function(MethodCall call)? handler) {
    _channel.setMethodCallHandler(handler);
  }

  /// Watches video file requests, including ones made inside a player frame.
  Future<void> watchMedia() {
    return _channel.invokeMethod<void>('watchMedia');
  }

  Future<void> setAdBlock(String mode, {bool connectDns = false}) {
    return _channel.invokeMethod<void>('setAdBlock', {
      'mode': mode,
      'connectDns': connectDns,
    });
  }

  /// TV speed mode: block trackers, webfonts, and chat widgets.
  Future<void> setSpeedMode(bool enabled) {
    return _channel.invokeMethod<void>('setSpeedMode', {'enabled': enabled});
  }

  Future<void> setLoadsImages(bool enabled) {
    return _channel.invokeMethod<void>('setLoadsImages', {'enabled': enabled});
  }
}

int? webViewMajor(String? version) {
  if (version == null || version.isEmpty) return null;
  final match = RegExp(r'(\d+)').firstMatch(version);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
