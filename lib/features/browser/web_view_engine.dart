import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/theme/aven_theme.dart';
import '../../platform/web_input.dart';
import 'page_engine.dart';

/// Page engine for both builds: Android System WebView.
class WebViewPageEngine implements PageEngine {
  WebViewPageEngine({
    required void Function(String url) onPageStarted,
    required void Function(String url) onPageFinished,
    required void Function(int progress) onProgress,
    required NavigationDecision Function(NavigationRequest request) onNavigationRequest,
    required void Function(WebResourceError error) onError,
    required void Function(HttpResponseError error) onHttpError,
    this.onPermission,
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

  /// Decides a page request for "camera", "microphone" or "location" on [host].
  final Future<bool> Function(String host, List<String> kinds)? onPermission;

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
    final decide = onPermission;
    if (decide == null) return;
    await platform.setOnPlatformPermissionRequest((request) async {
      final kinds = <String>[
        if (request.types.contains(WebViewPermissionResourceType.camera)) 'camera',
        if (request.types.contains(WebViewPermissionResourceType.microphone)) 'microphone',
      ];
      // DRM (protected media) needs no prompt; video sites rely on it.
      if (kinds.isEmpty) {
        await request.grant();
        return;
      }
      final host = Uri.tryParse(await controller.currentUrl() ?? '')?.host ?? '';
      if (await decide(host, kinds)) {
        await request.grant();
      } else {
        await request.deny();
      }
    });
    await platform.setGeolocationPermissionsPromptCallbacks(
      onShowPrompt: (request) async {
        final host = Uri.tryParse(request.origin)?.host ?? request.origin;
        final allow = await decide(host, const ['location']);
        return GeolocationPermissionsResponse(allow: allow, retain: false);
      },
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
  Future<Map<String, int>> findInPage(String query, {bool forward = true}) =>
      WebInput.pageFind(query, forward: forward);

  @override
  Future<void> clearFind() => WebInput.pageClearFind();

  @override
  Future<List<Map<String, String>>> listDownloads() async => const [];

  @override
  Widget buildView(Set<Factory<OneSequenceGestureRecognizer>> gestures) {
    return WebViewWidget(controller: controller, gestureRecognizers: gestures);
  }
}
