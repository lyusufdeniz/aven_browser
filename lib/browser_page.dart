import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'aven_theme.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'bookmark_store.dart';
import 'library_page.dart';
import 'settings_page.dart';
import 'url_input.dart';
import 'video_catalog.dart';
import 'video_player_page.dart';
import 'web_input.dart';

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

class _BrowserPageState extends State<BrowserPage>
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
  Duration _lastTick = Duration.zero;
  final Map<LogicalKeyboardKey, Timer> _arrowRelease = {};
  DateTime _lastScroll = DateTime.fromMillisecondsSinceEpoch(0);

  static final Set<Factory<OneSequenceGestureRecognizer>> _pageGestures =
      <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      };

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
    // Keep images on — lite mode trims motion/media instead.
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
        if (!mounted) {
          onHide();
          return;
        }
        setState(() {
          _fullscreenVideo = widget;
          _exitFullscreen = onHide;
        });
        _surfaceFocus.canRequestFocus = true;
        _surfaceFocus.requestFocus();
        _bumpCursor();
      },
      onHideCustomWidget: () {
        if (!mounted) return;
        setState(() {
          _fullscreenVideo = null;
          _exitFullscreen = null;
        });
        _cursorVisible.value = true;
        _cursorHide?.cancel();
      },
    );
  }

  void _bumpCursor() {
    if (!mounted) return;
    if (!_cursorVisible.value) _cursorVisible.value = true;
    _cursorHide?.cancel();
    // Auto-hide only while a page player is in fullscreen.
    if (_fullscreenVideo == null) return;
    _cursorHide = Timer(const Duration(milliseconds: 2800), () {
      if (!mounted || _fullscreenVideo == null) return;
      _cursorVisible.value = false;
    });
  }

  bool _isWebUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    return url.startsWith('http://') || url.startsWith('https://');
  }

  void _onPageStarted(String url) {
    _mediaEpoch++;
    _progress.value = 8;
    _pageLoading.value = true;
    _loadTimeout?.cancel();
    _loadTimeout = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      _pageLoading.value = false;
      if (_progress.value < 100) _progress.value = 100;
    });
    setState(() {
      _pageUrl = url;
      _pageError = null;
      if (_isWebUrl(url)) {
        _onStart = false;
        _address.text = url;
      }
      _saved = _bookmarks.any((item) => item.url == url);
    });
    _installHooks();
    _input.watchMedia();
  }

  _PageError? _pageError;

  bool _sameDocument(String? a, String? b) {
    if (a == null || b == null || a.isEmpty || b.isEmpty) return false;
    Uri? left = Uri.tryParse(a);
    Uri? right = Uri.tryParse(b);
    if (left == null || right == null) return a == b;
    return left.replace(fragment: '').toString() == right.replace(fragment: '').toString();
  }

  Future<void> _onPageFinished(String url) async {
    _loadTimeout?.cancel();
    _pageLoading.value = false;
    _progress.value = 100;
    if (!_addressEditing) {
      await _input.prepareForInput();
    }
    await _installHooks();
    if (_lite) await _installLiteCss();
    if (_adBlock != AdBlock.off) await _installAdblockCss();
    await _input.watchMedia();
    final title = await _controller.getTitle();
    final back = await _controller.canGoBack();
    final forward = await _controller.canGoForward();
    if (!mounted) return;
    final label = (title == null || title.trim().isEmpty) ? url : title.trim();
    if (_isWebUrl(url) && _pageError == null) {
      await _store.addHistory(
        WebLink(title: label, url: url, savedAt: DateTime.now().millisecondsSinceEpoch),
      );
    }
    if (!mounted) return;
    setState(() {
      _pageUrl = url;
      _pageTitle = label;
      _canBack = back;
      _canForward = forward;
      if (_isWebUrl(url) && !_addressEditing) _address.text = url;
      _saved = _bookmarks.any((item) => item.url == url);
      if (_isWebUrl(url)) _onStart = false;
    });
    _wakeSurface();
  }

  void _onError(WebResourceError error) {
    if (error.isForMainFrame != true || !mounted) return;
    _loadTimeout?.cancel();
    _pageLoading.value = false;
    _progress.value = 100;
    _holdSurfaceForError();
    setState(() {
      _pageError = _PageError.fromResource(error);
    });
  }

  void _onHttpError(HttpResponseError error) {
    if (!mounted) return;
    final code = error.response?.statusCode;
    if (code == null || code < 400) return;
    final uri = error.response?.uri ?? error.request?.uri;
    final url = uri?.toString();
    if (url == null) return;
    final current = _pageUrl ?? _address.text;
    if (!_sameDocument(url, current)) return;
    _loadTimeout?.cancel();
    _pageLoading.value = false;
    _progress.value = 100;
    _holdSurfaceForError();
    setState(() {
      _pageError = _PageError.fromHttp(code, url);
    });
  }

  void _holdSurfaceForError() {
    _held.clear();
    _direction = Offset.zero;
    if (_ticker.isActive) _ticker.stop();
    _surfaceFocus.canRequestFocus = false;
    _surfaceFocus.unfocus();
    _addressFocus.unfocus();
  }

  void _retryPage() {
    final url = _pageError?.url ?? _pageUrl ?? _address.text;
    setState(() => _pageError = null);
    _surfaceFocus.canRequestFocus = true;
    if (_isWebUrl(url)) {
      _controller.loadRequest(Uri.parse(url));
    } else {
      _controller.reload();
    }
  }

  Timer? _wakeTimer;

  @override
  void didChangeMetrics() {
    _wakeTimer?.cancel();
    _wakeTimer = Timer(const Duration(milliseconds: 60), () {
      if (mounted) _wakeSurface();
    });
  }

  Future<void> _wakeSurface() async {
    await _input.refreshSurface();
    if (!mounted) return;
    _surfaceKick.value = 1;
    final origin = _cursor.value;
    _cursor.value = origin + const Offset(0.4, 0);
    await Future<void>.delayed(const Duration(milliseconds: 48));
    if (!mounted) return;
    _cursor.value = origin;
    _surfaceKick.value = 0;
    await _input.refreshSurface();
  }

  Future<void> _installHooks() async {
    try {
      await _controller.runJavaScript(_pageHooks);
      await _controller.runJavaScript(videoWatchScript);
    } catch (_) {}
  }

  Future<void> _installLiteCss() async {
    try {
      await _controller.runJavaScript(r'''
(function(){
  var s = document.getElementById('aven-lite-style');
  if (!s) {
    s = document.createElement('style');
    s.id = 'aven-lite-style';
    (document.head || document.documentElement).appendChild(s);
  }
  s.textContent = '*,*::before,*::after{animation:none!important;transition:none!important;scroll-behavior:auto!important}html{scroll-behavior:auto!important}';
  function quietMedia(){
    document.querySelectorAll('video,audio').forEach(function(m){
      try {
        m.pause();
        m.removeAttribute('autoplay');
        m.autoplay = false;
        m.preload = 'none';
      } catch(e) {}
    });
  }
  function lazyImages(){
    document.querySelectorAll('img').forEach(function(img){
      try {
        if (!img.getAttribute('loading')) img.loading = 'lazy';
        img.decoding = 'async';
      } catch(e) {}
    });
    document.querySelectorAll('iframe').forEach(function(f){
      try { if (!f.getAttribute('loading')) f.loading = 'lazy'; } catch(e) {}
    });
  }
  quietMedia();
  lazyImages();
  if (!window.__avenLiteObs) {
    window.__avenLiteObs = true;
    new MutationObserver(function(){ quietMedia(); lazyImages(); })
      .observe(document.documentElement, {childList:true, subtree:true});
  }
})();
''');
    } catch (_) {}
  }

  Future<void> _installAdblockCss() async {
    try {
      await _controller.runJavaScript(r'''
(function(){
  if (document.getElementById('aven-adblock-style')) return;
  var s = document.createElement('style');
  s.id = 'aven-adblock-style';
  s.textContent = '#cts_test,#ad_ctd,.adsbox,.textads,.banner_ads,.banner-ads,.adbox,.ADBox,.AdBox,.adbox-wrapper,.adSocial,.ad-unit,.afs_ads,.ad-zone,.ad-space,[id^="google_ads_"],[id^="div-gpt-ad"],[class*="adsbygoogle"],iframe[id^="google_ads_iframe"],iframe[src*="doubleclick.net"],iframe[src*="googlesyndication.com"]{display:none!important;visibility:hidden!important;height:0!important;max-height:0!important;overflow:hidden!important;opacity:0!important;pointer-events:none!important}';
  (document.head || document.documentElement).appendChild(s);
})();
''');
    } catch (_) {}
  }

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startFocus.requestFocus();
    });
  }

  Future<void> _toggleBookmark() async {
    final url = _pageUrl;
    if (!_isWebUrl(url)) return;
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
    if (!_onStart && _isWebUrl(_pageUrl)) {
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
    _held.clear();
    _direction = Offset.zero;
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
    if (!_isWebUrl(url) || !mounted || _popupOpen || url == _pageUrl) return;
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
                        const Text('Pencere açılsın mı?', style: TextStyle(fontSize: 26)),
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
                              child: const Text('İptal'),
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
                              child: const Text('Aç'),
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

  Future<void> _onWatchedMedia(String url) async {
    if (!mounted || !_isWebUrl(url)) return;
    final epoch = _mediaEpoch;
    try {
      await _controller.runJavaScript('window.__avenOffer && window.__avenOffer(${jsonEncode(url)});');
    } catch (_) {}
    if (epoch != _mediaEpoch) return;
  }

  Future<void> _onVideoMessage(JavaScriptMessage message) async {
    final parsed = parsePlayedVideo(message.message);
    if (parsed == null || !mounted || _openingVideo) return;
    final sources = [
      for (final source in parsed.sources)
        if (_isStreamUrl(source.url))
          VideoSource(
            url: source.url,
            label: source.label,
            headers: _mediaHeadersFor(source.url),
          ),
    ];
    if (sources.isEmpty) return;
    final video = PageVideo(sources: _preferPlayable(sources), tracks: parsed.tracks);
    var initial = video.sources.first;
    for (final source in video.sources) {
      if (source.url.toLowerCase().contains('.m3u8')) {
        initial = source;
        break;
      }
    }
    _openingVideo = true;
    try {
      await _controller.runJavaScript(
        "document.querySelectorAll('video,audio').forEach(function(v){try{v.pause()}catch(e){}});",
      );
    } catch (_) {}
    try {
      await _input.pauseWebView();
    } catch (_) {}
    if (!mounted) {
      _openingVideo = false;
      try {
        await _input.resumeWebView();
      } catch (_) {}
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerPage(video: video, initialSource: initial),
      ),
    );
    _openingVideo = false;
    try {
      await _input.resumeWebView();
    } catch (_) {}
    if (!mounted || _menuOpen) return;
    _surfaceFocus.canRequestFocus = true;
    _surfaceFocus.requestFocus();
  }

  bool _isStreamUrl(String url) {
    final lower = url.toLowerCase();
    final path = lower.split('?').first.split('#').first;
    if (path.endsWith('.ts')) return false;
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  List<VideoSource> _preferPlayable(List<VideoSource> sources) {
    final ranked = [...sources];
    ranked.sort((a, b) {
      int score(VideoSource s) {
        final u = s.url.toLowerCase();
        if (u.contains('.m3u8')) return 0;
        if (u.contains('.mpd')) return 1;
        if (u.contains('.mp4')) return 2;
        return 3;
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
    if (_onStart && _isWebUrl(_pageUrl)) {
      setState(() => _onStart = false);
      _surfaceFocus.canRequestFocus = true;
      _surfaceFocus.requestFocus();
      return;
    }
    await SystemNavigator.pop();
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.016
        : ((elapsed - _lastTick).inMicroseconds / 1000000).clamp(0.0, 0.05);
    _lastTick = elapsed;
    if (_direction == Offset.zero || _webSize.isEmpty || _menuOpen || _onStart) {
      if (_ticker.isActive) _ticker.stop();
      _lastTick = Duration.zero;
      if (_cursorLook.value != _CursorLook.normal) {
        _cursorLook.value = _CursorLook.normal;
      }
      return;
    }
    final current = _cursor.value;
    var next = current + _direction * 300 * dt;
    var scrollX = 0.0;
    var scrollY = 0.0;
    if (next.dx < 0) {
      scrollX = next.dx;
      next = Offset(0, next.dy);
    } else if (next.dx > _webSize.width) {
      scrollX = next.dx - _webSize.width;
      next = Offset(_webSize.width, next.dy);
    }
    if (next.dy < 0) {
      scrollY = next.dy;
      next = Offset(next.dx, 0);
    } else if (next.dy > _webSize.height) {
      scrollY = next.dy - _webSize.height;
      next = Offset(next.dx, _webSize.height);
    }
    if (next != current) {
      _cursor.value = next;
      _bumpCursor();
    }
    final look = scrollY < 0
        ? _CursorLook.up
        : scrollY > 0
            ? _CursorLook.down
            : scrollX < 0
                ? _CursorLook.left
                : scrollX > 0
                    ? _CursorLook.right
                    : _CursorLook.normal;
    if (_cursorLook.value != look) _cursorLook.value = look;
    if (scrollX != 0 || scrollY != 0) {
      final now = DateTime.now();
      if (now.difference(_lastScroll).inMilliseconds > 40) {
        _lastScroll = now;
        _scrollBy(scrollX.sign * 28, scrollY.sign * 28, next.dx, next.dy);
      }
    }
  }

  void _syncDirection() {
    var x = 0.0;
    var y = 0.0;
    if (_held.contains(LogicalKeyboardKey.arrowLeft)) x -= 1;
    if (_held.contains(LogicalKeyboardKey.arrowRight)) x += 1;
    if (_held.contains(LogicalKeyboardKey.arrowUp)) y -= 1;
    if (_held.contains(LogicalKeyboardKey.arrowDown)) y += 1;
    final next = Offset(x, y);
    if (next == _direction) return;
    _direction = next;
    if (next != Offset.zero) _bumpCursor();
    if (next != Offset.zero && !_ticker.isActive && !_menuOpen && !_onStart && _pageError == null) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  bool _onHardwareKey(KeyEvent event) {
    if (!mounted || _onStart || _menuOpen || _pageTyping || _pageError != null) {
      return false;
    }
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    if (!_isArrow(event.logicalKey)) return false;
    if (!_surfaceFocus.hasFocus) {
      _surfaceFocus.canRequestFocus = true;
      _surfaceFocus.requestFocus();
    }
    _setArrow(event.logicalKey, event is! KeyUpEvent);
    return true;
  }

  void _setArrow(LogicalKeyboardKey key, bool down) {
    if (down) {
      _arrowRelease.remove(key)?.cancel();
      _held.add(key);
      _syncDirection();
      return;
    }
    _arrowRelease[key]?.cancel();
    _arrowRelease[key] = Timer(const Duration(milliseconds: 120), () {
      _arrowRelease.remove(key);
      _held.remove(key);
      _syncDirection();
    });
  }

  KeyEventResult _onSurfaceKey(FocusNode node, KeyEvent event) {
    if (_onStart || _pageTyping || _pageError != null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_isArrow(key)) {
      _setArrow(key, event is! KeyUpEvent);
      return KeyEventResult.handled;
    }
    final typed = event.character;
    if (event is KeyDownEvent && typed != null && _isTypingCharacter(typed)) {
      if (!_menuOpen) {
        setState(() => _menuOpen = true);
        _syncChrome();
      }
      final replacing = _address.text == _pageUrl;
      _address.text = replacing ? typed : '${_address.text}$typed';
      _address.selection = TextSelection.collapsed(offset: _address.text.length);
      return KeyEventResult.handled;
    }
    final activate = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;
    if (activate && event is KeyDownEvent) {
      if (_address.text.isNotEmpty && _address.text != _pageUrl) {
        _openInput(_address.text);
      } else {
        _activate();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _activate() async {
    _bumpCursor();
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cursor = _cursor.value;
    await _input.tap(cursor.dx * pixelRatio, cursor.dy * pixelRatio);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    try {
      final result = await _controller.runJavaScriptReturningResult(_editableCheck);
      if (_jsTrue(result)) await _input.focusForTyping();
    } catch (_) {}
  }

  Future<void> _scrollBy(double dx, double dy, double x, double y) async {
    final script = '''
(function() {
  var x = $x, y = $y, dx = $dx, dy = $dy;
  var el = document.elementFromPoint(x, y);
  while (el && el !== document.documentElement) {
    var style = getComputedStyle(el);
    var canY = (style.overflowY === 'auto' || style.overflowY === 'scroll') &&
        el.scrollHeight > el.clientHeight + 2;
    var canX = (style.overflowX === 'auto' || style.overflowX === 'scroll') &&
        el.scrollWidth > el.clientWidth + 2;
    if ((dy !== 0 && canY) || (dx !== 0 && canX)) {
      el.scrollBy(dx, dy);
      return;
    }
    el = el.parentElement;
  }
  window.scrollBy(dx, dy);
})();
''';
    try {
      await _controller.runJavaScript(script);
    } catch (_) {}
  }

  void _rememberWebSize(Size size) {
    if (size == _webSize || size.isEmpty) return;
    _webSize = size;
    if (!_placed) {
      _placed = true;
      _cursor.value = Offset(size.width / 2, size.height / 2);
      return;
    }
    final current = _cursor.value;
    _cursor.value = Offset(
      current.dx.clamp(0, size.width).toDouble(),
      current.dy.clamp(0, size.height).toDouble(),
    );
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
                            gestureRecognizers: _pageGestures,
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
                                return Positioned(
                                  left: offset.dx - 16,
                                  top: offset.dy - 16,
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
                          return Positioned(
                            left: offset.dx - 16,
                            top: offset.dy - 16,
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

enum _CursorLook { normal, up, down, left, right }

bool _isArrow(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown;
}

bool _isTypingCharacter(String value) {
  if (value.length != 1) return false;
  final code = value.codeUnitAt(0);
  return code >= 32 && code != 127;
}

bool _jsTrue(Object value) {
  if (value is bool) return value;
  final text = value.toString().replaceAll('"', '').trim().toLowerCase();
  return text == 'true';
}

class _PageError {
  const _PageError({
    required this.title,
    required this.detail,
    this.code,
    this.url,
  });

  final String title;
  final String detail;
  final int? code;
  final String? url;

  factory _PageError.fromHttp(int code, String url) {
    final title = switch (code) {
      400 => 'Geçersiz istek',
      401 => 'Giriş gerekli',
      403 => 'Erişim engellendi',
      404 => 'Sayfa bulunamadı',
      408 => 'İstek zaman aşımı',
      410 => 'Sayfa kaldırıldı',
      429 => 'Çok fazla istek',
      500 => 'Sunucu hatası',
      502 => 'Ağ geçidi hatası',
      503 => 'Servis kullanılamıyor',
      504 => 'Ağ geçidi zaman aşımı',
      _ when code >= 500 => 'Sunucu hatası',
      _ => 'Sayfa yüklenemedi',
    };
    return _PageError(
      code: code,
      title: title,
      detail: 'Sunucu $code kodu döndürdü.',
      url: url,
    );
  }

  factory _PageError.fromResource(WebResourceError error) {
    final type = error.errorType;
    final title = switch (type) {
      WebResourceErrorType.hostLookup => 'Site bulunamadı',
      WebResourceErrorType.timeout => 'Bağlantı zaman aşımı',
      WebResourceErrorType.connect => 'Bağlantı kurulamadı',
      WebResourceErrorType.failedSslHandshake => 'Güvenli bağlantı başarısız',
      WebResourceErrorType.tooManyRequests => 'Çok fazla istek',
      WebResourceErrorType.unsafeResource => 'Güvensiz kaynak',
      WebResourceErrorType.webContentProcessTerminated => 'Sayfa çöktü',
      WebResourceErrorType.badUrl => 'Geçersiz adres',
      WebResourceErrorType.fileNotFound => 'Sayfa bulunamadı',
      _ => 'Sayfa yüklenemedi',
    };
    return _PageError(
      title: title,
      detail: error.description,
      url: error.url,
    );
  }
}

class _PageLoadingOverlay extends StatelessWidget {
  const _PageLoadingOverlay({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: ColoredBox(
        color: AvenColors.background,
        child: Center(
          child: SizedBox(
            width: 72,
            height: 72,
            child: CustomPaint(
              painter: _RingProgressPainter(
                progress: progress.clamp(0.04, 1.0),
                track: AvenColors.row,
                fill: AvenColors.hover,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingProgressPainter extends CustomPainter {
  _RingProgressPainter({
    required this.progress,
    required this.track,
    required this.fill,
  });

  final double progress;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = size.shortestSide * 0.1;
    final radius = (size.shortestSide - stroke) / 2;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.57079632679,
      progress * 6.28318530718,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.track != track ||
        oldDelegate.fill != fill;
  }
}

class _PageErrorOverlay extends StatefulWidget {
  const _PageErrorOverlay({
    required this.error,
    required this.onRetry,
    required this.onHome,
  });

  final _PageError error;
  final VoidCallback onRetry;
  final VoidCallback onHome;

  @override
  State<_PageErrorOverlay> createState() => _PageErrorOverlayState();
}

class _PageErrorOverlayState extends State<_PageErrorOverlay> {
  late final FocusNode _retryFocus = FocusNode(debugLabel: 'error-retry');
  late final FocusNode _homeFocus = FocusNode(debugLabel: 'error-home');
  Timer? _focusGuard;

  @override
  void initState() {
    super.initState();
    _retryFocus.addListener(_onFocusChanged);
    _homeFocus.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _claimFocus());
  }

  @override
  void dispose() {
    _focusGuard?.cancel();
    _retryFocus.removeListener(_onFocusChanged);
    _homeFocus.removeListener(_onFocusChanged);
    _retryFocus.dispose();
    _homeFocus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_retryFocus.hasFocus || _homeFocus.hasFocus) {
      _focusGuard?.cancel();
      return;
    }
    _focusGuard?.cancel();
    _focusGuard = Timer(const Duration(milliseconds: 80), _claimFocus);
  }

  void _claimFocus() {
    if (!mounted) return;
    if (_retryFocus.hasFocus || _homeFocus.hasFocus) return;
    _retryFocus.requestFocus();
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight && index == 0) {
      _homeFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft && index == 1) {
      _retryFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (_isArrow(key)) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space) {
      if (index == 0) {
        widget.onRetry();
      } else {
        widget.onHome();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.error.code;
    return FocusScope(
      autofocus: true,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AvenColors.background,
                AvenColors.ink,
                Color(0xFF101628),
              ],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (code != null)
                      Text(
                        '$code',
                        style: TextStyle(
                          fontFamily: 'Cal Sans',
                          fontSize: 88,
                          fontWeight: FontWeight.w600,
                          height: 1,
                          letterSpacing: -2,
                          color: AvenColors.error.withValues(alpha: 0.9),
                        ),
                      )
                    else
                      const Icon(Icons.wifi_off_rounded, size: 64, color: AvenColors.hover),
                    const SizedBox(height: 18),
                    Text(
                      widget.error.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: AvenColors.mist,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.error.detail,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AvenColors.textMuted,
                        height: 1.4,
                      ),
                    ),
                    if (widget.error.url != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.error.url!,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AvenColors.teal),
                      ),
                    ],
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(0),
                          child: _ErrorAction(
                            focusNode: _retryFocus,
                            label: 'Yeniden dene',
                            icon: Icons.refresh,
                            onPressed: widget.onRetry,
                            onKeyEvent: (event) => _onKey(0, event),
                          ),
                        ),
                        const SizedBox(width: 14),
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(1),
                          child: _ErrorAction(
                            focusNode: _homeFocus,
                            label: 'Başlangıç',
                            icon: Icons.home_outlined,
                            onPressed: widget.onHome,
                            onKeyEvent: (event) => _onKey(1, event),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorAction extends StatelessWidget {
  const _ErrorAction({
    required this.focusNode,
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.onKeyEvent,
  });

  final FocusNode focusNode;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) => onKeyEvent(event),
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          return AvenFocusZoom(
            focused: focused,
            child: ExcludeFocus(
            child: TextButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
              style: TextButton.styleFrom(
                foregroundColor: focused ? AvenColors.mist : AvenColors.text,
                backgroundColor: focused ? AvenColors.hover : AvenColors.accentBlue,
                overlayColor: AvenColors.hover,
                side: focused
                    ? const BorderSide(color: AvenColors.hover, width: 2)
                    : const BorderSide(color: AvenColors.row),
                minimumSize: const Size(160, 52),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          );
        },
      ),
    );
  }
}

class _CursorDot extends StatelessWidget {
  const _CursorDot({this.look = _CursorLook.normal});

  final _CursorLook look;

  IconData? get _icon => switch (look) {
        _CursorLook.up => Icons.keyboard_arrow_up_rounded,
        _CursorLook.down => Icons.keyboard_arrow_down_rounded,
        _CursorLook.left => Icons.keyboard_arrow_left_rounded,
        _CursorLook.right => Icons.keyboard_arrow_right_rounded,
        _CursorLook.normal => null,
      };

  @override
  Widget build(BuildContext context) {
    final scrolling = look != _CursorLook.normal;
    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: scrolling ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: scrolling ? BorderRadius.circular(10) : null,
          color: scrolling
              ? AvenColors.hover
              : AvenColors.hover.withValues(alpha: 0.9),
          border: Border.all(color: AvenColors.text, width: scrolling ? 2 : 3),
          boxShadow: const [
            BoxShadow(color: AvenColors.scrim, blurRadius: 6),
          ],
        ),
        alignment: Alignment.center,
        child: _icon == null
            ? null
            : Icon(_icon, size: 26, color: AvenColors.text),
      ),
    );
  }
}

class _StartPage extends StatefulWidget {
  const _StartPage({
    required this.address,
    required this.focusNode,
    required this.editing,
    required this.bookmarks,
    required this.onTapField,
    required this.onSubmit,
    required this.onOpenBookmark,
    required this.onOpenBookmarks,
    required this.onOpenHistory,
    required this.onSettings,
  });

  final TextEditingController address;
  final FocusNode focusNode;
  final bool editing;
  final List<WebLink> bookmarks;
  final VoidCallback onTapField;
  final ValueChanged<String> onSubmit;
  final ValueChanged<String> onOpenBookmark;
  final VoidCallback onOpenBookmarks;
  final VoidCallback onOpenHistory;
  final VoidCallback onSettings;

  @override
  State<_StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<_StartPage> {
  static const _bookmarkLimit = 24;
  static const _suggestions = <_Suggestion>[
    _Suggestion(
      title: 'YouTube TV',
      url: 'https://www.youtube.com/tv',
      image: 'assets/suggestions/youtube.png',
      background: Color(0xFFFFFFFF),
    ),
    _Suggestion(
      title: 'Netflix',
      url: 'https://www.netflix.com/',
      image: 'assets/suggestions/netflix.png',
      background: Color(0xFF101010),
    ),
    _Suggestion(
      title: 'Prime Video',
      url: 'https://www.primevideo.com/',
      image: 'assets/suggestions/prime.webp',
      background: Color(0xFF1AA1FB),
    ),
    _Suggestion(
      title: 'Max',
      url: 'https://www.max.com/',
      image: 'assets/suggestions/max.png',
      background: Color(0xFF030327),
    ),
    _Suggestion(
      title: 'Disney+',
      url: 'https://www.disneyplus.com/',
      image: 'assets/suggestions/disney.webp',
      background: Color(0xFF000F4C),
    ),
    _Suggestion(
      title: 'Spotify',
      url: 'https://open.spotify.com/',
      image: 'assets/suggestions/spotify.webp',
      background: Color(0xFF000000),
    ),
    _Suggestion(
      title: 'Twitch',
      url: 'https://www.twitch.tv/',
      image: 'assets/suggestions/twitch.png',
      background: Color(0xFF6441A5),
    ),
    _Suggestion(
      title: 'Apple TV+',
      url: 'https://tv.apple.com/',
      image: 'assets/suggestions/appletv.png',
      background: Color(0xFF000000),
    ),
    _Suggestion(
      title: 'Kick',
      url: 'https://kick.com/',
      image: 'assets/suggestions/kick.png',
      background: Color(0xFF000000),
    ),
  ];

  late final List<FocusNode> _suggestFocus =
      List.generate(_suggestions.length, (_) => FocusNode());
  late final List<FocusNode> _bookmarkFocus =
      List.generate(_bookmarkLimit, (_) => FocusNode());
  late final List<FocusNode> _actionFocus = List.generate(3, (_) => FocusNode());
  final _pageScroll = ScrollController();
  final _suggestScroll = ScrollController();
  final _bookmarkScroll = ScrollController();

  static const _suggestItemWidth = 220.0;
  static const _suggestGap = 14.0;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _suggestFocus.length; i++) {
      final index = i;
      _suggestFocus[index].addListener(() {
        if (_suggestFocus[index].hasFocus) {
          _scrollSuggestTo(index);
          _ensureVisible(_suggestFocus[index]);
        }
      });
    }
    for (var i = 0; i < _bookmarkFocus.length; i++) {
      final index = i;
      _bookmarkFocus[index].addListener(() {
        if (_bookmarkFocus[index].hasFocus) {
          _scrollBookmarkTo(index);
          _ensureVisible(_bookmarkFocus[index]);
        }
      });
    }
    for (var i = 0; i < _actionFocus.length; i++) {
      final index = i;
      _actionFocus[index].addListener(() {
        if (_actionFocus[index].hasFocus) {
          _ensureVisible(_actionFocus[index]);
        }
      });
    }
  }

  @override
  void dispose() {
    _pageScroll.dispose();
    _suggestScroll.dispose();
    _bookmarkScroll.dispose();
    for (final node in _suggestFocus) {
      node.dispose();
    }
    for (final node in _bookmarkFocus) {
      node.dispose();
    }
    for (final node in _actionFocus) {
      node.dispose();
    }
    super.dispose();
  }

  void _ensureVisible(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = node.context;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.4,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _scrollSuggestTo(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_suggestScroll.hasClients) return;
      final extent = _suggestItemWidth + _suggestGap;
      final target = (index * extent)
          .clamp(0.0, _suggestScroll.position.maxScrollExtent);
      _suggestScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _scrollBookmarkTo(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_bookmarkScroll.hasClients) return;
      final extent = _suggestItemWidth + _suggestGap;
      final target = (index * extent)
          .clamp(0.0, _bookmarkScroll.position.maxScrollExtent);
      _bookmarkScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  static _Suggestion? _matchSuggestion(String url) {
    final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
    if (host.isEmpty) return null;
    bool hits(String needle) =>
        host == needle || host.endsWith('.$needle') || host.contains(needle);

    if (hits('youtube.com') || hits('youtu.be')) {
      return _suggestions.firstWhere((s) => s.title.startsWith('YouTube'));
    }
    if (hits('netflix.com')) {
      return _suggestions.firstWhere((s) => s.title == 'Netflix');
    }
    if (hits('primevideo.com') || hits('amazon.com') || hits('amazon.com.tr')) {
      return _suggestions.firstWhere((s) => s.title == 'Prime Video');
    }
    if (hits('max.com') || hits('hbomax.com')) {
      return _suggestions.firstWhere((s) => s.title == 'Max');
    }
    if (hits('disneyplus.com') || hits('disney.com')) {
      return _suggestions.firstWhere((s) => s.title == 'Disney+');
    }
    if (hits('spotify.com')) {
      return _suggestions.firstWhere((s) => s.title == 'Spotify');
    }
    if (hits('twitch.tv')) {
      return _suggestions.firstWhere((s) => s.title == 'Twitch');
    }
    if (hits('tv.apple.com')) {
      return _suggestions.firstWhere((s) => s.title == 'Apple TV+');
    }
    if (hits('kick.com')) {
      return _suggestions.firstWhere((s) => s.title == 'Kick');
    }
    return null;
  }

  int get _bookmarkCount => widget.bookmarks.length.clamp(0, _bookmarkLimit);

  void _focusAfterSearch() {
    _actionFocus.first.requestFocus();
  }

  void _focusAfterActions() {
    _suggestFocus.first.requestFocus();
  }

  void _fromAddress(LogicalKeyboardKey key) {
    if (key != LogicalKeyboardKey.arrowDown) return;
    _focusAfterSearch();
  }

  void _onSuggestKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight && index < _suggestions.length - 1) {
      _suggestFocus[index + 1].requestFocus();
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft && index > 0) {
      _suggestFocus[index - 1].requestFocus();
      return;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _actionFocus.first.requestFocus();
      return;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_bookmarkCount > 0) {
        _bookmarkFocus.first.requestFocus();
      }
      return;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space) {
      widget.onOpenBookmark(_suggestions[index].url);
    }
  }

  void _onBookmarkKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight && index < _bookmarkCount - 1) {
      _bookmarkFocus[index + 1].requestFocus();
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft && index > 0) {
      _bookmarkFocus[index - 1].requestFocus();
      return;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _suggestFocus.first.requestFocus();
      return;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space) {
      widget.onOpenBookmark(widget.bookmarks[index].url);
    }
  }

  void _onActionKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight && index < 2) {
      _actionFocus[index + 1].requestFocus();
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft && index > 0) {
      _actionFocus[index - 1].requestFocus();
      return;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.focusNode.requestFocus();
      return;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _focusAfterActions();
      return;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space) {
      switch (index) {
        case 0:
          widget.onOpenHistory();
        case 1:
          widget.onOpenBookmarks();
        default:
          widget.onSettings();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks = widget.bookmarks.take(_bookmarkLimit).toList();
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: ColoredBox(
        color: AvenColors.background,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              controller: _pageScroll,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 48),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 64).clamp(0.0, double.infinity),
                  maxWidth: 980,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    const Text(
                      'aven',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cal Sans',
                        fontSize: 56,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1.2,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(0),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: _AddressField(
                            controller: widget.address,
                            focusNode: widget.focusNode,
                            editing: widget.editing,
                            autofocus: true,
                            onTap: widget.onTapField,
                            onSubmit: widget.onSubmit,
                            onArrow: _fromAddress,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(1),
                          child: _StartAction(
                            focusNode: _actionFocus[0],
                            icon: Icons.history,
                            label: 'Geçmiş',
                            onPressed: widget.onOpenHistory,
                            onKeyEvent: (event) => _onActionKey(0, event),
                          ),
                        ),
                        const SizedBox(width: 14),
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(2),
                          child: _StartAction(
                            focusNode: _actionFocus[1],
                            icon: Icons.star_outline,
                            label: 'Yer imleri',
                            onPressed: widget.onOpenBookmarks,
                            onKeyEvent: (event) => _onActionKey(1, event),
                          ),
                        ),
                        const SizedBox(width: 14),
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(3),
                          child: _StartAction(
                            focusNode: _actionFocus[2],
                            icon: Icons.settings,
                            label: 'Ayarlar',
                            onPressed: widget.onSettings,
                            onKeyEvent: (event) => _onActionKey(2, event),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Öneriler',
                        style: TextStyle(fontSize: 16, color: AvenColors.textMuted),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 148,
                      child: ListView.separated(
                        controller: _suggestScroll,
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(0, 10, 48, 10),
                        itemCount: _suggestions.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: _suggestGap),
                        itemBuilder: (context, index) {
                          final item = _suggestions[index];
                          return FocusTraversalOrder(
                            order: NumericFocusOrder(10 + index.toDouble()),
                            child: _SuggestionPoster(
                              suggestion: item,
                              focusNode: _suggestFocus[index],
                              onKeyEvent: (event) => _onSuggestKey(index, event),
                              onPressed: () => widget.onOpenBookmark(item.url),
                            ),
                          );
                        },
                      ),
                    ),
                    if (bookmarks.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Yer imleri',
                          style: TextStyle(
                            fontSize: 16,
                            color: AvenColors.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 148,
                        child: ListView.separated(
                          controller: _bookmarkScroll,
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(0, 10, 48, 10),
                          itemCount: bookmarks.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: _suggestGap),
                          itemBuilder: (context, index) {
                            final link = bookmarks[index];
                            return FocusTraversalOrder(
                              order: NumericFocusOrder(40 + index.toDouble()),
                              child: _BookmarkPoster(
                                link: link,
                                matched: _matchSuggestion(link.url),
                                focusNode: _bookmarkFocus[index],
                                onKeyEvent: (event) =>
                                    _onBookmarkKey(index, event),
                                onPressed: () =>
                                    widget.onOpenBookmark(link.url),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Suggestion {
  const _Suggestion({
    required this.title,
    required this.url,
    required this.image,
    required this.background,
  });

  final String title;
  final String url;
  final String image;
  final Color background;
}

class _SuggestionPoster extends StatelessWidget {
  const _SuggestionPoster({
    required this.suggestion,
    required this.focusNode,
    required this.onKeyEvent,
    required this.onPressed,
  });

  final _Suggestion suggestion;
  final FocusNode focusNode;
  final ValueChanged<KeyEvent> onKeyEvent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        onKeyEvent(event);
        return event is KeyDownEvent &&
                (_isArrow(event.logicalKey) ||
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                    event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.gameButtonA ||
                    event.logicalKey == LogicalKeyboardKey.space)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          return AvenFocusZoom(
            focused: focused,
            scale: 1.12,
            child: SizedBox(
            width: 220,
            height: 128,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: suggestion.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: focused ? AvenColors.focus : Colors.transparent,
                      width: focused ? 3 : 0,
                    ),
                    boxShadow: focused
                        ? [
                            BoxShadow(
                              color: AvenColors.focus.withValues(alpha: 0.45),
                              blurRadius: 22,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(focused ? 11 : 14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: suggestion.background),
                        Image.asset(
                          suggestion.image,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (context, error, stack) => Center(
                            child: Text(
                              suggestion.title,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: suggestion.background.computeLuminance() > 0.45
                                    ? Colors.black
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          );
        },
      ),
    );
  }
}

class _BookmarkPoster extends StatelessWidget {
  const _BookmarkPoster({
    required this.link,
    required this.matched,
    required this.focusNode,
    required this.onKeyEvent,
    required this.onPressed,
  });

  final WebLink link;
  final _Suggestion? matched;
  final FocusNode focusNode;
  final ValueChanged<KeyEvent> onKeyEvent;
  final VoidCallback onPressed;

  String get _favicon {
    final host = Uri.tryParse(link.url)?.host ?? '';
    if (host.isEmpty) return '';
    return 'https://www.google.com/s2/favicons?domain=$host&sz=128';
  }

  Color get _fallbackBg {
    final host = Uri.tryParse(link.url)?.host ?? link.title;
    var hash = 0;
    for (final cu in host.codeUnits) {
      hash = 0x1fffffff & (hash + cu);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.42, 0.18).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final suggestion = matched;
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        onKeyEvent(event);
        return event is KeyDownEvent &&
                (_isArrow(event.logicalKey) ||
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                    event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.gameButtonA ||
                    event.logicalKey == LogicalKeyboardKey.space)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          final bg = suggestion?.background ?? _fallbackBg;
          return AvenFocusZoom(
            focused: focused,
            scale: 1.12,
            child: SizedBox(
            width: 220,
            height: 128,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: focused ? AvenColors.focus : Colors.transparent,
                      width: focused ? 3 : 0,
                    ),
                    boxShadow: focused
                        ? [
                            BoxShadow(
                              color: AvenColors.focus.withValues(alpha: 0.45),
                              blurRadius: 22,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(focused ? 11 : 14),
                    child: suggestion != null
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              ColoredBox(color: suggestion.background),
                              Image.asset(
                                suggestion.image,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.high,
                              ),
                            ],
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              ColoredBox(color: bg),
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
                                  child: Image.network(
                                    _favicon,
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stack) {
                                      return const Icon(
                                        Icons.public,
                                        size: 40,
                                        color: Colors.white70,
                                      );
                                    },
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                  child: Text(
                                    link.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
          );
        },
      ),
    );
  }
}

class _StartAction extends StatelessWidget {
  const _StartAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.focusNode,
    required this.onKeyEvent,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final FocusNode focusNode;
  final ValueChanged<KeyEvent> onKeyEvent;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        onKeyEvent(event);
        return event is KeyDownEvent &&
                (_isArrow(event.logicalKey) ||
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                    event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.gameButtonA ||
                    event.logicalKey == LogicalKeyboardKey.space)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          return AvenFocusZoom(
            focused: focused,
            child: ExcludeFocus(
            child: TextButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
              style: TextButton.styleFrom(
                foregroundColor: AvenColors.text,
                backgroundColor: focused ? AvenColors.hover : AvenColors.accentBlue,
                overlayColor: AvenColors.hover,
                side: focused
                    ? const BorderSide(color: AvenColors.hover, width: 2)
                    : BorderSide.none,
                minimumSize: const Size(150, 52),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          );
        },
      ),
    );
  }
}

class _FloatingMenu extends StatelessWidget {
  const _FloatingMenu({
    required this.open,
    required this.address,
    required this.addressFocus,
    required this.menuFocus,
    required this.editing,
    required this.canBack,
    required this.canForward,
    required this.saved,
    required this.adBlockOn,
    required this.zoom,
    required this.onTapField,
    required this.onSubmit,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onHome,
    required this.onBookmark,
    required this.onLibrary,
    required this.onToggleAdBlock,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onZoomReset,
    required this.onSettings,
  });

  final bool open;
  final TextEditingController address;
  final FocusNode addressFocus;
  final FocusNode menuFocus;
  final bool editing;
  final bool canBack;
  final bool canForward;
  final bool saved;
  final bool adBlockOn;
  final int zoom;
  final VoidCallback onTapField;
  final ValueChanged<String> onSubmit;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final VoidCallback onHome;
  final VoidCallback onBookmark;
  final VoidCallback onLibrary;
  final VoidCallback onToggleAdBlock;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomReset;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return AnimatedAlign(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: editing ? Alignment.topCenter : Alignment.bottomCenter,
      child: IgnorePointer(
        ignoring: !open,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          offset: open ? Offset.zero : Offset(0, editing ? -1.4 : 1.4),
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            padding: editing
                ? const EdgeInsets.fromLTRB(28, 28, 28, 0)
                : const EdgeInsets.fromLTRB(28, 0, 28, 22),
            child: Material(
              elevation: 16,
              color: AvenColors.accentBlue.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.none,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 28, 12, 6),
                child: FocusTraversalGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 460,
                        child: _AddressField(
                          controller: address,
                          focusNode: addressFocus,
                          editing: editing,
                          compact: true,
                          nextFocus: menuFocus,
                          onTap: onTapField,
                          onSubmit: onSubmit,
                        ),
                      ),
                      _MenuBar(
                        firstFocus: menuFocus,
                        addressFocus: addressFocus,
                        canBack: canBack,
                        canForward: canForward,
                        saved: saved,
                        adBlockOn: adBlockOn,
                        zoom: zoom,
                        onBack: onBack,
                        onForward: onForward,
                        onReload: onReload,
                        onHome: onHome,
                        onBookmark: onBookmark,
                        onLibrary: onLibrary,
                        onToggleAdBlock: onToggleAdBlock,
                        onZoomOut: onZoomOut,
                        onZoomIn: onZoomIn,
                        onZoomReset: onZoomReset,
                        onSettings: onSettings,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddressField extends StatelessWidget {
  const _AddressField({
    required this.controller,
    required this.focusNode,
    required this.editing,
    required this.onTap,
    required this.onSubmit,
    this.autofocus = false,
    this.compact = false,
    this.nextFocus,
    this.onArrow,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool editing;
  final VoidCallback onTap;
  final ValueChanged<String> onSubmit;
  final bool autofocus;
  final bool compact;
  final FocusNode? nextFocus;
  final ValueChanged<LogicalKeyboardKey>? onArrow;

  void _beginEditing() {
    onTap();
    // The field stays read-only until this frame finishes. Asking for the
    // keyboard before that attaches a dummy connection and Android cancels it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        focusNode.requestFocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
        WebInput().showKeyboard();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    focusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (!editing && onArrow != null && _isArrow(key)) {
        onArrow!(key);
        return KeyEventResult.handled;
      }
      if (!editing && key == LogicalKeyboardKey.arrowDown && nextFocus != null) {
        nextFocus!.requestFocus();
        return KeyEventResult.handled;
      }
      if (!editing && nextFocus != null && _isArrow(key)) {
        return KeyEventResult.handled;
      }
      if (!editing && _isArrow(key)) {
        final direction = switch (key) {
          LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
          LogicalKeyboardKey.arrowRight => TraversalDirection.right,
          LogicalKeyboardKey.arrowUp => TraversalDirection.up,
          _ => TraversalDirection.down,
        };
        Focus.of(context).focusInDirection(direction);
        return KeyEventResult.handled;
      }
      if (!editing && (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.gameButtonA)) {
        _beginEditing();
        return KeyEventResult.handled;
      }
      if (!editing &&
          (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter)) {
        if (controller.text.trim().isEmpty) {
          _beginEditing();
        } else {
          onSubmit(controller.text);
        }
        return KeyEventResult.handled;
      }
      if (editing) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.backspace && controller.text.isNotEmpty) {
        controller.text = controller.text.substring(0, controller.text.length - 1);
        controller.selection = TextSelection.collapsed(offset: controller.text.length);
        return KeyEventResult.handled;
      }
      final typed = event.character;
      if (typed != null && _isTypingCharacter(typed)) {
        controller.text = '${controller.text}$typed';
        controller.selection = TextSelection.collapsed(offset: controller.text.length);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return AvenFocusZoom(
          focused: focused,
          scale: 1.04,
          child: TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      readOnly: !editing,
      showCursor: editing,
      enableInteractiveSelection: editing,
      style: TextStyle(fontSize: compact ? 16 : 20),
      textInputAction: TextInputAction.go,
      onTap: _beginEditing,
      onSubmitted: onSubmit,
      decoration: InputDecoration(
        hintText: 'Site veya arama',
        filled: true,
        fillColor: AvenColors.text.withValues(alpha: 0.08),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: compact ? 8 : 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(
            color: AvenColors.text.withValues(alpha: 0.18),
            width: 1.5,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(
            color: AvenColors.text.withValues(alpha: 0.18),
            width: 1.5,
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: AvenColors.hover, width: 3),
        ),
      ),
    ),
        );
      },
    );
  }
}

class _MenuBar extends StatefulWidget {
  const _MenuBar({
    required this.firstFocus,
    required this.addressFocus,
    required this.canBack,
    required this.canForward,
    required this.saved,
    required this.adBlockOn,
    required this.zoom,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onHome,
    required this.onBookmark,
    required this.onLibrary,
    required this.onToggleAdBlock,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onZoomReset,
    required this.onSettings,
  });

  final FocusNode firstFocus;
  final FocusNode addressFocus;
  final bool canBack;
  final bool canForward;
  final bool saved;
  final bool adBlockOn;
  final int zoom;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final VoidCallback onHome;
  final VoidCallback onBookmark;
  final VoidCallback onLibrary;
  final VoidCallback onToggleAdBlock;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomReset;
  final VoidCallback onSettings;

  @override
  State<_MenuBar> createState() => _MenuBarState();
}

class _MenuBarState extends State<_MenuBar> {
  late final List<FocusNode> _nodes = [
    widget.firstFocus,
    ...List.generate(10, (_) => FocusNode()),
  ];

  @override
  void dispose() {
    for (final node in _nodes.skip(1)) {
      node.dispose();
    }
    super.dispose();
  }

  void _move(int index, LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowRight && index < _nodes.length - 1) {
      _nodes[index + 1].requestFocus();
    } else if (key == LogicalKeyboardKey.arrowLeft && index > 0) {
      _nodes[index - 1].requestFocus();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      widget.addressFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = <(IconData?, String, bool, VoidCallback?, String?)>[
      (Icons.arrow_back, 'Geri', widget.canBack, widget.onBack, null),
      (Icons.arrow_forward, 'İleri', widget.canForward, widget.onForward, null),
      (Icons.refresh, 'Yenile', true, widget.onReload, null),
      (Icons.home, 'Başlangıç', true, widget.onHome, null),
      (widget.saved ? Icons.star : Icons.star_border, 'Yer imi', true, widget.onBookmark, null),
      (Icons.history, 'Kitaplık', true, widget.onLibrary, null),
      (
        widget.adBlockOn ? Icons.shield : Icons.shield_outlined,
        widget.adBlockOn ? 'Engelleme açık' : 'Engelleme kapalı',
        true,
        widget.onToggleAdBlock,
        null,
      ),
      (Icons.remove, 'Uzaklaştır', true, widget.onZoomOut, null),
      (null, 'Yakınlaştırma', true, widget.onZoomReset, '%${widget.zoom}'),
      (Icons.add, 'Yakınlaştır', true, widget.onZoomIn, null),
      (Icons.settings, 'Ayarlar', true, widget.onSettings, null),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < items.length; index++)
                _BarButton(
                  focusNode: _nodes[index],
                  icon: items[index].$1,
                  label: items[index].$5,
                  tooltip: items[index].$2,
                  enabled: items[index].$3,
                  onPressed: items[index].$4 ?? () {},
                  onArrow: (key) => _move(index, key),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.tooltip,
    required this.onPressed,
    required this.focusNode,
    this.icon,
    this.label,
    this.enabled = true,
    this.onArrow,
  });

  final IconData? icon;
  final String? label;
  final String tooltip;
  final VoidCallback onPressed;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<LogicalKeyboardKey>? onArrow;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (onArrow != null && _isArrow(key)) {
      onArrow!(key);
      return KeyEventResult.handled;
    }
    final activate = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space;
    if (activate) {
      if (enabled) onPressed();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final node = focusNode;
    return ListenableBuilder(
      listenable: node,
      builder: (context, _) {
        final focused = node.hasFocus;
        return AvenFocusZoom(
          focused: focused,
          scale: 1.12,
          child: SizedBox(
          width: label != null ? 58 : 48,
          height: 72,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              if (focused)
                Positioned(
                  bottom: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AvenColors.background.withValues(alpha: 0.93),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AvenColors.hover),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: Text(
                        tooltip,
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ),
              Focus(
                focusNode: node,
                onKeyEvent: _onKey,
                child: ExcludeFocus(
                  child: label != null
                      ? TextButton(
                          onPressed: enabled ? onPressed : () {},
                          style: TextButton.styleFrom(
                            minimumSize: const Size(58, 48),
                            padding: EdgeInsets.zero,
                            backgroundColor: focused ? AvenColors.hover : null,
                            foregroundColor: AvenColors.text,
                            side: focused
                                ? const BorderSide(color: AvenColors.hover, width: 2)
                                : BorderSide.none,
                          ),
                          child: Text(
                            label!,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        )
                      : IconButton(
                          onPressed: enabled ? onPressed : () {},
                          icon: Icon(icon),
                          iconSize: 24,
                          padding: EdgeInsets.zero,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            backgroundColor: focused ? AvenColors.hover : null,
                            foregroundColor: !enabled
                                ? AvenColors.textMuted
                                : AvenColors.text,
                            side: focused
                                ? const BorderSide(color: AvenColors.hover, width: 2)
                                : BorderSide.none,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        );
      },
    );
  }
}

class _WebViewWarning extends StatelessWidget {
  const _WebViewWarning();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AvenColors.hover.withValues(alpha: 0.25),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'Bu kutunun WebView sürümü eski. Android System WebView güncellenirse siteler daha düzgün açılır.',
        ),
      ),
    );
  }
}

