import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/theme/aven_theme.dart';
import '../../core/url/url_input.dart';
import '../../data/settings_store.dart';
import '../../platform/web_input.dart';
import '../library/library_page.dart';
import '../player/video_catalog.dart';
import '../player/video_player_page.dart';
import '../settings/settings_page.dart';
import 'media_site.dart';
import 'web_scripts.dart';

part 'widgets/browser_page_widgets.dart';
part 'web_navigation.dart';
part 'cursor_input.dart';

const _pageHooks = '''
if (!window.__aven) {
  window.__aven = true;
  function avenAsk(url) {
    try { url = new URL(url, document.baseURI).href; } catch (e) { url = String(url || ''); }
    if (!url || url.indexOf('http') !== 0 || !window.AvenPopup) return;
    try { AvenPopup.postMessage(url); } catch (e) {}
  }
  window.open = function(url) {
    if (url) avenAsk(url);
    return null;
  };
  document.addEventListener('click', function(event) {
    var node = event.target;
    while (node && node.tagName !== 'A') node = node.parentElement;
    if (!node || !node.href) return;
    var target = (node.target || '').toLowerCase();
    if (target === '_blank' || target === '_new') {
      event.preventDefault();
      event.stopPropagation();
      avenAsk(node.href);
    }
  }, true);
  function avenEditable(el) {
    if (!el || el === document.body || el === document.documentElement) return false;
    var tag = (el.tagName || '').toUpperCase();
    if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return true;
    return el.isContentEditable === true;
  }
  function avenReportField() {
    if (!window.AvenField) return;
    try { AvenField.postMessage(avenEditable(document.activeElement) ? '1' : '0'); } catch (e) {}
  }
  document.addEventListener('focusin', avenReportField, true);
  document.addEventListener('focusout', function() { setTimeout(avenReportField, 40); }, true);
}
''';

const _editableCheck = '''
(function() {
  var el = document.activeElement;
  if (!el) return false;
  var tag = (el.tagName || '').toUpperCase();
  if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return true;
  return el.isContentEditable === true;
})()
''';

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

abstract class _BrowserPageBase extends State<BrowserPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _input = WebInput();
  final _store = BrowserStore();
  final _address = TextEditingController();
  final _addressFocus = FocusNode();
  final _startFocus = FocusNode();
  final _surfaceFocus = FocusNode();
  final _menuFocus = FocusNode();
  final _cursor = ValueNotifier<Offset>(Offset.zero);
  final _cursorVisible = ValueNotifier<bool>(true);
  final _cursorLook = ValueNotifier<_CursorLook>(_CursorLook.normal);
  final _progress = ValueNotifier<int>(0);
  final _pageLoading = ValueNotifier<bool>(false);
  final _surfaceKick = ValueNotifier<int>(0);
  Timer? _loadTimeout;
  Timer? _cursorHide;
  Widget? _fullscreenVideo;
  VoidCallback? _exitFullscreen;

  late final Ticker _ticker;
  late final WebViewController _controller;

  Size _webSize = Size.zero;
  bool _placed = false;
  bool _onStart = true;
  bool _menuOpen = false;
  DateTime _lastBack = DateTime.fromMillisecondsSinceEpoch(0);
  bool _openingVideo = false;
  bool _webSuspended = false;
  bool _pageTyping = false;
  bool _popupOpen = false;
  bool _addressEditing = false;
  bool _startEditing = false;
  bool _canBack = false;
  bool _canForward = false;
  bool _warnWebView = false;
  bool _lite = false;
  bool _saved = false;
  String? _pageUrl;
  String? _pageTitle;
  SearchEngine _engine = SearchEngine.google;
  List<WebLink> _bookmarks = const [];
  AdBlock _adBlock = AdBlock.off;
  AdBlock _adBlockProvider = AdBlock.adguard;
  int _zoom = 100;
  int _mediaEpoch = 0;
  String? _userAgent;
  final Set<LogicalKeyboardKey> _held = {};
  Offset _direction = Offset.zero;
  DateTime? _tickWall;
  final Map<LogicalKeyboardKey, Timer> _arrowRelease = {};
  DateTime _lastScroll = DateTime.fromMillisecondsSinceEpoch(0);

  static const cursorSpeedMin = 95.0;
  static const cursorSpeedMax = 240.0;
  DateTime? _moveStartedAt;
  _PageError? _pageError;
  Timer? _wakeTimer;

  static final Set<Factory<OneSequenceGestureRecognizer>> pageGestures =
      <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      };

  // Implemented by install wrappers / chrome helpers on _BrowserPageState.
  Future<void> _installHooks();
  Future<void> _installBannerCss();
  Future<void> _installLiteCss();
  Future<void> _installAdblockCss();
  Future<void> _installMediaSiteHints();
  Future<void> _openInput(String raw);
  void _syncChrome();

  // Implemented by _CursorInput.
  void _resetPointerState();
}

class _BrowserPageState extends _BrowserPageBase
    with _BrowserNavigation, _CursorInput {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    _input.setHandler((call) async {
      if (call.method == 'media' && call.arguments is String) {
        _onWatchedMedia(call.arguments as String);
      }
    });
    _ticker = createTicker(_onTick);
    _surfaceFocus.canRequestFocus = false;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AvenColors.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: _onPageStarted,
          onPageFinished: _onPageFinished,
          onProgress: (value) {
            _progress.value = value;
            if (value >= 100) {
              _pageLoading.value = false;
              _loadTimeout?.cancel();
              _wakeSurface();
            }
          },
          onWebResourceError: _onError,
          onHttpError: _onHttpError,
        ),
      );
    _boot();
  }

  Future<void> _boot() async {
    await _configureAndroid();
    final engine = await _store.loadEngine();
    final bookmarks = await _store.loadBookmarks();
    final block = await _store.loadAdBlock();
    final provider = await _store.loadAdBlockProvider();
    final agent = await _store.loadAgent();
    final lite = await _store.loadLiteBrowsing();
    final version = await _input.webViewVersion();
    await _input.setAdBlock(block.name);
    await _applyAgent(agent);
    await _applyLite(lite);
    if (!mounted) return;
    final major = webViewMajor(version);
    setState(() {
      _engine = engine;
      _bookmarks = bookmarks;
      _adBlock = block;
      _adBlockProvider = provider;
      _lite = lite;
      _warnWebView = major != null && major < 80;
    });
  }

  Future<void> _applyAgent(BrowserAgent agent) async {
    await _controller.setUserAgent(agent.value);
    try {
      _userAgent = await _controller.getUserAgent();
    } catch (_) {
      _userAgent = agent.value;
    }
  }

  Future<void> _applyLite(bool enabled) async {
    _lite = enabled;
    final platform = _controller.platform;
    if (platform is! AndroidWebViewController) return;
    await platform.setMediaPlaybackRequiresUserGesture(enabled);
    // Keep images on Ãƒâ€Ãƒâ€¡ÃƒÂ¶ lite mode trims motion/media instead.
    await _input.setLoadsImages(true);
  }

  Future<void> _setZoom(int zoom) async {
    final next = zoom.clamp(50, 300);
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setTextZoom(next);
    }
    if (!mounted) return;
    setState(() => _zoom = next);
  }

  Future<void> _configureAndroid() async {
    final platform = _controller.platform;
    if (platform is! AndroidWebViewController) return;
    await platform.setMediaPlaybackRequiresUserGesture(_lite);
    await platform.setUseWideViewPort(true);
    await platform.setTextZoom(100);
    await _controller.addJavaScriptChannel(
      'AvenVideo',
      onMessageReceived: _onVideoMessage,
    );
    await _controller.addJavaScriptChannel(
      'AvenPopup',
      onMessageReceived: _onPopupMessage,
    );
    await _controller.addJavaScriptChannel(
      'AvenField',
      onMessageReceived: _onFieldMessage,
    );
    try {
      _userAgent = await _controller.getUserAgent();
    } catch (_) {}
    await platform.setCustomWidgetCallbacks(
      onShowCustomWidget: (widget, onHide) {
        // Refuse in-WebView fullscreen Ãƒâ€Ãƒâ€¡ÃƒÂ¶ it stalls the TV. Hijack to Aven player.
        onHide();
        unawaited(_hijackPageVideos());
      },
      onHideCustomWidget: () {},
    );
  }

  Future<void> _hijackPageVideos() async {
    // Fullscreen is refused on TV; only offer the opt-in badge Ãƒâ€Ãƒâ€¡ÃƒÂ¶ never auto-open.
    try {
      await _controller.runJavaScript(r'''
(function(){
  try {
    if (window.__avenPrepare) {
      var videos = document.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) window.__avenPrepare(videos[i]);
    }
  } catch(e) {}
})();
''');
    } catch (_) {}
  }

  Future<void> _onWatchedMedia(String url) async {
    if (!mounted || !isAvenWebUrl(url)) return;
    // Feed the media pool / focused badge only Ãƒâ€Ãƒâ€¡ÃƒÂ¶ do not auto-open Aven player.
    try {
      await _controller.runJavaScript(
        'window.__avenOffer && window.__avenOffer(${jsonEncode(url)});',
      );
    } catch (_) {}
  }

  @override
  Future<void> _installHooks() async {
    await WebScripts.installHooks(
      _controller,
      pageHooks: _pageHooks,
      videoWatch: videoWatchScript,
    );
  }

  @override
  Future<void> _installBannerCss() async {
    await WebScripts.installBannerCss(_controller);
  }

  @override
  Future<void> _installMediaSiteHints() async {
    if (!isAvenMediaSite(_pageUrl)) return;
    await WebScripts.installMediaSiteHints(_controller);
  }

  @override
  Future<void> _installLiteCss() async {
    await WebScripts.installLiteCss(
      _controller,
      mediaSite: isAvenMediaSite(_pageUrl),
    );
  }

  @override
  Future<void> _installAdblockCss() async {
    await WebScripts.installAdblockCss(_controller);
  }

  @override
  Future<void> _openInput(String raw) async {
    final target = normalizeInput(raw, engine: _engine);
    if (target == null) {
      _showStart();
      return;
    }
    setState(() {
      _onStart = false;
      _menuOpen = false;
      _addressEditing = false;
      _startEditing = false;
      _pageError = null;
    });
    _syncChrome();
    _addressFocus.unfocus();
    _startFocus.unfocus();
    _surfaceFocus.canRequestFocus = true;
    await _resumeWebPage();
    await _controller.loadRequest(Uri.parse(target));
    _surfaceFocus.requestFocus();
  }

  void _showStart() {
    setState(() {
      _onStart = true;
      _menuOpen = false;
      _addressEditing = false;
      _startEditing = false;
      _pageError = null;
      _address.text = '';
    });
    _addressFocus.unfocus();
    _surfaceFocus.canRequestFocus = false;
    _surfaceFocus.unfocus();
    _syncChrome();
    unawaited(_suspendWebPage());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startFocus.requestFocus();
    });
  }

  Future<void> _leaveStartToPage() async {
    if (!_onStart) return;
    setState(() {
      _onStart = false;
      if (isAvenWebUrl(_pageUrl)) _address.text = _pageUrl!;
    });
    _syncChrome();
    _surfaceFocus.canRequestFocus = true;
    await _resumeWebPage();
    if (!mounted) return;
    _surfaceFocus.requestFocus();
  }

  Future<void> _toggleBookmark() async {
    final url = _pageUrl;
    if (!isAvenWebUrl(url)) return;
    final exists = _bookmarks.any((item) => item.url == url);
    final next = exists
        ? _bookmarks.where((item) => item.url != url).toList()
        : [
            WebLink(
              title: _pageTitle ?? url!,
              url: url!,
              savedAt: DateTime.now().millisecondsSinceEpoch,
            ),
            ..._bookmarks,
          ];
    final stored = await _store.saveBookmarks(next);
    if (!mounted) return;
    setState(() {
      _bookmarks = stored;
      _saved = stored.any((item) => item.url == url);
    });
  }

  Future<void> _openLibrary({int section = 0}) async {
    final picked = await showDialog<String>(
      context: context,
      barrierColor: AvenColors.barrier,
      builder: (context) {
        return Dialog(
          backgroundColor: AvenColors.accentBlue,
          insetPadding: const EdgeInsets.symmetric(horizontal: 160, vertical: 96),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 960,
                maxHeight: 600,
                minWidth: 720,
                minHeight: 480,
              ),
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width * 0.62,
                height: MediaQuery.sizeOf(context).height * 0.62,
                child: LibraryPage(store: _store, initialSection: section),
              ),
            ),
          ),
        );
      },
    );
    _bookmarks = await _store.loadBookmarks();
    if (!mounted) return;
    setState(() => _saved = _bookmarks.any((item) => item.url == _pageUrl));
    if (picked != null) {
      await _openInput(picked);
      return;
    }
    if (_onStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _onStart) _startFocus.requestFocus();
      });
    } else if (_menuOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _menuOpen) _menuFocus.requestFocus();
      });
    }
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      barrierColor: AvenColors.barrier,
      builder: (context) {
        return Dialog(
          backgroundColor: AvenColors.accentBlue,
          insetPadding: const EdgeInsets.symmetric(horizontal: 160, vertical: 96),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 960,
                maxHeight: 600,
                minWidth: 720,
                minHeight: 480,
              ),
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width * 0.62,
                height: MediaQuery.sizeOf(context).height * 0.62,
                child: SettingsPage(store: _store, input: _input),
              ),
            ),
          ),
        );
      },
    );
    final engine = await _store.loadEngine();
    final block = await _store.loadAdBlock();
    final provider = await _store.loadAdBlockProvider();
    final agent = await _store.loadAgent();
    final lite = await _store.loadLiteBrowsing();
    await _input.setAdBlock(block.name);
    await _applyAgent(agent);
    await _applyLite(lite);
    if (!mounted) return;
    setState(() {
      _engine = engine;
      _adBlock = block;
      _adBlockProvider = provider;
      _lite = lite;
    });
    if (!_onStart && isAvenWebUrl(_pageUrl)) {
      await _controller.reload();
    }
    if (_onStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _onStart) _startFocus.requestFocus();
      });
    } else if (_menuOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _menuOpen) _menuFocus.requestFocus();
      });
    }
  }

  Future<void> _toggleAdBlock() async {
    final next = _adBlock == AdBlock.off ? _adBlockProvider : AdBlock.off;
    await _store.saveAdBlock(next);
    await _input.setAdBlock(next.name);
    if (next != AdBlock.off) await _installAdblockCss();
    if (!mounted) return;
    setState(() => _adBlock = next);
  }

  @override
  void _syncChrome() {
    final open = _onStart || _menuOpen;
    _input.setChromeOpen(open);
    if (open) {
      _input.lockFocus();
    } else {
      _input.prepareForInput();
    }
  }

  void _openMenu() {
    if (_pageTyping) {
      _pageTyping = false;
      _input.setPageTyping(false);
    }
    _resetPointerState();
    setState(() => _menuOpen = true);
    _syncChrome();
    _surfaceFocus.canRequestFocus = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _menuOpen) _menuFocus.requestFocus();
    });
  }

  void _closeMenu() {
    setState(() {
      _menuOpen = false;
      _addressEditing = false;
    });
    _addressFocus.unfocus();
    _surfaceFocus.canRequestFocus = !_pageTyping;
    _syncChrome();
    if (!_pageTyping) _surfaceFocus.requestFocus();
  }

  void _onFieldMessage(JavaScriptMessage message) {
    final typing = message.message.trim() == '1';
    if (!mounted || typing == _pageTyping) return;
    _pageTyping = typing;
    _input.setPageTyping(typing);
    if (typing) {
      _surfaceFocus.canRequestFocus = false;
      _surfaceFocus.unfocus();
      return;
    }
    if (!_menuOpen) {
      _surfaceFocus.canRequestFocus = true;
    }
  }

  Future<void> _onPopupMessage(JavaScriptMessage message) async {
    final url = message.message.trim();
    if (!isAvenWebUrl(url) || !mounted || _popupOpen || url == _pageUrl) return;
    _popupOpen = true;
    final open = await showDialog<bool>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: ColoredBox(color: AvenColors.scrim),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640, minWidth: 420),
                child: Material(
                  color: AvenColors.background,
                  elevation: 24,
                  borderRadius: BorderRadius.circular(22),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 26, 28, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Pencere aÃ¢â€Å“Ã„Å¸Ã¢â€â‚¬Ã¢â€“â€™lsÃ¢â€â‚¬Ã¢â€“â€™n mÃ¢â€â‚¬Ã¢â€“â€™?', style: TextStyle(fontSize: 26)),
                        const SizedBox(height: 12),
                        Text(
                          url,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, color: AvenColors.textMuted, height: 1.4),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(120, 48),
                                foregroundColor: AvenColors.text,
                                backgroundColor: AvenColors.background,
                                overlayColor: AvenColors.hover,
                                textStyle: const TextStyle(fontSize: 16),
                              ),
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Ã¢â€â‚¬Ã¢â€“â€˜ptal'),
                            ),
                            const SizedBox(width: 12),
                            FilledButton(
                              autofocus: true,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(120, 48),
                                backgroundColor: AvenColors.accent,
                                foregroundColor: AvenColors.text,
                                overlayColor: AvenColors.hover,
                                textStyle: const TextStyle(fontSize: 16),
                              ),
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('AÃ¢â€Å“Ã„Å¸'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    _popupOpen = false;
    if (open == true && mounted) {
      await _controller.loadRequest(Uri.parse(url));
    }
  }

  Future<void> _onVideoMessage(JavaScriptMessage message) async {
    final parsed = parsePlayedVideo(message.message);
    if (parsed == null || !mounted || _openingVideo) return;
    final epoch = _mediaEpoch;
    var sources = _preferPlayable([
      for (final source in parsed.sources)
        if (_isStreamUrl(source.url))
          VideoSource(
            url: source.url,
            label: source.label,
            headers: _mediaHeadersFor(source.url),
          ),
    ]);
    // Kick/IVS often opens before the master playlist hits the pool.
    if (!_hasHls(sources)) {
      for (var i = 0; i < 10 && mounted && !_openingVideo; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (epoch != _mediaEpoch) return;
        final pooled = await _readMediaPool();
        if (pooled.isEmpty) continue;
        final merged = <VideoSource>[
          ...sources,
          for (final item in pooled)
            if (_isStreamUrl(item.url))
              VideoSource(
                url: item.url,
                label: item.label,
                headers: _mediaHeadersFor(item.url),
              ),
        ];
        sources = _preferPlayable(_dedupeSources(merged));
        if (_hasHls(sources)) break;
      }
    }
    if (epoch != _mediaEpoch || sources.isEmpty || !mounted || _openingVideo) return;
    final video = PageVideo(sources: sources, tracks: parsed.tracks);
    var initial = video.sources.first;
    for (final source in video.sources) {
      final u = source.url.toLowerCase();
      if (u.contains('.m3u8')) {
        initial = source;
        if (u.contains('live-video.net') || u.contains('master')) break;
      }
    }
    _openingVideo = true;
    _resetPointerState();
    await _suspendWebPage();
    if (!mounted) {
      _openingVideo = false;
      await _resumeWebPage();
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerPage(video: video, initialSource: initial),
      ),
    );
    _openingVideo = false;
    if (_onStart) {
      // Home stays on top Ãƒâ€Ãƒâ€¡ÃƒÂ¶ keep the page frozen underneath.
      return;
    }
    await _resumeWebPage();
    if (!mounted || _menuOpen) return;
    _resetPointerState();
    if (_webSize.isEmpty) {
      _cursor.value = Offset.zero;
    } else {
      _cursor.value = Offset(_webSize.width / 2, _webSize.height / 2);
    }
    _cursorVisible.value = true;
    _cursorLook.value = _CursorLook.normal;
    try {
      await _input.lockFocus();
      await _input.prepareForInput();
    } catch (_) {}
    _surfaceFocus.canRequestFocus = true;
    _surfaceFocus.requestFocus();
    await _wakeSurface();
  }

  bool _hasHls(List<VideoSource> sources) {
    return sources.any((s) {
      final u = s.url.toLowerCase();
      return u.contains('.m3u8') || u.contains('mpegurl') || u.contains('live-video.net');
    });
  }

  List<VideoSource> _dedupeSources(List<VideoSource> sources) {
    final seen = <String>{};
    final out = <VideoSource>[];
    for (final source in sources) {
      if (seen.add(source.url)) out.add(source);
    }
    return out;
  }

  Future<List<({String url, String label})>> _readMediaPool() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult(r'''
(function(){
  try {
    return JSON.stringify((window.__avenPool || []).map(function(item){
      return {url: item.url || '', label: item.label || 'Net'};
    }));
  } catch (e) { return '[]'; }
})();
''');
      final text = raw is String
          ? raw.replaceAll(r'\"', '"').replaceAll(RegExp(r'^"|"$'), '')
          : raw.toString();
      // runJavaScriptReturningResult often wraps JSON as a quoted JS string.
      dynamic decoded = raw;
      if (raw is String) {
        try {
          decoded = jsonDecode(raw);
        } catch (_) {
          try {
            decoded = jsonDecode(text);
          } catch (_) {
            return const [];
          }
        }
      }
      if (decoded is String) {
        try {
          decoded = jsonDecode(decoded);
        } catch (_) {
          return const [];
        }
      }
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map && item['url'] is String && (item['url'] as String).isNotEmpty)
            (url: item['url'] as String, label: (item['label'] as String?) ?? 'Net'),
      ];
    } catch (_) {
      return const [];
    }
  }

  bool _isStreamUrl(String url) {
    final lower = url.toLowerCase();
    final path = lower.split('?').first.split('#').first;
    if (path.endsWith('.ts') || path.endsWith('.m4s') || path.endsWith('.aac')) {
      return false;
    }
    if (!(lower.startsWith('http://') || lower.startsWith('https://'))) return false;
    // Only hand ExoPlayer real playlists / progressive files Ãƒâ€Ãƒâ€¡ÃƒÂ¶ Kick's bare
    // `/stream/` API hits and similar junk cause progressive 404s.
    if (lower.contains('.m3u8') || lower.contains('mpegurl')) return true;
    if (lower.contains('.mpd')) return true;
    if (RegExp(r'\.(mp4|webm|mkv|mov)([?#]|$)').hasMatch(lower)) return true;
    if (lower.contains('live-video.net') &&
        (lower.contains('/hls') ||
            lower.contains('playlist') ||
            lower.contains('master') ||
            lower.contains('.m3u8'))) {
      return true;
    }
    if (lower.contains('googlevideo.com') && lower.contains('mime=video')) return true;
    if (lower.contains('/hls/') && !lower.contains('/stream/')) return true;
    return false;
  }

  List<VideoSource> _preferPlayable(List<VideoSource> sources) {
    final ranked = [...sources];
    ranked.sort((a, b) {
      int score(VideoSource s) {
        final u = s.url.toLowerCase();
        if (u.contains('live-video.net') && u.contains('.m3u8')) return 0;
        if (u.contains('.m3u8') && u.contains('master')) return 1;
        if (u.contains('.m3u8')) return 2;
        if (u.contains('.mpd')) return 3;
        if (u.contains('.mp4')) return 4;
        return 5;
      }
      return score(a).compareTo(score(b));
    });
    return ranked;
  }

  Map<String, String> _mediaHeadersFor(String mediaUrl) {
    const fallbackUa =
        'Mozilla/5.0 (Linux; Android 12; SHIELD Android TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    final ua = (_userAgent != null && _userAgent!.trim().isNotEmpty) ? _userAgent! : fallbackUa;
    final pageUrl = _pageUrl;
    final page = pageUrl == null ? null : Uri.tryParse(pageUrl);
    final media = Uri.tryParse(mediaUrl);
    final referer = (pageUrl != null && pageUrl.isNotEmpty)
        ? pageUrl
        : (media != null ? '${media.scheme}://${media.host}/' : '');
    return {
      'User-Agent': ua,
      if (referer.isNotEmpty) 'Referer': referer,
      if (page != null && page.host.isNotEmpty) 'Origin': '${page.scheme}://${page.host}',
      'Accept': '*/*',
      'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
    };
  }

  Future<void> _handleBack() async {
    // One remote press can arrive both as a key and as a system back.
    final now = DateTime.now();
    if (now.difference(_lastBack) < const Duration(milliseconds: 400)) return;
    _lastBack = now;
    if (_fullscreenVideo != null) {
      final exit = _exitFullscreen;
      setState(() {
        _fullscreenVideo = null;
        _exitFullscreen = null;
      });
      exit?.call();
      _cursorVisible.value = true;
      _cursorHide?.cancel();
      return;
    }
    if (!_onStart && !_menuOpen) {
      _openMenu();
      return;
    }
    if (_menuOpen) {
      _closeMenu();
      return;
    }
    if (_onStart && isAvenWebUrl(_pageUrl)) {
      await _leaveStartToPage();
      return;
    }
    await SystemNavigator.pop();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _input.setHandler(null);
    for (final timer in _arrowRelease.values) {
      timer.cancel();
    }
    WidgetsBinding.instance.removeObserver(this);
    _wakeTimer?.cancel();
    _loadTimeout?.cancel();
    _cursorHide?.cancel();
    _ticker.dispose();
    _address.dispose();
    _addressFocus.dispose();
    _startFocus.dispose();
    _surfaceFocus.dispose();
    _menuFocus.dispose();
    _cursor.dispose();
    _cursorVisible.dispose();
    _cursorLook.dispose();
    _progress.dispose();
    _pageLoading.dispose();
    _surfaceKick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            _handleBack();
          },
          const SingleActivator(LogicalKeyboardKey.goBack): () {
            _handleBack();
          },
        },
        child: Focus(
          child: Scaffold(
        backgroundColor: AvenColors.background,
        body: Stack(
          children: [
            Focus(
              focusNode: _surfaceFocus,
              autofocus: !_onStart && _pageError == null,
              canRequestFocus: !_onStart && !_menuOpen && _pageError == null,
              skipTraversal: _onStart || _menuOpen || _pageError != null,
              descendantsAreFocusable: false,
              onKeyEvent: _onSurfaceKey,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  if (size != _webSize) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _rememberWebSize(size);
                    });
                  }
                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned.fill(
                        child: ValueListenableBuilder<int>(
                          valueListenable: _surfaceKick,
                          builder: (context, kick, child) {
                            return Transform.translate(
                              offset: Offset((kick.isOdd) ? 1 : 0, 0),
                              child: child,
                            );
                          },
                          child: WebViewWidget(
                            controller: _controller,
                            gestureRecognizers: _BrowserPageBase.pageGestures,
                          ),
                        ),
                      ),
                      if (!_onStart && !_menuOpen && _fullscreenVideo == null)
                        ValueListenableBuilder<_CursorLook>(
                          valueListenable: _cursorLook,
                          builder: (context, look, _) {
                            return ValueListenableBuilder<Offset>(
                              valueListenable: _cursor,
                              builder: (context, offset, _) {
                                final paint = _cursorPaintOrigin(offset, size);
                                return Positioned(
                                  left: paint.dx,
                                  top: paint.dy,
                                  width: 32,
                                  height: 32,
                                  child: IgnorePointer(child: _CursorDot(look: look)),
                                );
                              },
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _pageLoading,
              builder: (context, loading, _) {
                if (!loading || _onStart || _pageError != null) {
                  return const SizedBox.shrink();
                }
                return Positioned.fill(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _progress,
                    builder: (context, value, _) {
                      return _PageLoadingOverlay(progress: (value / 100).clamp(0.04, 1.0));
                    },
                  ),
                );
              },
            ),
            if (_onStart)
              _StartPage(
                address: _address,
                focusNode: _startFocus,
                editing: _startEditing,
                bookmarks: _bookmarks,
                onTapField: () => setState(() => _startEditing = true),
                onSubmit: _openInput,
                onOpenBookmark: _openInput,
                onOpenBookmarks: () => _openLibrary(section: 0),
                onOpenHistory: () => _openLibrary(section: 1),
                onSettings: _openSettings,
              ),
            if (_pageError != null && !_onStart)
              Positioned.fill(
                child: _PageErrorOverlay(
                  error: _pageError!,
                  onRetry: _retryPage,
                  onHome: _showStart,
                ),
              ),
            if (!_onStart)
              _FloatingMenu(
                open: _menuOpen,
                address: _address,
                addressFocus: _addressFocus,
                menuFocus: _menuFocus,
                editing: _addressEditing,
                canBack: _canBack,
                canForward: _canForward,
                saved: _saved,
                adBlockOn: _adBlock != AdBlock.off,
                zoom: _zoom,
                onTapField: () => setState(() => _addressEditing = true),
                onSubmit: _openInput,
                onBack: () => _controller.goBack(),
                onForward: () => _controller.goForward(),
                onReload: () {
                  setState(() => _pageError = null);
                  _controller.reload();
                },
                onHome: _showStart,
                onBookmark: _toggleBookmark,
                onLibrary: _openLibrary,
                onToggleAdBlock: _toggleAdBlock,
                onZoomOut: () => _setZoom(_zoom - 10),
                onZoomIn: () => _setZoom(_zoom + 10),
                onZoomReset: () => _setZoom(100),
                onSettings: _openSettings,
              ),
            if (_warnWebView)
              const Align(
                alignment: Alignment.topCenter,
                child: _WebViewWarning(),
              ),
            if (_fullscreenVideo != null)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: _fullscreenVideo!,
                ),
              ),
            if (_fullscreenVideo != null)
              ValueListenableBuilder<bool>(
                valueListenable: _cursorVisible,
                builder: (context, visible, _) {
                  return ValueListenableBuilder<_CursorLook>(
                    valueListenable: _cursorLook,
                    builder: (context, look, _) {
                      return ValueListenableBuilder<Offset>(
                        valueListenable: _cursor,
                        builder: (context, offset, _) {
                          final area = MediaQuery.sizeOf(context);
                          final paint = _cursorPaintOrigin(offset, area);
                          return Positioned(
                            left: paint.dx,
                            top: paint.dy,
                            width: 32,
                            height: 32,
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                opacity: visible ? 1 : 0,
                                duration: const Duration(milliseconds: 180),
                                child: _CursorDot(look: look),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
        ),
      ),
    );
  }
}
