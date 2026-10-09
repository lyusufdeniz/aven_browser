import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Shared page-script surface for the TV WebView and the phone Gecko engine.
abstract class JsRunner {
  Future<void> runJavaScript(String javaScript);
  Future<Object> runJavaScriptReturningResult(String javaScript);
}

abstract class PageEngine implements JsRunner {
  Future<void> configure({
    required bool lite,
    required void Function(Widget widget, VoidCallback onHide) onShowFullscreen,
    required VoidCallback onHideFullscreen,
  });

  Future<void> addJavaScriptChannel(
    String name, {
    required void Function(JavaScriptMessage message) onMessageReceived,
  });

  Future<void> setUserAgent(String? userAgent);
  Future<String?> getUserAgent();
  Future<void> loadRequest(Uri uri);
  Future<void> reload();
  Future<void> goBack();
  Future<void> goForward();
  Future<bool> canGoBack();
  Future<bool> canGoForward();
  Future<String?> getTitle();
  Future<void> setTextZoom(int zoom);
  Future<void> setMediaPlaybackRequiresUserGesture(bool require);

  Widget buildView(Set<Factory<OneSequenceGestureRecognizer>> gestures);

  Future<void> setPrivate(bool enabled) async {}

  Future<void> findInPage(String query) async {}

  Future<void> clearFind() async {}

  Future<List<Map<String, String>>> listDownloads() async => const [];
}
