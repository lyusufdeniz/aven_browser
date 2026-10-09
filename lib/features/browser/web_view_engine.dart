import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/theme/aven_theme.dart';
import 'page_engine.dart';

/// TV engine: Android System WebView.
class WebViewPageEngine implements PageEngine {
  WebViewPageEngine({
    required void Function(String url) onPageStarted,
    required void Function(String url) onPageFinished,
    required void Function(int progress) onProgress,
    required NavigationDecision Function(NavigationRequest request) onNavigationRequest,
    required void Function(WebResourceError error) onError,
    required void Function(HttpResponseError error) onHttpError,
  }) {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AvenColors.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: onPageStarted,
          onPageFinished: onPageFinished,
          onProgress: onProgress,
          onNavigationRequest: onNavigationRequest,
          onWebResourceError: onError,
          onHttpError: onHttpError,
        ),
      );
  }

  late final WebViewController controller;

  @override
  Future<void> configure({
    required bool lite,
    required void Function(Widget widget, VoidCallback onHide) onShowFullscreen,
    required VoidCallback onHideFullscreen,
  }) async {
    final platform = controller.platform;
    if (platform is! AndroidWebViewController) return;
    await platform.setMediaPlaybackRequiresUserGesture(lite);
    await platform.setUseWideViewPort(true);
    await platform.setTextZoom(100);
    await platform.setCustomWidgetCallbacks(
      onShowCustomWidget: onShowFullscreen,
      onHideCustomWidget: onHideFullscreen,
    );
  }

  @override
  Future<void> addJavaScriptChannel(
    String name, {
    required void Function(JavaScriptMessage message) onMessageReceived,
  }) {
    return controller.addJavaScriptChannel(name, onMessageReceived: onMessageReceived);
  }

  @override
  Future<void> setUserAgent(String? userAgent) => controller.setUserAgent(userAgent);

  @override
  Future<String?> getUserAgent() => controller.getUserAgent();

  @override
  Future<void> loadRequest(Uri uri) => controller.loadRequest(uri);

  @override
  Future<void> reload() => controller.reload();

  @override
  Future<void> goBack() => controller.goBack();

  @override
  Future<void> goForward() => controller.goForward();

  @override
  Future<bool> canGoBack() => controller.canGoBack();

  @override
  Future<bool> canGoForward() => controller.canGoForward();

  @override
  Future<String?> getTitle() => controller.getTitle();

  @override
  Future<void> runJavaScript(String javaScript) => controller.runJavaScript(javaScript);

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) {
    return controller.runJavaScriptReturningResult(javaScript);
  }

  @override
  Future<void> setTextZoom(int zoom) async {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setTextZoom(zoom);
    }
  }

  @override
  Future<void> setMediaPlaybackRequiresUserGesture(bool require) async {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setMediaPlaybackRequiresUserGesture(require);
    }
  }

  @override
  Future<void> setPrivate(bool enabled) async {}

  @override
  Future<void> findInPage(String query) async {}

  @override
  Future<void> clearFind() async {}

  @override
  Future<List<Map<String, String>>> listDownloads() async => const [];

  @override
  Widget buildView(Set<Factory<OneSequenceGestureRecognizer>> gestures) {
    return WebViewWidget(controller: controller, gestureRecognizers: gestures);
  }
}
