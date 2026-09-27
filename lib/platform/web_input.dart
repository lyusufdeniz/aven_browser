import 'package:flutter/services.dart';

/// Sends remote-control clicks into the Android WebView.
///
/// The cursor itself is drawn by Flutter. A tap has to become a real
/// [MotionEvent] on the WebView, otherwise the page never sees it.
class WebInput {
  static const _channel = MethodChannel('com.avenbrowser/input');

  static Future<dynamic> Function(MethodCall)? _appHandler;
  static final List<void Function(bool)> _pipListeners = [];
  static bool _bound = false;

  static void _ensureBound() {
    if (_bound) return;
    _bound = true;
    _channel.setMethodCallHandler(_dispatch);
  }

  static Future<dynamic> _dispatch(MethodCall call) async {
    if (call.method == 'pipChanged') {
      final inPip = call.arguments == true;
      for (final listener in List<void Function(bool)>.of(_pipListeners)) {
        listener(inPip);
      }
      return null;
    }
    return _appHandler?.call(call);
  }

  Future<void> tap(double x, double y, {bool screen = false}) {
    return _channel.invokeMethod<void>('tap', {'x': x, 'y': y, 'screen': screen});
  }

  /// Injects a mouse-wheel style scroll into the WebView (SPA-friendly).
  Future<void> scroll(double x, double y, double dx, double dy) {
    return _channel.invokeMethod<void>('scroll', {
      'x': x,
      'y': y,
      'dx': dx,
      'dy': dy,
    });
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
    _appHandler = handler;
    _ensureBound();
  }

  /// Picture-in-picture mode changes from Android.
  void addPipListener(void Function(bool inPip) listener) {
    _pipListeners.add(listener);
    _ensureBound();
  }

  void removePipListener(void Function(bool inPip) listener) {
    _pipListeners.remove(listener);
  }

  Future<bool> isPipSupported() async {
    final raw = await _channel.invokeMethod<bool>('isPipSupported');
    return raw == true;
  }

  Future<bool> enterPip({int width = 16, int height = 9}) async {
    final raw = await _channel.invokeMethod<bool>('enterPip', {
      'width': width,
      'height': height,
    });
    return raw == true;
  }

  Future<void> setPipAspect({int width = 16, int height = 9}) {
    return _channel.invokeMethod<void>('setPipAspect', {
      'width': width,
      'height': height,
    });
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

  /// Opens the system speech recognizer and returns the first match.
  Future<String?> recognizeSpeech({String locale = 'tr-TR'}) {
    return _channel.invokeMethod<String>('recognizeSpeech', {'locale': locale});
  }

  /// Opens an intent:// or custom-scheme URL via Android Intent.
  /// Returns a map: `{opened: bool, fallback?: String}`.
  Future<Map<String, dynamic>> openExternalUrl(String url) async {
    final raw = await _channel.invokeMethod<dynamic>('openExternalUrl', {
      'url': url,
    });
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {'opened': raw == true};
  }
}

int? webViewMajor(String? version) {
  if (version == null || version.isEmpty) return null;
  final match = RegExp(r'(\d+)').firstMatch(version);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
