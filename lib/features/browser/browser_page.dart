import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/platform/aven_flavor.dart';
import '../../core/theme/aven_theme.dart';
import '../../core/theme/aven_dialog.dart';
import '../../core/url/url_input.dart';
import '../../core/url/search_suggest.dart';
import '../../data/settings_store.dart';
import '../../platform/web_input.dart';
import '../library/library_page.dart';
import '../player/video_catalog.dart';
import '../player/video_player_page.dart';
import '../settings/settings_page.dart';
import 'gecko_engine.dart';
import 'media_site.dart';
import 'page_engine.dart';
import 'reader_mode.dart';
import 'web_scripts.dart';
import 'web_view_engine.dart';

part 'widgets/browser_page_widgets.dart';
part 'web_navigation.dart';
part 'cursor_input.dart';

class _PageTab {
  String? url;
  String title = 'Yeni sekme';
  bool incognito = false;
}

const _pageHooks = '''
if (!window.__aven) {
  window.__aven = true;
  function avenAsk(url) {
    try { url = new URL(url, document.baseURI).href; } catch (e) { url = String(url || ''); }
    if (!url || !window.AvenPopup) return;
    if (/^(javascript|about|data|blob):/i.test(url)) return;
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
  late final PageEngine _controller;

  Size _webSize = Size.zero;
  bool _placed = false;
  bool _onStart = true;
  bool _menuOpen = false;
  final List<_PageTab> _tabs = [_PageTab()];
  int _tabIndex = 0;
  bool _phoneTabsOpen = false;
  DateTime _lastBack = DateTime.fromMillisecondsSinceEpoch(0);
  bool _exitDialogOpen = false;
  bool _openingVideo = false;
  bool _webSuspended = false;
  bool _pageTyping = false;
  bool _popupOpen = false;
  bool _externalOpen = false;
  bool _addressEditing = false;
  bool _startEditing = false;
  bool _canBack = false;
  bool _canForward = false;
  bool _warnWebView = false;
  bool _lite = false;
  bool _homeSuggestions = true;
  bool _desktopSite = false;
  String _connection = 'unknown';
  bool _findOpen = false;
  bool _voiceBusy = false;
  final _findText = TextEditingController();
  List<SearchSuggestion> _omniboxSuggestions = const [];
  List<Map<String, String>> _liveDownloads = const [];
  String? _toastHoldId;
  Timer? _toastHold;
  Timer? _suggestDebounce;
  bool _saved = false;
  String? _pageUrl;
  String? _pageTitle;
  String? _castMediaUrl;
  SearchEngine _engine = SearchEngine.google;
  List<WebLink> _bookmarks = const [];
  List<WebLink> _history = const [];
  AdBlock _adBlock = AdBlock.off;
  AdBlock _adBlockProvider = AdBlock.local;
  bool _readerOn = false;
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
      } else if (call.method == 'cast' && call.arguments is Map) {
        final raw = Map<Object?, Object?>.from(call.arguments as Map);
        final url = '${raw['url'] ?? ''}';
        unawaited(_openCast(url, raw['play'] == true));
      }
    });
    _ticker = createTicker(_onTick);
    _surfaceFocus.canRequestFocus = false;
    void onProgress(int value) {
      _progress.value = value;
      if (value >= 100) {
        _pageLoading.value = false;
        _loadTimeout?.cancel();
        _wakeSurface();
      }
    }
    if (AvenFlavor.isMobile) {
      _controller = GeckoPageEngine(
        onPageStarted: _onPageStarted,
        onPageFinished: (url) => unawaited(_onPageFinished(url)),
        onProgress: onProgress,
        onError: _onError,
        onExternal: (url) => unawaited(_confirmOpenExternal(url)),
        onNewTab: (url) => unawaited(_openSpawnedLink(url)),
        onSecurity: _onSecurity,
        onPermissionPrompt: _confirmPermission,
        onContextMenu: _showContextMenu,
        onDownloads: _onDownloadList,
      );
    } else {
      _controller = WebViewPageEngine(
        onPageStarted: _onPageStarted,
        onPageFinished: (url) => unawaited(_onPageFinished(url)),
        onProgress: onProgress,
        onNavigationRequest: _onNavigationRequest,
        onError: _onError,
        onHttpError: _onHttpError,
      );
    }
    _address.addListener(_onAddressEdited);
    _boot();
  }

  void _onDownloadList(List<Map<String, String>> items) {
    final active = items.where((item) {
      final status = item['status'];
      return status == 'İniyor' || status == 'Bekliyor' || status == 'Durdu';
    });
    if (active.isNotEmpty) {
      _toastHoldId = active.first['id'];
    }
    if (!mounted) return;
    setState(() => _liveDownloads = items);
  }

  Map<String, String>? get _toastDownload {
    for (final item in _liveDownloads) {
      final status = item['status'];
      if (status == 'İniyor' || status == 'Bekliyor' || status == 'Durdu') {
        return item;
      }
    }
    if (_toastHoldId == null) return null;
    for (final item in _liveDownloads) {
      if (item['id'] == _toastHoldId) return item;
    }
    return null;
  }

  void _onAddressEdited() {
    if (!AvenFlavor.isMobile) return;
    _suggestDebounce?.cancel();
    _suggestDebounce = Timer(const Duration(milliseconds: 160), () {
      unawaited(_loadOmniboxSuggestions());
    });
  }

  Future<void> _loadOmniboxSuggestions() async {
    final focused = _onStart ? _startFocus.hasFocus : _addressFocus.hasFocus;
    final query = _address.text.trim();
    final page = (_pageUrl ?? '').trim();
    if (!focused || (!_onStart && query == page)) {
      if (mounted && _omniboxSuggestions.isNotEmpty) {
        setState(() => _omniboxSuggestions = const []);
      }
      return;
    }
    if (query.length < 2) {
      final recent = [
        for (final item in _history.take(6))
          SearchSuggestion(
            label: item.title.trim().isEmpty ? item.url : item.title.trim(),
            query: item.url,
            isUrl: true,
            source: SuggestionSource.history,
          ),
      ];
      if (mounted) setState(() => _omniboxSuggestions = recent);
      return;
    }
    final next = await buildAddressSuggestions(
      query,
      engine: _engine,
      history: [
        for (final item in _history) (title: item.title, url: item.url),
      ],
      bookmarks: [
        for (final item in _bookmarks) (title: item.title, url: item.url),
      ],
    );
    if (!mounted) return;
    setState(() => _omniboxSuggestions = next);
  }

  Future<void> _boot() async {
    await _configureAndroid();
    final engine = await _store.loadEngine();
    final bookmarks = await _store.loadBookmarks();
    final history = await _store.loadHistory();
    final block = await _store.loadAdBlock();
    final provider = await _store.loadAdBlockProvider();
    final agent = await _store.loadAgent();
    final lite = await _store.loadLiteBrowsing(fallback: !AvenFlavor.isMobile);
    final homeSuggestions = await _store.loadHomeSuggestions();
    final version = await _input.webViewVersion();
    await _input.setAdBlock(block.name);
    await _applyAgent(agent);
    await _applyLite(lite);
    if (!mounted) return;
    final major = webViewMajor(version);
    setState(() {
      _engine = engine;
      _bookmarks = bookmarks;
      _history = history;
      _adBlock = block;
      _adBlockProvider = provider;
      _lite = lite;
      _homeSuggestions = homeSuggestions;
      _desktopSite = agent == BrowserAgent.desktop;
      _warnWebView = !AvenFlavor.isMobile && major != null && major < 80;
    });
    // Start screen never mounts WebView; keep native side paused anyway.
    if (_onStart) {
      unawaited(_suspendWebPage());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _onStart && !AvenFlavor.isMobile) {
          _startFocus.requestFocus();
        }
      });
    }
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
    await _controller.setMediaPlaybackRequiresUserGesture(enabled);
    // Keep images on - lite mode trims motion/media instead.
    await _input.setLoadsImages(true);
  }

  Future<void> _setZoom(int zoom) async {
    final next = zoom.clamp(50, 300);
    await _controller.setTextZoom(next);
    if (!mounted) return;
    setState(() => _zoom = next);
  }

  Future<void> _configureAndroid() async {
    await _controller.configure(
      lite: _lite,
      onShowFullscreen: (widget, onHide) {
        if (!mounted) {
          onHide();
          return;
        }
        if (_menuOpen) {
          setState(() {
            _menuOpen = false;
            _addressEditing = false;
          });
        }
        setState(() {
          _fullscreenVideo = widget;
          _exitFullscreen = onHide;
          _onStart = false;
        });
        _syncChrome();
        _cursorVisible.value = true;
        _bumpCursor();
        unawaited(_input.setChromeOpen(false));
        unawaited(_input.prepareForInput());
      },
      onHideFullscreen: () {
        if (!mounted) return;
        setState(() {
          _fullscreenVideo = null;
          _exitFullscreen = null;
        });
        _syncChrome();
        _cursorVisible.value = true;
        _cursorHide?.cancel();
      },
    );
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
  }

  Future<void> _onWatchedMedia(String url) async {
    if (!mounted || !isAvenWebUrl(url) || isAdMediaUrl(url)) return;
    // Feed the media pool / focused badge only - do not auto-open Aven player.
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
      _readerOn = false;
    });
    _syncChrome();
    _addressFocus.unfocus();
    _startFocus.unfocus();
    _surfaceFocus.canRequestFocus = true;
    // Always force-resume: a stale pauseTimers() leaves the page black forever.
    _webSuspended = false;
    try {
      await _input.resumeWebView();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 32));
    try {
      await _controller.loadRequest(Uri.parse(target));
    } catch (_) {}
    _surfaceFocus.requestFocus();
    unawaited(_wakeSurface());
  }

  void _showStart() {
    setState(() {
      _onStart = true;
      _phoneTabsOpen = false;
      _omniboxSuggestions = const [];
      _menuOpen = false;
      _addressEditing = false;
      _startEditing = false;
      _pageError = null;
      _pageUrl = null;
      _connection = 'unknown';
      _pageTitle = null;
      _canBack = false;
      _canForward = false;
      _saved = false;
      _readerOn = false;
      _fullscreenVideo = null;
      if (AvenFlavor.isMobile && _tabIndex < _tabs.length) {
        _tabs[_tabIndex].url = null;
        _tabs[_tabIndex].title = 'Yeni sekme';
      }
      _exitFullscreen = null;
      _address.text = '';
    });
    _addressFocus.unfocus();
    _surfaceFocus.canRequestFocus = false;
    _surfaceFocus.unfocus();
    _syncChrome();
    unawaited(_resetWebViewForHome());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _onStart && !AvenFlavor.isMobile) {
          _startFocus.requestFocus();
        }
      });
    });
  }

  /// Drop the previous document so Back from home cannot return to it.
  Future<void> _resetWebViewForHome() async {
    await _suspendWebPage();
    try {
      await _controller.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
    // Avoid clearCache/clearLocalStorage here — they race pauseTimers and can
    // leave the next navigation on a black, non-loading surface.
  }

  Future<void> _confirmExit() async {
    if (_exitDialogOpen) return;
    _exitDialogOpen = true;
    try {
      // Let the Back/Escape key that opened this fully finish, otherwise the
      // new dialog route receives the same press and pops immediately.
      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (!mounted) return;
      final openedAt = DateTime.now();
      final leave = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: AvenColors.barrier,
        builder: (context) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              // Ignore the residual Back that still rides in after showDialog.
              if (DateTime.now().difference(openedAt) <
                  const Duration(milliseconds: 300)) {
                return;
              }
              Navigator.of(context).pop(false);
            },
            child: AvenConfirmDialog(
              icon: Icons.power_settings_new_rounded,
              title: 'Uygulamadan çık',
              message: 'Aven Browser kapatılsın mı? Açık sayfa sıfırlanır.',
              cancelLabel: 'İptal',
              confirmLabel: 'Çık',
              autofocusConfirm: false,
            ),
          );
        },
      );
      if (leave == true && mounted) {
        await SystemNavigator.pop();
      }
    } finally {
      _exitDialogOpen = false;
    }
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

  Widget _tvPanel(BuildContext context, Widget child) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width - 72;
    final height = size.height - 56;
    return Dialog(
      backgroundColor: AvenColors.panel,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          width: width > 1040 ? 1040 : width,
          height: height > 640 ? 640 : height,
          child: child,
        ),
      ),
    );
  }

  Future<void> _openLibrary({int section = 0}) async {
    if (AvenFlavor.isMobile) {
      final picked = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => LibraryPage(store: _store, initialSection: section),
        ),
      );
      _bookmarks = await _store.loadBookmarks();
      _history = await _store.loadHistory();
      if (!mounted) return;
      setState(() => _saved = _bookmarks.any((item) => item.url == _pageUrl));
      if (picked != null) await _openInput(picked);
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      barrierColor: AvenColors.barrier,
      builder: (context) => _tvPanel(
        context,
        LibraryPage(store: _store, initialSection: section),
      ),
    );
    _bookmarks = await _store.loadBookmarks();
    _history = await _store.loadHistory();
    if (!mounted) return;
    setState(() => _saved = _bookmarks.any((item) => item.url == _pageUrl));
    if (picked != null) {
      await _openInput(picked);
      return;
    }
    if (_onStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _onStart && !AvenFlavor.isMobile) {
          _startFocus.requestFocus();
        }
      });
    } else if (_menuOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _menuOpen) _menuFocus.requestFocus();
      });
    }
  }

  Future<void> _openSettings() async {
    if (AvenFlavor.isMobile) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => SettingsPage(store: _store, input: _input),
        ),
      );
    } else {
    await showDialog<void>(
      context: context,
      barrierColor: AvenColors.barrier,
      builder: (context) => _tvPanel(
        context,
        SettingsPage(store: _store, input: _input),
      ),
    );
    }
    final engine = await _store.loadEngine();
    final block = await _store.loadAdBlock();
    final provider = await _store.loadAdBlockProvider();
    final agent = await _store.loadAgent();
    final lite = await _store.loadLiteBrowsing(fallback: !AvenFlavor.isMobile);
    final homeSuggestions = await _store.loadHomeSuggestions();
    await _input.setAdBlock(block.name);
    await _applyAgent(agent);
    await _applyLite(lite);
    if (!mounted) return;
    setState(() {
      _engine = engine;
      _adBlock = block;
      _adBlockProvider = provider;
      _lite = lite;
      _homeSuggestions = homeSuggestions;
    });
    if (!_onStart && isAvenWebUrl(_pageUrl)) {
      await _controller.reload();
    }
    if (_onStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _onStart && !AvenFlavor.isMobile) {
          _startFocus.requestFocus();
        }
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
    await _input.setAdBlock(next.name, connectDns: next.usesDns);
    if (next.isEnabled) await _installAdblockCss();
    if (!mounted) return;
    setState(() => _adBlock = next);
  }

  Future<void> _toggleReader() async {
    if (_onStart || _pageError != null) return;
    try {
      final raw = await _controller.runJavaScriptReturningResult(readerToggleScript);
      final text = raw.toString().replaceAll('"', '').trim().toLowerCase();
      if (!mounted) return;
      setState(() => _readerOn = text == 'on');
    } catch (_) {}
  }

  @override
  void _syncChrome() {
    if (_fullscreenVideo != null) {
      // Fullscreen surface owns input; Flutter chrome must not intercept.
      _input.setChromeOpen(false);
      _input.prepareForInput();
      return;
    }
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _menuOpen) _menuFocus.requestFocus();
      });
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

  String? _spawnedUrl;
  DateTime? _spawnedAt;

  Future<void> _openSpawnedLink(String url) async {
    final target = url.trim();
    if (!mounted || !isAvenWebUrl(target) || target == _pageUrl) return;
    final now = DateTime.now();
    if (_spawnedUrl == target &&
        _spawnedAt != null &&
        now.difference(_spawnedAt!) < const Duration(milliseconds: 800)) {
      return;
    }
    _spawnedUrl = target;
    _spawnedAt = now;
    final incognito = _tabIndex < _tabs.length && _tabs[_tabIndex].incognito;
    await _openInNewTab(target, incognito: incognito);
  }

  Future<void> _onPopupMessage(JavaScriptMessage message) async {
    final url = message.message.trim();
    if (!mounted || _popupOpen || _externalOpen || url == _pageUrl) return;
    if (isExternalAppUrl(url)) {
      await _confirmOpenExternal(url);
      return;
    }
    if (!isAvenWebUrl(url)) return;
    if (AvenFlavor.isMobile) {
      await _openSpawnedLink(url);
      return;
    }
    _popupOpen = true;
    final open = await showDialog<bool>(
      context: context,
      barrierColor: AvenColors.barrier,
      builder: (context) {
        return AvenConfirmDialog(
          icon: Icons.open_in_new_rounded,
          title: 'Pencere açılsın mı?',
          message: url,
          cancelLabel: 'İptal',
          confirmLabel: 'Aç',
          autofocusConfirm: true,
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
    _openingVideo = true;
    _resetPointerState();
    setState(() {});
    final epoch = _mediaEpoch;
    try {
      // Frame referer + pool in parallel — don't serialize two JS round-trips.
      final frameFuture = _readPlayerFrame();
      final poolFuture = _readMediaPool();
      final frameReferer = await frameFuture;
      final pooledFirst = await poolFuture;

      VideoSource mapSource(String url, String label, double? duration) {
        return VideoSource(
          url: url,
          label: label,
          headers: _mediaHeadersFor(url, frameReferer: frameReferer),
          durationSeconds: duration,
        );
      }

      var sources = _preferPlayable([
        for (final source in parsed.sources)
          if (_isStreamUrl(source.url) && !isAdMediaUrl(source.url))
            mapSource(source.url, source.label, source.durationSeconds),
        for (final item in pooledFirst)
          if (_isStreamUrl(item.url) && !isAdMediaUrl(item.url))
            mapSource(item.url, item.label, item.duration),
      ]);
      sources = _preferPlayable(_dedupeSources(sources));

      // Poll only when needed, and keep it short (was up to ~5.6s before).
      if (sources.isEmpty) {
        for (var i = 0; i < 6 && mounted; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 180));
          if (epoch != _mediaEpoch) return;
          final pooled = await _readMediaPool();
          if (pooled.isEmpty) continue;
          sources = _preferPlayable(
            _dedupeSources([
              ...sources,
              for (final item in pooled)
                if (_isStreamUrl(item.url) && !isAdMediaUrl(item.url))
                  mapSource(item.url, item.label, item.duration),
            ]),
          );
          if (sources.isNotEmpty) break;
        }
      } else if (!_hasContentStream(sources)) {
        // Already playable — give HLS a brief chance, then open anyway.
        for (var i = 0; i < 2 && mounted; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          if (epoch != _mediaEpoch) return;
          final pooled = await _readMediaPool();
          if (pooled.isEmpty) continue;
          sources = _preferPlayable(
            _dedupeSources([
              ...sources,
              for (final item in pooled)
                if (_isStreamUrl(item.url) && !isAdMediaUrl(item.url))
                  mapSource(item.url, item.label, item.duration),
            ]),
          );
          if (_hasContentStream(sources)) break;
        }
      }
      if (epoch != _mediaEpoch || sources.isEmpty || !mounted) return;
      final video = PageVideo(sources: sources, tracks: parsed.tracks);
      var initial = video.sources.first;
      for (final source in video.sources) {
        final u = source.url.toLowerCase();
        if (u.contains('.m3u8')) {
          initial = source;
          if (u.contains('live-video.net') ||
              u.contains('master') ||
              u.contains('/hls/') ||
              u.contains('.m3u8')) {
            break;
          }
        }
      }
      // Prefer longest known duration over short preroll leftovers.
      for (final source in video.sources) {
        final d = source.durationSeconds ?? 0;
        final best = initial.durationSeconds ?? 0;
        if (d > 180 && d > best) initial = source;
      }
      _castMediaUrl = initial.url;
      // Freeze the page in the background while the player route opens.
      unawaited(_suspendWebPage());
      if (!mounted) {
        await _resumeWebPage();
        return;
      }
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (context) =>
              VideoPlayerPage(video: video, initialSource: initial),
        ),
      );
    } finally {
      _openingVideo = false;
      if (mounted) setState(() {});
    }
    if (_onStart) {
      // Home stays on top - keep the page frozen underneath.
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

  bool _hasContentStream(List<VideoSource> sources) {
    if (_hasHls(sources)) return true;
    return sources.any((s) {
      final u = s.url.toLowerCase();
      return u.contains('/embed') ||
          u.contains('/player') ||
          u.contains('/stream') ||
          u.contains('videodelivery') ||
          u.contains('b-cdn.net') ||
          u.contains('jwpcdn') ||
          ((s.durationSeconds ?? 0) > 180);
    });
  }

  Future<String?> _readPlayerFrame() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult(r'''
(function(){
  try {
    if (window.__avenPlayerFrame) return String(window.__avenPlayerFrame);
    var iframes = document.querySelectorAll('iframe[src],iframe[data-src]');
    var best = '', area = 0;
    for (var i = 0; i < iframes.length; i++) {
      var f = iframes[i];
      var src = f.getAttribute('src') || f.getAttribute('data-src') || '';
      if (!src || src.indexOf('http') !== 0) continue;
      var low = src.toLowerCase();
      var w = f.offsetWidth || 0, h = f.offsetHeight || 0;
      // Skip IAB ad slots.
      if ((w === 728 && h === 90) || (w === 300 && h === 250) || (w === 160 && h === 600) ||
          (w === 336 && h === 280) || (w === 320 && (h === 50 || h === 100))) continue;
      if (/doubleclick|googlesyndication|pagead|popads|exoclick/.test(low)) continue;
      var looks = /embed|player|video|watch|stream|live|channel|youtube|vimeo|hls|iframe\.php|media/.test(low);
      var a = w * h;
      if (!looks && a < 40000) continue;
      if (a > area && w > 120 && h > 70) { area = a; best = src; }
    }
    // Fallback: largest non-ad iframe on the page.
    if (!best) {
      for (var j = 0; j < iframes.length; j++) {
        var f2 = iframes[j];
        var src2 = f2.getAttribute('src') || f2.getAttribute('data-src') || '';
        if (!src2 || src2.indexOf('http') !== 0) continue;
        var r = f2.getBoundingClientRect();
        var a2 = r.width * r.height;
        if (a2 > area && r.width > 200 && r.height > 120) { area = a2; best = src2; }
      }
    }
    return best || '';
  } catch (e) { return ''; }
})();
''');
      final text = raw is String
          ? raw.replaceAll(r'\"', '"').replaceAll(RegExp(r'^"|"$'), '')
          : raw.toString();
      if (text.isEmpty || text == 'null') return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  List<VideoSource> _dedupeSources(List<VideoSource> sources) {
    final seen = <String>{};
    final out = <VideoSource>[];
    for (final source in sources) {
      if (seen.add(source.url)) out.add(source);
    }
    return out;
  }

  Future<List<({String url, String label, double? duration})>> _readMediaPool() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult(r'''
(function(){
  try {
    return JSON.stringify((window.__avenPool || []).map(function(item){
      return {url: item.url || '', label: item.label || 'Net', duration: item.duration || 0};
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
            (
              url: item['url'] as String,
              label: (item['label'] as String?) ?? 'Net',
              duration: switch (item['duration']) {
                num n => n.toDouble(),
                String s => double.tryParse(s),
                _ => null,
              },
            ),
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
    // Only hand ExoPlayer real playlists / progressive files - Kick's bare
    // `/stream/` API hits and similar junk cause progressive 404s.
    if (lower.contains('.m3u8') || lower.contains('mpegurl')) return true;
    if (lower.contains('.mpd')) return true;
    if (RegExp(r'\.(mp4|webm|mkv|mov|m4v)([?#]|$)').hasMatch(lower)) return true;
    if (lower.contains('live-video.net') &&
        (lower.contains('/hls') ||
            lower.contains('playlist') ||
            lower.contains('master') ||
            lower.contains('.m3u8'))) {
      return true;
    }
    if (lower.contains('googlevideo.com') && lower.contains('mime=video')) return true;
    if (lower.contains('/hls/') && !lower.contains('/stream/')) return true;
    if (lower.contains('videodelivery.net') || lower.contains('cloudflarestream.com')) {
      return true;
    }
    if (lower.contains('vz-') && lower.contains('.b-cdn.net')) return true;
    if ((lower.contains('okcdn') || lower.contains('vkvd') || lower.contains('mycdn.me')) &&
        (lower.contains('video') || lower.contains('.mp4') || lower.contains('hls'))) {
      return true;
    }
    return false;
  }

  List<VideoSource> _preferPlayable(List<VideoSource> sources) {
    final ranked = [...sources];
    ranked.sort((a, b) {
      int score(VideoSource s) {
        final dur = s.durationSeconds ?? 0;
        // Short clips are almost always preroll leftovers.
        final durPenalty = (dur > 0 && dur < 90) ? 40 : (dur > 180 ? -10 : 0);
        return contentHostScore(s.url) + durPenalty;
      }
      return score(a).compareTo(score(b));
    });
    return ranked;
  }

  Map<String, String> _mediaHeadersFor(String mediaUrl, {String? frameReferer}) {
    const fallbackUa =
        'Mozilla/5.0 (Linux; Android 12; SHIELD Android TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    final ua = (_userAgent != null && _userAgent!.trim().isNotEmpty) ? _userAgent! : fallbackUa;
    final pageUrl = _pageUrl;
    final page = pageUrl == null ? null : Uri.tryParse(pageUrl);
    final media = Uri.tryParse(mediaUrl);
    final frame = frameReferer == null || frameReferer.isEmpty ? null : Uri.tryParse(frameReferer);
    final mediaHost = media?.host.toLowerCase() ?? '';
    final pageHost = page?.host.toLowerCase() ?? '';
    // Embed CDNs usually require the player iframe origin as Referer.
    String referer;
    if (frame != null &&
        frame.host.isNotEmpty &&
        mediaHost.isNotEmpty &&
        mediaHost != pageHost) {
      referer = '${frame.scheme}://${frame.host}/';
    } else if (pageUrl != null && pageUrl.isNotEmpty) {
      referer = pageUrl;
    } else if (media != null) {
      referer = '${media.scheme}://${media.host}/';
    } else {
      referer = '';
    }
    final originHost = frame?.host.isNotEmpty == true && mediaHost != pageHost
        ? frame!.host
        : page?.host;
    final originScheme = frame?.host.isNotEmpty == true && mediaHost != pageHost
        ? frame!.scheme
        : page?.scheme;
    return {
      'User-Agent': ua,
      if (referer.isNotEmpty) 'Referer': referer,
      if (originHost != null && originHost.isNotEmpty)
        'Origin': '${originScheme ?? 'https'}://$originHost',
      'Accept': '*/*',
      'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
    };
  }

  Future<void> _toggleDesktopSite() async {
    final next = _desktopSite ? BrowserAgent.defaultAgent : BrowserAgent.desktop;
    await _store.saveAgent(next);
    await _applyAgent(next);
    if (!mounted) return;
    setState(() => _desktopSite = next == BrowserAgent.desktop);
    if (!_onStart) {
      setState(() {
        _pageError = null;
        _readerOn = false;
      });
      await _controller.reload();
    }
  }

  void _closeAllTabs() {
    setState(() {
      _tabs
        ..clear()
        ..add(_PageTab());
      _tabIndex = 0;
      _phoneTabsOpen = false;
    });
    unawaited(_controller.setPrivate(false));
    _showStart();
  }

  void _newTab() {
    setState(() {
      _tabs.add(_PageTab());
      _tabIndex = _tabs.length - 1;
    });
    unawaited(_controller.setPrivate(false));
    _showStart();
  }

  Future<void> _newIncognitoTab() async {
    setState(() {
      _tabs.add(_PageTab()
        ..incognito = true
        ..title = 'Gizli sekme');
      _tabIndex = _tabs.length - 1;
      _phoneTabsOpen = false;
    });
    await _controller.setPrivate(true);
    _showStart();
  }

  Future<void> _openInNewTab(String url, {bool incognito = false}) async {
    if (!isAvenWebUrl(url)) return;
    setState(() {
      _tabs.add(
        _PageTab()
          ..incognito = incognito
          ..title = incognito ? 'Gizli sekme' : 'Yeni sekme'
          ..url = url,
      );
      _tabIndex = _tabs.length - 1;
      _phoneTabsOpen = false;
    });
    await _controller.setPrivate(incognito);
    await _openInput(url);
  }

  Future<void> _showContextMenu(Map<String, String> info) async {
    if (!mounted || !AvenFlavor.isMobile) return;
    final link = info['link'] ?? '';
    final src = info['src'] ?? '';
    final title = (info['title'] ?? '').trim();
    final hasLink = isAvenWebUrl(link);
    final hasImage = isAvenWebUrl(src);
    if (!hasLink && !hasImage) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AvenTone.elevated(context),
      showDragHandle: true,
      builder: (context) {
        Future<void> go(Future<void> Function() action) async {
          Navigator.pop(context);
          await action();
        }

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              if (hasLink) ...[
                ListTile(
                  leading: const Icon(Icons.tab),
                  title: const Text('Yeni sekmede aç'),
                  onTap: () => unawaited(go(() => _openInNewTab(link))),
                ),
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: const Text('Gizli sekmede aç'),
                  onTap: () => unawaited(go(() => _openInNewTab(link, incognito: true))),
                ),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Bağlantıyı kopyala'),
                  onTap: () => unawaited(go(() async {
                    await Clipboard.setData(ClipboardData(text: link));
                  })),
                ),
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('Bağlantıyı paylaş'),
                  onTap: () => unawaited(go(() async {
                    if (_controller is GeckoPageEngine) {
                      await (_controller as GeckoPageEngine).share(link);
                    }
                  })),
                ),
              ],
              if (hasImage) ...[
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('Resmi yeni sekmede aç'),
                  onTap: () => unawaited(go(() => _openInNewTab(src))),
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Resmi kaydet'),
                  onTap: () => unawaited(go(() => GeckoPageEngine.saveUrl(src))),
                ),
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('Resim adresini kopyala'),
                  onTap: () => unawaited(go(() async {
                    await Clipboard.setData(ClipboardData(text: src));
                  })),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _voiceSearch() async {
    if (_voiceBusy) return;
    setState(() => _voiceBusy = true);
    try {
      final spoken = await _input.recognizeSpeech();
      final text = spoken?.trim() ?? '';
      if (text.isEmpty || !mounted) return;
      await _openInput(text);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  Future<bool> _confirmPermission(String host, String label) async {
    if (!mounted) return false;
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) {
        final ink = AvenTone.text(context);
        return AlertDialog(
          backgroundColor: AvenTone.elevated(context),
          title: Text(host, style: TextStyle(color: ink)),
          content: Text('$label izni istiyor.', style: TextStyle(color: ink)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Engelle'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('İzin ver'),
            ),
          ],
        );
      },
    );
    return allow ?? false;
  }

  void _onSecurity(Map<String, String> info) {
    if (!mounted || _onStart) return;
    final mode = info['mode'] ?? 'unknown';
    if (mode == _connection) return;
    setState(() => _connection = mode);
  }

  Future<void> _showSecurity() async {
    if (_controller is! GeckoPageEngine || _onStart) return;
    final info = await (_controller as GeckoPageEngine).securityInfo();
    if (!mounted) return;
    final mode = info['mode'] ?? _connection;
    final host = info['host']?.isNotEmpty == true
        ? info['host']!
        : Uri.tryParse(_pageUrl ?? '')?.host ?? '';
    final headline = switch (mode) {
      'secure' => 'Bağlantı güvenli',
      'warning' => 'Bağlantıda uyarı var',
      'insecure' => 'Bağlantı güvenli değil',
      _ => 'Güvenlik bilgisi yok',
    };
    final detail = switch (mode) {
      'secure' => 'Bu siteye şifreli (HTTPS) bağlandınız. Sertifika tarayıcıya güvenilir görünüyor.',
      'warning' => 'Adres HTTPS ama sertifika istisnası ya da karışık içerik var. Sayfadaki bazı parçalar şifresiz olabilir.',
      'insecure' => 'Bu site şifresiz HTTP kullanıyor. Girdiğiniz bilgiler başkaları tarafından görülebilir.',
      _ => 'Bu adres için sertifika bilgisi yok.',
    };
    final subject = _certName(info['subject'] ?? '');
    final issuer = _certName(info['issuer'] ?? '');
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AvenTone.elevated(context),
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Row(
                children: [
                  Icon(
                    mode == 'secure'
                        ? Icons.lock
                        : mode == 'warning'
                            ? Icons.warning_amber
                            : Icons.lock_open,
                    color: mode == 'secure'
                        ? const Color(0xFF188038)
                        : mode == 'warning'
                            ? const Color(0xFFE37400)
                            : const Color(0xFFD93025),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      headline,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              if (host.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(host, style: TextStyle(color: AvenTone.textMuted(context))),
              ],
              const SizedBox(height: 12),
              Text(detail),
              if (subject.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Sertifika', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('Konu: $subject'),
                if (issuer.isNotEmpty) Text('Veren: $issuer'),
                if ((info['validFrom'] ?? '').isNotEmpty)
                  Text('Başlangıç: ${info['validFrom']}'),
                if ((info['validTo'] ?? '').isNotEmpty)
                  Text('Bitiş: ${info['validTo']}'),
              ],
            ],
          ),
        );
      },
    );
  }

  String _certName(String raw) {
    if (raw.isEmpty) return '';
    final cn = RegExp(r'CN=([^,]+)').firstMatch(raw)?.group(1)?.trim();
    return cn?.isNotEmpty == true ? cn! : raw;
  }

  Future<void> _showSiteSettings() async {
    if (_controller is! GeckoPageEngine) return;
    final engine = _controller as GeckoPageEngine;
    final items = await engine.siteSettings();
    if (!mounted) return;
    final host = items.isEmpty ? '' : (items.first['host'] ?? '');
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AvenTone.elevated(context),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: host.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Site ayarları için önce bir sayfa açın'),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text(
                        host,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                    for (final item in items)
                      _SitePermRow(
                        id: item['id'] ?? '',
                        label: item['label'] ?? '',
                        value: item['value'] ?? 'ask',
                        onChanged: (value) => unawaited(engine.setSiteSetting(item['id'] ?? '', value)),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _openCast(String url, bool play) async {
    if (!mounted || !isAvenWebUrl(url)) return;
    if (play && _isStreamUrl(url)) {
      final source = VideoSource(url: url, label: 'Aven TV');
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayerPage(
            video: PageVideo(sources: [source], tracks: const []),
            initialSource: source,
          ),
        ),
      );
      return;
    }
    await _openInput(url);
  }

  Future<void> _shareWithTv() async {
    final media = _castMediaUrl;
    final play = media != null && _isStreamUrl(media);
    final url = play ? media : _pageUrl;
    if (url == null || !isAvenWebUrl(url) || !mounted) return;
    final picked = await showModalBottomSheet<({String name, String host, int port})>(
      context: context,
      backgroundColor: AvenTone.elevated(context),
      showDragHandle: true,
      builder: (context) => const _CastTvSheet(),
    );
    if (picked == null || !mounted) return;
    final ok = await _input.sendToTv(
      host: picked.host,
      port: picked.port,
      url: url,
      play: play,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Aven TV\'ye gönderildi' : 'TV\'ye ulaşılamadı'),
      ),
    );
  }

  Future<void> _sharePage() async {
    if (_controller is! GeckoPageEngine) return;
    final url = _pageUrl;
    if (url == null || url.isEmpty) return;
    final title = _pageTitle?.trim() ?? '';
    final text = title.isEmpty ? url : '$title\n$url';
    await (_controller as GeckoPageEngine).share(text);
  }

  void _selectTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs[index];
    setState(() => _tabIndex = index);
    unawaited(() async {
      await _controller.setPrivate(tab.incognito);
      final url = tab.url;
      if (url == null || !isAvenWebUrl(url)) {
        _showStart();
        return;
      }
      await _openInput(url);
    }());
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    if (_tabs.length == 1) {
      _tabs[0] = _PageTab();
      _showStart();
      return;
    }
    final active = index == _tabIndex;
    setState(() {
      _tabs.removeAt(index);
      if (_tabIndex >= _tabs.length) {
        _tabIndex = _tabs.length - 1;
      } else if (index < _tabIndex) {
        _tabIndex -= 1;
      }
    });
    if (active) {
      _selectTab(_tabIndex);
    } else if (AvenFlavor.isMobile && _tabIndex < _tabs.length) {
      unawaited(_controller.setPrivate(_tabs[_tabIndex].incognito));
    }
  }

  Future<void> _handleBack() async {
    // One remote press can arrive both as a key and as a system back.
    final now = DateTime.now();
    if (now.difference(_lastBack) < const Duration(milliseconds: 400)) return;
    if (_exitDialogOpen) return;
    _lastBack = now;
    if (AvenFlavor.isMobile) {
      if (_findOpen) {
        unawaited(_controller.clearFind());
        setState(() => _findOpen = false);
        return;
      }
      if (_startFocus.hasFocus || _addressFocus.hasFocus) {
        _startFocus.unfocus();
        _addressFocus.unfocus();
        return;
      }
      if (_phoneTabsOpen) {
        setState(() => _phoneTabsOpen = false);
        return;
      }
      if (_fullscreenVideo != null) {
        final exit = _exitFullscreen;
        setState(() {
          _fullscreenVideo = null;
          _exitFullscreen = null;
        });
        exit?.call();
        return;
      }
      if (!_onStart && await _controller.canGoBack()) {
        await _controller.goBack();
        return;
      }
      if (!_onStart) {
        _showStart();
        return;
      }
      if (_tabs.length > 1) {
        _closeTab(_tabIndex);
        return;
      }
      await _confirmExit();
      return;
    }
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
    if (_onStart) {
      await _confirmExit();
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
    _suggestDebounce?.cancel();
    _toastHold?.cancel();
    _address.removeListener(_onAddressEdited);
    _findText.dispose();
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
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: AvenFlavor.isMobile
                ? AvenTone.overlay(context)
                : SystemUiOverlayStyle.light,
            child: Scaffold(
        backgroundColor: AvenFlavor.isMobile
            ? Theme.of(context).scaffoldBackgroundColor
            : AvenColors.background,
        body: _phoneTabsOpen && AvenFlavor.isMobile
            ? _PhoneTabGrid(
                tabs: _tabs,
                tabIndex: _tabIndex,
                onCloseGrid: () => setState(() => _phoneTabsOpen = false),
                onSelectTab: (index) {
                  setState(() => _phoneTabsOpen = false);
                  _selectTab(index);
                },
                onCloseTab: _closeTab,
                onCloseAll: _closeAllTabs,
                onNewTab: () {
                  setState(() => _phoneTabsOpen = false);
                  _newTab();
                },
                onIncognito: () => unawaited(_newIncognitoTab()),
              )
            : Column(
          children: [
            Expanded(
              child: Builder(
                builder: (context) {
                  final page = Stack(
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
                      // Keep WebView out of the tree on the start screen — hybrid
                      // composition still costs GPU/CPU even when paused underneath.
                      Positioned.fill(
                        child: _onStart
                            ? ColoredBox(
                                color: AvenFlavor.isMobile
                                    ? Theme.of(context).scaffoldBackgroundColor
                                    : AvenColors.background,
                              )
                            : ValueListenableBuilder<int>(
                                valueListenable: _surfaceKick,
                                builder: (context, kick, child) {
                                  return Transform.translate(
                                    offset: Offset((kick.isOdd) ? 1 : 0, 0),
                                    child: child,
                                  );
                                },
                                child: _controller.buildView(
                                  AvenFlavor.isMobile
                                      ? const <Factory<OneSequenceGestureRecognizer>>{}
                                      : _BrowserPageBase.pageGestures,
                                ),
                              ),
                      ),
                      if (!_onStart &&
                          !_menuOpen &&
                          _fullscreenVideo == null &&
                          !AvenFlavor.isMobile)
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
                if (AvenFlavor.isMobile || !loading || _onStart || _pageError != null) {
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
              Positioned.fill(child: _StartPage(
                phone: AvenFlavor.isMobile,
                address: _address,
                focusNode: _startFocus,
                editing: _startEditing,
                engine: _engine,
                bookmarks: _bookmarks,
                history: _history,
                showSuggestions: _homeSuggestions,
                onTapField: () => setState(() => _startEditing = true),
                onLeaveField: () {
                  if (_startEditing) setState(() => _startEditing = false);
                },
                onSubmit: _openInput,
                onOpenBookmark: _openInput,
                onOpenBookmarks: () => _openLibrary(section: 0),
                onOpenHistory: () => _openLibrary(section: 1),
                onOpenDownloads: () => _openLibrary(section: 2),
                onSettings: _openSettings,
              )),
            if (_pageError != null && !_onStart)
              Positioned.fill(
                child: _PageErrorOverlay(
                  error: _pageError!,
                  menuOpen: _menuOpen,
                  onRetry: _retryPage,
                  onHome: _showStart,
                ),
              ),
            if (!_onStart && !AvenFlavor.isMobile)
              _FloatingMenu(
                open: _menuOpen,
                address: _address,
                addressFocus: _addressFocus,
                menuFocus: _menuFocus,
                editing: _addressEditing,
                canBack: _canBack,
                canForward: _canForward,
                saved: _saved,
                adBlockOn: _adBlock.isEnabled,
                readerOn: _readerOn,
                zoom: _zoom,
                onTapField: () => setState(() => _addressEditing = true),
                onSubmit: _openInput,
                onBack: () => _controller.goBack(),
                onForward: () => _controller.goForward(),
                onReload: () {
                  setState(() {
                    _pageError = null;
                    _readerOn = false;
                  });
                  unawaited(() async {
                    await _resumeWebPage();
                    try {
                      await _controller.reload();
                    } catch (_) {
                      final url = _pageUrl ?? _address.text;
                      if (isAvenWebUrl(url)) {
                        try {
                          await _controller.loadRequest(Uri.parse(url));
                        } catch (_) {}
                      }
                    }
                    await _wakeSurface();
                  }());
                },
                onHome: _showStart,
                onBookmark: _toggleBookmark,
                onLibrary: _openLibrary,
                onToggleAdBlock: _toggleAdBlock,
                onToggleReader: () => unawaited(_toggleReader()),
                onZoomOut: () => _setZoom(_zoom - 10),
                onZoomIn: () => _setZoom(_zoom + 10),
                onZoomReset: () => _setZoom(100),
                onSettings: _openSettings,
                onExit: _confirmExit,
              ),
            if (_warnWebView)
              const Align(
                alignment: Alignment.topCenter,
                child: _WebViewWarning(),
              ),
            if (_openingVideo && _fullscreenVideo == null)
              const Positioned.fill(
                child: _OpeningPlayerOverlay(),
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
        );
                  if (!AvenFlavor.isMobile) return page;
                  return SafeArea(
                    bottom: false,
                    child: ListenableBuilder(
                    listenable: Listenable.merge([_startFocus, _addressFocus, _address]),
                    builder: (context, _) {
                  final atTop = true;
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final fieldTop = atTop
                          ? 4.0
                          : (constraints.maxHeight - 52) / 2 - 28;
                      return Stack(
                        children: [
                          Padding(
                            padding: EdgeInsets.only(top: atTop ? 60 : 0),
                            child: page,
                          ),
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            top: fieldTop,
                            left: 12,
                            right: 12,
                            child: _PhoneOmnibox(
                              address: _address,
                              addressFocus: _onStart ? _startFocus : _addressFocus,
                              editing: _onStart ? _startEditing : _addressEditing,
                              canShare: !_onStart && isAvenWebUrl(_pageUrl),
                              voiceBusy: _voiceBusy,
                              onVoice: () => unawaited(_voiceSearch()),
                              loading: _pageLoading,
                              progress: _progress,
                              onTapField: () {
                                setState(() {
                                  if (_onStart) {
                                    _startEditing = true;
                                  } else {
                                    _addressEditing = true;
                                  }
                                });
                                unawaited(_loadOmniboxSuggestions());
                              },
                              onSubmit: _openInput,
                              incognito: _tabIndex < _tabs.length &&
                                  _tabs[_tabIndex].incognito,
                              connection: _onStart ? 'unknown' : _connection,
                              onSecurity: () => unawaited(_showSecurity()),
                              onShare: () => unawaited(_sharePage()),
                            ),
                          ),
                          if ((_onStart
                                  ? _startFocus.hasFocus
                                  : _addressFocus.hasFocus &&
                                      _address.text.trim() != (_pageUrl ?? '').trim()) &&
                              _omniboxSuggestions.isNotEmpty)
                            Positioned(
                              top: fieldTop + 64,
                              left: 12,
                              right: 12,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: (constraints.maxHeight - fieldTop - 80)
                                      .clamp(120.0, 320.0),
                                ),
                                child: Material(
                                color: AvenTone.elevated(context),
                                borderRadius: BorderRadius.circular(16),
                                clipBehavior: Clip.antiAlias,
                                child: ListView(
                                  children: [
                                    if (_address.text.trim().length < 2)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'Son açılanlar',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AvenTone.textMuted(context),
                                            ),
                                          ),
                                        ),
                                      ),
                                    for (final item in _omniboxSuggestions.take(6))
                                      ListTile(
                                        dense: true,
                                        leading: Icon(
                                          item.isUrl ? Icons.history : Icons.search,
                                          size: 20,
                                        ),
                                        title: Text(
                                          item.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onTap: () => unawaited(_openInput(item.query)),
                                      ),
                                  ],
                                ),
                              ),
                              ),
                            ),
                        ],
                      );
                    },
                  );
                    },
                  ),
                  );
                },
              ),
            ),
            if (AvenFlavor.isMobile && _toastDownload != null)
              _DownloadToast(
                item: _toastDownload!,
                onOpen: () {
                  final id = _toastDownload?['id'] ?? '';
                  if (id.isEmpty) return;
                  unawaited(GeckoPageEngine.openSaved(id));
                  setState(() => _toastHoldId = null);
                },
                onCancel: () {
                  final id = _toastDownload?['id'] ?? '';
                  if (id.isEmpty) return;
                  unawaited(GeckoPageEngine.cancelDownload(id));
                },
                onDismiss: () => setState(() => _toastHoldId = null),
              ),
            if (AvenFlavor.isMobile)
              _PhoneTopBar(
                tabCount: _tabs.length,
                canBack: _canBack,
                canForward: _canForward,
                saved: _saved,
                adBlockOn: _adBlock.isEnabled,
                readerOn: _readerOn,
                zoom: _zoom,
                desktopSite: _desktopSite,
                onBack: () {
                  if (_canBack) {
                    unawaited(_controller.goBack());
                  } else if (!_onStart) {
                    _showStart();
                  }
                },
                onForward: () => _controller.goForward(),
                onNewTab: _newTab,
                onTabs: () => setState(() => _phoneTabsOpen = true),
                onBookmark: _toggleBookmark,
                onLibrary: _openLibrary,
                onToggleAdBlock: _toggleAdBlock,
                onToggleReader: () => unawaited(_toggleReader()),
                onZoomOut: () => _setZoom(_zoom - 10),
                onZoomIn: () => _setZoom(_zoom + 10),
                onZoomReset: () => _setZoom(100),
                onSettings: _openSettings,
                onToggleDesktop: () => unawaited(_toggleDesktopSite()),
                onIncognito: () => unawaited(_newIncognitoTab()),
                onFind: () {
                  if (_onStart) return;
                  setState(() => _findOpen = true);
                },
                onDownloads: () => unawaited(_openLibrary(section: 2)),
                onShare: () => unawaited(_sharePage()),
                onCast: () => unawaited(_shareWithTv()),
                playingVideo: _castMediaUrl != null,
                onSiteSettings: () => unawaited(_showSiteSettings()),
                canShare: !_onStart && isAvenWebUrl(_pageUrl),
                canReload: !_onStart,
                onReload: () {
                  setState(() {
                    _pageError = null;
                    _readerOn = false;
                  });
                  unawaited(_controller.reload());
                },
              ),
            if (AvenFlavor.isMobile && _findOpen)
              Material(
                color: AvenTone.elevated(context),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _findText,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'Sayfada bul',
                            isDense: true,
                            border: InputBorder.none,
                          ),
                          onChanged: (value) {
                            if (value.trim().isEmpty) {
                              unawaited(_controller.clearFind());
                            } else {
                              unawaited(_controller.findInPage(value));
                            }
                          },
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          final value = _findText.text;
                          if (value.isNotEmpty) {
                            unawaited(_controller.findInPage(value));
                          }
                        },
                        icon: const Icon(Icons.keyboard_arrow_down),
                        tooltip: 'Sonraki',
                      ),
                      IconButton(
                        onPressed: () {
                          unawaited(_controller.clearFind());
                          setState(() => _findOpen = false);
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
        ),
      ),
    );
  }
}
