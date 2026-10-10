import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/l10n/aven_strings.dart';
import 'page_engine.dart';

/// Phone engine: Mozilla GeckoView.
class GeckoPageEngine implements PageEngine {
  GeckoPageEngine({
    required this.onPageStarted,
    required this.onPageFinished,
    required this.onProgress,
    required this.onError,
    required this.onExternal,
    this.onNewTab,
    this.onSecurity,
    this.onPermissionPrompt,
    this.onContextMenu,
    this.onDownloads,
  }) {
    _channel.setMethodCallHandler(_onNative);
  }

  static const _viewType = 'aven/gecko';
  static const _channel = MethodChannel('dev.furina.avenbrowser/gecko');

  final void Function(String url) onPageStarted;
  final void Function(String url) onPageFinished;
  final void Function(int progress) onProgress;
  final void Function(WebResourceError error) onError;
  final void Function(String url) onExternal;
  final void Function(String url)? onNewTab;
  final void Function(Map<String, String> info)? onSecurity;
  final Future<bool> Function(String host, String label)? onPermissionPrompt;
  final void Function(Map<String, String> info)? onContextMenu;
  final void Function(List<Map<String, String>> items)? onDownloads;
  final Map<String, void Function(JavaScriptMessage message)> _channels = {};

  Future<dynamic> _onNative(MethodCall call) async {
    switch (call.method) {
      case 'pageStarted':
        onPageStarted(call.arguments as String? ?? '');
      case 'pageFinished':
        onPageFinished(call.arguments as String? ?? '');
      case 'progress':
        onProgress((call.arguments as num?)?.toInt() ?? 0);
      case 'external':
        final url = call.arguments as String? ?? '';
        if (url.isNotEmpty) onExternal(url);
      case 'newTab':
        final opened = call.arguments as String? ?? '';
        if (opened.isNotEmpty) onNewTab?.call(opened);
      case 'error':
        final raw = call.arguments;
        final map = raw is Map ? Map<Object?, Object?>.from(raw) : const <Object?, Object?>{};
        onError(
          WebResourceError(
            errorCode: (map['code'] as num?)?.toInt() ?? -1,
            description: map['description'] as String? ?? 'Gecko load error',
            errorType: WebResourceErrorType.unknown,
            isForMainFrame: true,
            url: map['url'] as String?,
          ),
        );
      case 'permissionPrompt':
        final raw = call.arguments;
        final map = raw is Map ? raw : const {};
        final hostRaw = '${map['host'] ?? ''}'.trim();
        final host = hostRaw.isEmpty ? avenText('aven_this_site') : hostRaw;
        final label = permissionLabel('${map['id'] ?? ''}');
        if (onPermissionPrompt == null) return false;
        return onPermissionPrompt!(host, label);
      case 'downloads':
        final raw = call.arguments;
        if (raw is List && onDownloads != null) {
          onDownloads!(
            [
              for (final item in raw)
                if (item is Map)
                  {
                    for (final entry in item.entries)
                      entry.key.toString(): '${entry.value ?? ''}',
                  },
            ],
          );
        }
      case 'contextMenu':
        final raw = call.arguments;
        if (raw is Map && onContextMenu != null) {
          onContextMenu!(
            {
              for (final entry in raw.entries)
                entry.key.toString(): '${entry.value ?? ''}',
            },
          );
        }
      case 'security':
        final raw = call.arguments;
        if (raw is Map && onSecurity != null) {
          onSecurity!(
            {
              for (final entry in raw.entries)
                entry.key.toString(): '${entry.value ?? ''}',
            },
          );
        }
      case 'js':
        final raw = call.arguments;
        if (raw is! Map) return;
        final map = Map<Object?, Object?>.from(raw);
        final name = map['channel'] as String? ?? '';
        final message = map['message'] as String? ?? '';
        _channels[name]?.call(JavaScriptMessage(message: message));
    }
  }

  @override
  Future<void> configure({
    required bool lite,
    required void Function(Widget widget, VoidCallback onHide) onShowFullscreen,
    required VoidCallback onHideFullscreen,
  }) async {
    await setMediaPlaybackRequiresUserGesture(lite);
  }

  @override
  Future<void> addJavaScriptChannel(
    String name, {
    required void Function(JavaScriptMessage message) onMessageReceived,
  }) async {
    _channels[name] = onMessageReceived;
  }

  @override
  Future<void> setUserAgent(String? userAgent) {
    return _channel.invokeMethod<void>('setUserAgent', {'agent': userAgent});
  }

  @override
  Future<String?> getUserAgent() {
    return _channel.invokeMethod<String>('getUserAgent');
  }

  @override
  Future<void> loadRequest(Uri uri) {
    return _channel.invokeMethod<void>('loadUrl', {'url': uri.toString()});
  }

  @override
  Future<void> reload() => _channel.invokeMethod<void>('reload');

  @override
  Future<void> goBack() => _channel.invokeMethod<void>('goBack');

  @override
  Future<void> goForward() => _channel.invokeMethod<void>('goForward');

  @override
  Future<bool> canGoBack() async {
    return await _channel.invokeMethod<bool>('canGoBack') ?? false;
  }

  @override
  Future<bool> canGoForward() async {
    return await _channel.invokeMethod<bool>('canGoForward') ?? false;
  }

  @override
  Future<String?> getTitle() => _channel.invokeMethod<String>('getTitle');

  @override
  Future<void> runJavaScript(String javaScript) async {
    await _channel.invokeMethod<Object?>('eval', {'code': javaScript});
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    final value = await _channel.invokeMethod<Object?>('eval', {'code': javaScript});
    return value ?? 'null';
  }

  @override
  Future<void> setTextZoom(int zoom) {
    return _channel.invokeMethod<void>('setTextZoom', {'zoom': zoom});
  }

  @override
  Future<void> setMediaPlaybackRequiresUserGesture(bool require) {
    return _channel.invokeMethod<void>('setMediaGesture', {'require': require});
  }

  @override
  Future<void> setPrivate(bool enabled) {
    return _channel.invokeMethod<void>('setPrivate', {'enabled': enabled});
  }

  @override
  Future<Map<String, int>> findInPage(String query, {bool forward = true}) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('find', {
      'query': query,
      'backwards': !forward,
    });
    return {
      'current': int.tryParse('${raw?['current']}') ?? 0,
      'total': int.tryParse('${raw?['total']}') ?? 0,
    };
  }

  Future<String> requestAutofill() async {
    final status = await _channel.invokeMethod<String>('requestAutofill');
    return status ?? 'failed';
  }

  Future<void> openAutofillSettings() {
    return _channel.invokeMethod<void>('openAutofillSettings');
  }

  Future<Uint8List?> capturePreview() async {
    final raw = await _channel.invokeMethod<Uint8List>('capturePreview');
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  @override
  Future<void> clearFind() {
    return _channel.invokeMethod<void>('clearFind');
  }

  Future<Map<String, String>> securityInfo() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getSecurity');
    if (raw == null) return const {};
    return {
      for (final entry in raw.entries) entry.key.toString(): '${entry.value ?? ''}',
    };
  }

  Future<List<Map<String, String>>> siteSettings() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('getSiteSettings');
    if (raw == null) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          {
            for (final entry in item.entries)
              entry.key.toString(): '${entry.value ?? ''}',
          },
    ];
  }

  Future<void> setSiteSetting(String id, String value) {
    return _channel.invokeMethod<void>('setSiteSetting', {'id': id, 'value': value});
  }

  Future<void> share(String text) {
    return _channel.invokeMethod<void>('share', {'text': text});
  }

  static Future<List<Map<String, String>>> fetchDownloads() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('listDownloads');
    if (raw == null) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          {
            for (final entry in item.entries)
              entry.key.toString(): '${entry.value ?? ''}',
          },
    ];
  }

  static Future<void> saveUrl(String url) {
    return _channel.invokeMethod<void>('downloadUrl', {'url': url});
  }

  static Future<void> openSaved(String id) {
    return _channel.invokeMethod<void>('openDownload', {'id': id});
  }

  static Future<void> cancelDownload(String id) {
    return _channel.invokeMethod<void>('cancelDownload', {'id': id});
  }

  @override
  Future<List<Map<String, String>>> listDownloads() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('listDownloads');
    if (raw == null) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          {
            for (final entry in item.entries)
              entry.key.toString(): '${entry.value}',
          },
    ];
  }

  @override
  Widget buildView(Set<Factory<OneSequenceGestureRecognizer>> gestures) {
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: gestures,
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (params) {
        final view = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
          creationParamsCodec: const StandardMessageCodec(),
        );
        view.addOnPlatformViewCreatedListener(params.onPlatformViewCreated);
        view.create();
        return view;
      },
    );
  }
}
