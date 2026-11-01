import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/l10n/aven_strings.dart';
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
import '../remote/tv_remote_page.dart';
import '../settings/settings_page.dart';
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
  String title = avenText('aven_new_tab');
  bool incognito = false;
  Uint8List? preview;
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

/// Phone page hooks: tells Flutter when to tuck the bars away (scrolling
/// down), bring them back (up or near the top), and how far a pull at the
/// very top has gone. Inner scrolled panes never count as "at the top".
const _scrollHooks = r'''
(function(){
  if (window.__avenScrollHook || !window.AvenScroll) return;
  window.__avenScrollHook = true;
  function send(m){ try { AvenScroll.postMessage(m); } catch (e) {} }
  function top(){ return window.scrollY || document.documentElement.scrollTop || 0; }
  var last = top(), run = 0, hidden = false;
  window.addEventListener('scroll', function(){
    var y = top(), d = y - last;
    last = y;
    if (y < 48) { run = 0; if (hidden) { hidden = false; send('show'); } return; }
    if ((d > 0) !== (run > 0)) run = 0;
    run += d;
    if (!hidden && run > 56) { hidden = true; send('hide'); }
    else if (hidden && run < -40) { hidden = false; send('show'); }
  }, {passive: true});
  var startY = null, dist = 0, shown = 0;
  function scrolledAbove(el){
    for (; el && el !== document.body && el !== document.documentElement; el = el.parentElement) {
      if (el.scrollTop > 0) return true;
    }
    return false;
  }
  function report(v){
    if (Math.abs(v - shown) < 0.04 && v !== 0) return;
    shown = v;
    send('pull:' + v.toFixed(2));
  }
  document.addEventListener('touchstart', function(e){
    dist = 0;
    startY = e.touches.length === 1 && top() <= 0 && !scrolledAbove(e.target)
      ? e.touches[0].clientY : null;
  }, {passive: true});
  document.addEventListener('touchmove', function(e){
    if (startY === null) return;
    if (top() > 0 || e.touches.length !== 1) { startY = null; if (shown) report(0); return; }
    dist = e.touches[0].clientY - startY;
    report(dist > 0 ? Math.min(dist / 150, 1.5) : 0);
  }, {passive: true});
  function end(){
    if (startY !== null && shown) send(dist >= 150 ? 'refresh' : 'pull:0');
    startY = null; dist = 0; shown = 0;
  }
  document.addEventListener('touchend', end, {passive: true});
  document.addEventListener('touchcancel', end, {passive: true});
})();
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

  /// TV home screen row: bookmarks, or recent pages while there are none.
  Future<void> _syncHomeChannel() async {
    if (AvenFlavor.isMobile) return;
    final bookmarks = await _store.loadBookmarks();
    final recent = bookmarks.isEmpty;
    final links = recent ? await _store.loadHistory() : bookmarks;
    final label = recent ? avenText('aven_recent') : avenText('aven_bookmarks');
    try {
      await _input.syncHomeChannel(
        title: 'Aven · $label',
        links: [
          for (final link in links.take(12)) (title: link.title, url: link.url),
        ],
      );
    } catch (_) {}
  }

  final _address = TextEditingController();
  final _addressFocus = FocusNode();
  final _startFocus = FocusNode();
  final _surfaceFocus = FocusNode();
  final _menuFocus = FocusNode();
  final _menuVoiceFocus = FocusNode();
  final _cursor = ValueNotifier<Offset>(Offset.zero);
  final _cursorVisible = ValueNotifier<bool>(true);
  final _cursorLook = ValueNotifier<_CursorLook>(_CursorLook.normal);
  final _progress = ValueNotifier<int>(0);
  final _pageLoading = ValueNotifier<bool>(false);
  final _surfaceKick = ValueNotifier<int>(0);
  Timer? _loadTimeout;
  Timer? _cursorHide;
  Widget? _fullscreenVideo;

  /// Phone: a page video is fullscreen inside GeckoView, so the browser
  /// chrome and system bars step aside.
  bool _pageFullscreen = false;
  Timer? _downloadPoll;
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
  bool _autofillPrompted = false;
  bool _popupOpen = false;
  bool _externalOpen = false;
  bool _addressEditing = false;
  bool _startEditing = false;
  bool _canBack = false;
  bool _canForward = false;
  bool _warnWebView = false;
  bool _lite = false;
  bool _homeSuggestions = true;
  bool _homeBookmarks = true;
  bool _desktopSite = false;
  String _connection = 'unknown';
  bool _findOpen = false;
  int _findCurrent = 0;
  int _findTotal = 0;
  Timer? _previewTimer;
  bool _voiceBusy = false;

  /// Phone: tabs closed lately, newest first, for Undo and the tab grid.
  final List<({String url, String title})> _closedTabs = [];

  /// Phone: the page scrolled down, so the address and tool bars step aside.
  bool _barsHidden = false;

  /// Phone: the user tucked the address bar away to see the top of a page;
  /// it comes back once they scroll down and up again.
  bool _addressTucked = false;

  /// Phone: pull-to-refresh distance (1 = far enough), and a reload it started.
  final _pull = ValueNotifier<double>(0);
  bool _pullRefreshing = false;

  /// Videos left part way, newest first (start screen row).
  List<WatchProgress> _watching = const [];
  final _findText = TextEditingController();
  final _findFocus = FocusNode();
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
  Future<void> _refreshSecurity();
  void _leavePageTyping();
  Future<void> _installMediaSiteHints();
  Future<void> _openInput(String raw);
  void _syncChrome();
  void _schedulePreview();

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
      } else if (call.method == 'downloadStarted') {
        unawaited(_leaveDownloadPage('${call.arguments ?? ''}'));
        if (AvenFlavor.isMobile) _watchDownloads();
      } else if (call.method == 'contextMenu' && call.arguments is Map) {
        final raw = Map<Object?, Object?>.from(call.arguments as Map);
        unawaited(_showContextMenu({
          for (final entry in raw.entries) '${entry.key}': '${entry.value ?? ''}',
        }));
      } else if (call.method == 'pageTypingEnded') {
        _leavePageTyping();
      } else if (call.method == 'remote' && call.arguments is Map) {
        _onRemote(Map<Object?, Object?>.from(call.arguments as Map));
      } else if (call.method == 'cast' && call.arguments is Map) {
        final raw = Map<Object?, Object?>.from(call.arguments as Map);
        final url = '${raw['url'] ?? ''}';
        // Phone: a link from another app gets its own tab.
        if (AvenFlavor.isMobile) {
          unawaited(_openInNewTab(url));
        } else {
          _notify(avenText('aven_cast_received'), icon: Icons.smartphone);
          unawaited(_openCast(url, raw['play'] == true));
        }
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
    _controller = WebViewPageEngine(
      onPageStarted: _onPageStarted,
      onPageFinished: (url) => unawaited(_onPageFinished(url)),
      onProgress: onProgress,
      onNavigationRequest: _onNavigationRequest,
      onError: _onError,
      onHttpError: _onHttpError,
      onPermission: AvenFlavor.isMobile ? _decidePermission : null,
    );
    _address.addListener(_onAddressEdited);
    _boot();
  }

  void _onPageFullscreen(bool fullscreen) {
    if (!mounted || fullscreen == _pageFullscreen) return;
    setState(() {
      _pageFullscreen = fullscreen;
      if (fullscreen) _findOpen = false;
    });
    // No orientation lock: the screen keeps following how the phone is held.
    unawaited(SystemChrome.setEnabledSystemUIMode(
      fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    ));
  }

  /// Phone: page permission requests, remembered per site like a browser does.
  Future<bool> _decidePermission(String host, List<String> kinds) async {
    final incognito = _tabIndex < _tabs.length && _tabs[_tabIndex].incognito;
    for (final kind in kinds) {
      var choice = host.isEmpty ? 'ask' : await _store.loadSitePermission(host, kind);
      if (choice == 'ask') {
        final allow = await _confirmPermission(
          host.isEmpty ? avenText('aven_this_site') : host,
          permissionLabel(kind),
        );
        choice = allow ? 'allow' : 'block';
        if (!incognito && host.isNotEmpty) {
          await _store.saveSitePermission(host, kind, choice);
        }
      }
      if (choice != 'allow') return false;
    }
    // The page may use it only if Android lets Aven use it too.
    return WebInput.ensurePermissions(kinds);
  }

  /// Phone: follow downloads started from the page for the progress toast.
  void _watchDownloads() {
    _downloadPoll?.cancel();
    Future<void> tick() async {
      final items = await WebInput.listDownloads();
      if (!mounted) return;
      _onDownloadList(items);
      if (!items.any((item) => downloadIsActive(item['status']))) {
        _downloadPoll?.cancel();
        _downloadPoll = null;
      }
    }

    unawaited(tick());
    _downloadPoll = Timer.periodic(const Duration(milliseconds: 700), (_) => unawaited(tick()));
  }

  @override
  Future<void> _refreshSecurity() async {
    if (!AvenFlavor.isMobile || _onStart) return;
    _onSecurity(await WebInput.pageSecurity());
  }

  void _onDownloadList(List<Map<String, String>> items) {
    final active = items.where((item) {
      final status = item['status'];
      return downloadIsActive(status);
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
      if (downloadIsActive(status)) {
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
    final homeBookmarks = await _store.loadHomeBookmarks();
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
      _homeBookmarks = homeBookmarks;
      _desktopSite = agent == BrowserAgent.desktop;
      _warnWebView = !AvenFlavor.isMobile && major != null && major < 80;
    });
    if (AvenFlavor.isMobile) await _restoreTabs();
    unawaited(_refreshWatching());
    unawaited(_syncHomeChannel());
    final launchUrl = await _input.takeLaunchUrl();
    if (launchUrl != null && mounted) {
      if (AvenFlavor.isMobile) {
        await _openInNewTab(launchUrl);
      } else {
        await _openCast(launchUrl, false);
      }
      return;
    }
    if (AvenFlavor.isMobile) unawaited(_offerDefaultBrowser());
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
        if (AvenFlavor.isMobile) _onPageFullscreen(true);
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
        if (AvenFlavor.isMobile) _onPageFullscreen(false);
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
    if (AvenFlavor.isMobile) {
      await _controller.addJavaScriptChannel(
        'AvenScroll',
        onMessageReceived: _onScrollMessage,
      );
    }
    try {
      _userAgent = await _controller.getUserAgent();
    } catch (_) {}
  }

  Future<void> _onWatchedMedia(String url) async {
    if (!mounted || !isAvenWebUrl(url) || isAdMediaUrl(url)) return;
    if (AvenFlavor.isMobile) return;
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
      // The phone plays videos in the page; the Aven player is a TV thing.
      videoWatch: AvenFlavor.isMobile ? '' : videoWatchScript,
    );
    if (AvenFlavor.isMobile) {
      try {
        await _controller.runJavaScript(_scrollHooks);
      } catch (_) {}
    }
  }

  /// Phone page scroll: hide the bars going down, show them going up, and
  /// pull down at the very top to reload.
  void _onScrollMessage(JavaScriptMessage message) {
    if (!mounted || !AvenFlavor.isMobile) return;
    final text = message.message;
    if (text == 'hide' || text == 'show') {
      final hide = text == 'hide' &&
          !_onStart &&
          !_findOpen &&
          !_addressFocus.hasFocus &&
          _pageError == null;
      // Scrolling back up also brings back an address bar the user tucked away.
      final untuck = text == 'show' && _addressTucked;
      if (hide != _barsHidden || untuck) {
        setState(() {
          _barsHidden = hide;
          if (untuck) _addressTucked = false;
        });
      }
      return;
    }
    if (text == 'refresh') {
      _pull.value = 0;
      unawaited(HapticFeedback.mediumImpact());
      setState(() {
        _pullRefreshing = true;
        _barsHidden = false;
        _pageError = null;
        _readerOn = false;
      });
      unawaited(_controller.reload());
      // A page that never reports finishing must not leave the spinner up.
      Timer(const Duration(seconds: 8), () {
        if (mounted && _pullRefreshing) setState(() => _pullRefreshing = false);
      });
      return;
    }
    if (text.startsWith('pull:')) {
      _pull.value = double.tryParse(text.substring(5)) ?? 0;
    }
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
    // A download link never fires onPageStarted, so hook the TV WebView
    // (download listener, ad block client) before the first load.
    if (!AvenFlavor.isMobile) await _input.watchMedia();
    try {
      await _controller.loadRequest(Uri.parse(target));
    } catch (_) {}
    _surfaceFocus.requestFocus();
    unawaited(_wakeSurface());
  }

  void _showStart() {
    unawaited(_refreshWatching());
    setState(() {
      _onStart = true;
      _barsHidden = false;
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
        _tabs[_tabIndex].title = avenText('aven_new_tab');
      }
      _exitFullscreen = null;
      _address.text = '';
    });
    unawaited(_persistTabs());
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
              destructive: true,
              icon: Icons.power_settings_new_rounded,
              title: avenText('aven_exit_title'),
              message: avenText('aven_exit_message'),
              cancelLabel: avenText('aven_cancel'),
              confirmLabel: avenText('aven_quit'),
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
    final previous = _bookmarks;
    final stored = await _store.saveBookmarks(next);
    if (!mounted) return;
    unawaited(_syncHomeChannel());
    setState(() {
      _bookmarks = stored;
      _saved = stored.any((item) => item.url == url);
    });
    if (exists) {
      _notify(
        avenText('aven_bookmark_removed'),
        icon: Icons.star_border,
        action: avenText('aven_undo'),
        onAction: () => unawaited(() async {
          final back = await _store.saveBookmarks(previous);
          if (!mounted) return;
          unawaited(_syncHomeChannel());
          setState(() {
            _bookmarks = back;
            _saved = back.any((item) => item.url == _pageUrl);
          });
        }()),
      );
    } else {
      _notify(
        avenText('aven_bookmark_added'),
        icon: Icons.star,
        action: avenText('aven_view'),
        onAction: () => unawaited(_openLibrary(section: 0)),
      );
    }
  }

  /// TV panels slide in from the right at full height; the page stays
  /// visible beside them.
  Future<T?> _showTvSheet<T>({required String label, required Widget child}) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: label,
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        final size = MediaQuery.sizeOf(context);
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: AvenColors.background,
            elevation: 24,
            child: SizedBox(
              width: size.width * 0.67,
              height: size.height,
              child: child,
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween(
            begin: const Offset(0.35, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
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
      if (picked != null) await _openPicked(picked);
      return;
    }
    final opener = FocusManager.instance.primaryFocus;
    final picked = await _showTvSheet<String>(
      label: avenText('aven_library'),
      child: LibraryPage(store: _store, initialSection: section),
    );
    _bookmarks = await _store.loadBookmarks();
    _history = await _store.loadHistory();
    unawaited(_syncHomeChannel());
    if (!mounted) return;
    setState(() => _saved = _bookmarks.any((item) => item.url == _pageUrl));
    if (picked != null) {
      await _openPicked(picked);
      return;
    }
    _restoreFocusAfterPanel(opener);
  }

  Future<void> _openPicked(String picked) async {
    const prefix = LibraryPage.readingPrefix;
    if (picked.startsWith(prefix)) {
      await _openReading(int.tryParse(picked.substring(prefix.length)) ?? 0);
    } else {
      await _openInput(picked);
    }
  }

  Object? _decodeJs(Object? raw) {
    var value = raw;
    // Android hands the JSON back as a quoted string; unwrap until it is data.
    for (var i = 0; i < 3 && value is String; i++) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return value;
      }
    }
    return value;
  }

  /// Confirms an action. The phone gets a shortcut button (View, Undo) above
  /// the floating toolbar; the TV shows it at the top, clear of its menu,
  /// without a button the remote could not reach.
  void _notify(String text, {IconData? icon, String? action, VoidCallback? onAction}) {
    if (!mounted) return;
    final phone = AvenFlavor.isMobile;
    final ink = Theme.of(context).colorScheme.onInverseSurface;
    final size = MediaQuery.sizeOf(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: phone ? 20 : 26, color: ink),
              SizedBox(width: phone ? 12 : 16),
            ],
            Expanded(
              child: Text(text, style: TextStyle(fontSize: phone ? 14 : 18)),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(phone ? 14 : 18)),
        margin: phone
            ? const EdgeInsets.fromLTRB(12, 0, 12, 84)
            : EdgeInsets.fromLTRB(size.width * 0.28, 0, size.width * 0.28, size.height - 120),
        duration: const Duration(seconds: 3),
        persist: false,
        action: phone && action != null && onAction != null
            ? SnackBarAction(label: action, onPressed: onAction)
            : null,
      ));
  }

  /// Read later: keeps the link, plus the article text for offline reading.
  Future<void> _readLater() async {
    final url = _pageUrl;
    if (_onStart || url == null || !isAvenWebUrl(url)) return;
    final title = (_pageTitle?.trim().isNotEmpty ?? false) ? _pageTitle!.trim() : url;
    final now = DateTime.now().millisecondsSinceEpoch;
    String? file;
    try {
      final data = _decodeJs(await _controller.runJavaScriptReturningResult(readerExtractScript));
      final html = data is Map ? '${data['html'] ?? ''}' : '';
      final dir = await WebInput.filesDir();
      if (html.trim().length > 200 && dir != null) {
        final out = File('$dir/reading/$now.json');
        await out.create(recursive: true);
        await out.writeAsString(jsonEncode({'html': html}));
        file = out.path;
      }
    } catch (_) {}
    final current = await _store.loadReadingList();
    for (final old in current.where((item) => item.url == url)) {
      final path = old.file;
      if (path == null) continue;
      try {
        await File(path).delete();
      } catch (_) {}
    }
    await _store.saveReadingList([
      ReadingItem(title: title, url: url, savedAt: now, file: file),
      ...current.where((item) => item.url != url),
    ]);
    if (!mounted) return;
    _notify(
      avenText(file == null ? 'aven_reading_saved' : 'aven_reading_saved_offline'),
      icon: Icons.bookmark_added_outlined,
      action: avenText('aven_view'),
      onAction: () => unawaited(_openLibrary(section: 3)),
    );
  }

  /// Opens a reading list copy in the page view, without the network.
  Future<void> _openReading(int savedAt) async {
    final items = await _store.loadReadingList();
    final item = items.where((entry) => entry.savedAt == savedAt).firstOrNull;
    if (item == null || !mounted) return;
    String? article;
    try {
      final data = jsonDecode(await File(item.file!).readAsString());
      if (data is Map && data['html'] is String) article = data['html'] as String;
    } catch (_) {}
    if (!mounted) return;
    if (article == null) {
      await _openInput(item.url);
      return;
    }
    final saved = DateTime.fromMillisecondsSinceEpoch(savedAt);
    final page = offlineReadingPage(
      item: item,
      article: article,
      dark: Theme.of(context).brightness == Brightness.dark,
      savedLabel: avenText('aven_offline_copy', ['${saved.day}.${saved.month}.${saved.year}']),
    );
    setState(() {
      _onStart = false;
      _menuOpen = false;
      _addressEditing = false;
      _startEditing = false;
      _pageError = null;
      _readerOn = false;
      _pageUrl = item.url;
      _pageTitle = item.title;
      _address.text = item.url;
    });
    _syncChrome();
    _addressFocus.unfocus();
    _startFocus.unfocus();
    _surfaceFocus.canRequestFocus = true;
    _webSuspended = false;
    try {
      await _input.resumeWebView();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 32));
    try {
      await _controller.loadHtml(page, baseUrl: item.url);
    } catch (_) {}
    unawaited(_wakeSurface());
  }

  Future<void> _refreshWatching() async {
    final items = await _store.loadWatchProgress();
    if (!mounted) return;
    setState(() => _watching = items.where((item) => item.page != null).toList());
  }

  /// Phone: suggests making Aven the default browser, once.
  Future<void> _offerDefaultBrowser() async {
    if (await _store.loadDefaultBrowserAsked()) return;
    bool isDefault;
    try {
      isDefault = await WebInput.isDefaultBrowser();
    } catch (_) {
      return;
    }
    if (isDefault || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    await _store.saveDefaultBrowserAsked();
    if (!mounted) return;
    final set = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AvenTone.elevated(context),
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.public, size: 40, color: AvenTone.text(context)),
                const SizedBox(height: 14),
                Text(
                  avenText('aven_default_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  avenText('aven_default_detail'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: AvenTone.textMuted(context)),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(avenText('aven_default_set')),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(avenText('aven_default_later')),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (set == true) {
      try {
        if (await WebInput.requestDefaultBrowser()) {
          _notify(avenText('aven_default_is'), icon: Icons.check_circle_outline);
        }
      } catch (_) {}
    }
  }

  /// Phone: pick an Aven TV on the network and drive it from the phone.
  Future<void> _openTvRemote() async {
    final picked = await showModalBottomSheet<({String name, String host, int port})>(
      context: context,
      backgroundColor: AvenTone.elevated(context),
      showDragHandle: true,
      builder: (context) => const _CastTvSheet(),
    );
    if (picked == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => TvRemotePage(name: picked.name, host: picked.host, port: picked.port),
      ),
    );
  }

  /// TV: a command from a phone remote. Keys arrive as real key presses
  /// (see AvenCast); this handles the cursor, scrolling and typed text.
  void _onRemote(Map<Object?, Object?> args) {
    if (!mounted || AvenFlavor.isMobile) return;
    double number(Object? value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    final onPage = !_onStart &&
        !_menuOpen &&
        _pageError == null &&
        !_openingVideo &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    switch ('${args['cmd']}') {
      case 'move':
        if (!onPage || _webSize.isEmpty) return;
        final next = _cursor.value + Offset(number(args['dx']), number(args['dy']));
        final maxX = (_webSize.width - 1).clamp(0.0, double.infinity);
        final maxY = (_webSize.height - 1).clamp(0.0, double.infinity);
        final clamped = Offset(next.dx.clamp(0.0, maxX), next.dy.clamp(0.0, maxY));
        _cursor.value = clamped;
        _bumpCursor();
        // Pushing past an edge scrolls the page, like holding an arrow there.
        final overX = next.dx - clamped.dx;
        final overY = next.dy - clamped.dy;
        if (overX != 0 || overY != 0) {
          unawaited(_scrollBy(overX, overY, clamped.dx, clamped.dy));
        }
      case 'scroll':
        if (!onPage) return;
        final at = _cursor.value;
        unawaited(_scrollBy(0, number(args['dy']), at.dx, at.dy));
      case 'click':
        if (onPage) {
          unawaited(_activate());
        } else {
          unawaited(WebInput.pressKey('ok'));
        }
      case 'text':
        unawaited(_remoteText('${args['text'] ?? ''}', args['submit'] == true));
    }
  }

  Future<void> _remoteText(String text, bool submit) async {
    // Start screen or the menu's address bar: fill it like typing on the TV.
    if (_onStart || _menuOpen) {
      _address.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      if (submit && text.trim().isNotEmpty) await _openInput(text);
      return;
    }
    // A focused page field takes the text; with none, the text is a search.
    final script = '''
(function(){
  var t = ${jsonEncode(text)}, submit = $submit;
  var el = document.activeElement;
  while (el && el.shadowRoot && el.shadowRoot.activeElement) el = el.shadowRoot.activeElement;
  var editable = el && (el.isContentEditable || /^(input|textarea)\$/i.test(el.tagName));
  if (!editable) return 'none';
  if (el.isContentEditable) {
    document.execCommand('insertText', false, t);
  } else {
    var proto = /textarea/i.test(el.tagName) ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, t);
    el.dispatchEvent(new Event('input', {bubbles: true}));
    el.dispatchEvent(new Event('change', {bubbles: true}));
  }
  if (submit) {
    var key = {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true};
    el.dispatchEvent(new KeyboardEvent('keydown', key));
    el.dispatchEvent(new KeyboardEvent('keyup', key));
    if (el.form) {
      try { el.form.requestSubmit ? el.form.requestSubmit() : el.form.submit(); } catch (e) {}
    }
  }
  return 'ok';
})();
''';
    try {
      final result = await _controller.runJavaScriptReturningResult(script);
      if ('$result'.contains('ok')) return;
    } catch (_) {}
    if (submit && text.trim().isNotEmpty) await _openInput(text);
  }

  Future<void> _openSettings() async {
    final opener = FocusManager.instance.primaryFocus;
    // Settings close with a link when the user picks the website row.
    final String? link;
    if (AvenFlavor.isMobile) {
      link = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => SettingsPage(store: _store, input: _input),
        ),
      );
    } else {
      link = await _showTvSheet<String>(
        label: avenText('aven_settings'),
        child: SettingsPage(store: _store, input: _input),
      );
    }
    final engine = await _store.loadEngine();
    final block = await _store.loadAdBlock();
    final provider = await _store.loadAdBlockProvider();
    final agent = await _store.loadAgent();
    final lite = await _store.loadLiteBrowsing(fallback: !AvenFlavor.isMobile);
    final homeBookmarks = await _store.loadHomeBookmarks();
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
      _homeBookmarks = homeBookmarks;
    });
    if (link != null) {
      await _openInput(link);
      return;
    }
    if (!_onStart && isAvenWebUrl(_pageUrl)) {
      await _controller.reload();
    }
    _restoreFocusAfterPanel(opener);
  }

  /// Puts focus back on the button that opened a TV panel (History,
  /// Bookmarks, Settings…) instead of jumping to the address bar.
  void _restoreFocusAfterPanel(FocusNode? opener) {
    final tv = !AvenFlavor.isMobile;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (tv && opener != null && opener.context != null && opener.canRequestFocus) {
        opener.requestFocus();
        return;
      }
      if (_onStart) {
        if (tv) _startFocus.requestFocus();
      } else if (_menuOpen) {
        _menuFocus.requestFocus();
      }
    });
  }

  Future<void> _toggleAdBlock() async {
    final next = _adBlock == AdBlock.off ? _adBlockProvider : AdBlock.off;
    await _store.saveAdBlock(next);
    await _input.setAdBlock(next.name);
    if (next.isEnabled) await _installAdblockCss();
    if (!mounted) return;
    setState(() => _adBlock = next);
    _notify(
      avenText(next.isEnabled ? 'aven_adblock_now_on' : 'aven_adblock_now_off'),
      icon: next.isEnabled ? Icons.shield : Icons.shield_outlined,
    );
  }

  Future<void> _toggleReader() async {
    if (_onStart || _pageError != null) return;
    try {
      final raw = await _controller.runJavaScriptReturningResult(readerToggleScript);
      final text = raw.toString().replaceAll('"', '').trim().toLowerCase();
      if (!mounted) return;
      setState(() => _readerOn = text == 'on');
      _notify(
        avenText(switch (text) {
          'on' => 'aven_reader_now_on',
          'off' => 'aven_reader_now_off',
          _ => 'aven_reader_none',
        }),
        icon: Icons.chrome_reader_mode_outlined,
      );
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

  /// Back on the remote ended typing in a page field (Android side).
  @override
  void _leavePageTyping() {
    if (!_pageTyping) return;
    _pageTyping = false;
    if (!_menuOpen) {
      _surfaceFocus.canRequestFocus = true;
      _surfaceFocus.requestFocus();
    }
  }

  void _openMenu() {
    // Reset both sides: a stale typing flag on either would keep the D-pad
    // away from the menu.
    _pageTyping = false;
    unawaited(_input.setPageTyping(false));
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
    // Opening the menu blurs the WebView, and the page then reports its
    // still-active field again; typing must not start under open chrome.
    if (typing && (_menuOpen || _onStart)) return;
    if (!mounted || typing == _pageTyping) return;
    _pageTyping = typing;
    _input.setPageTyping(typing);
    if (typing) {
      _surfaceFocus.canRequestFocus = false;
      _surfaceFocus.unfocus();
      if (AvenFlavor.isMobile) unawaited(_offerAutofill());
      return;
    }
    if (!_menuOpen) {
      _surfaceFocus.canRequestFocus = true;
    }
  }

  Future<void> _offerAutofill() async {
    final status = await WebInput.autofillStatus();
    if (!mounted || status != 'off' || _autofillPrompted) return;
    _autofillPrompted = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(avenText('aven_autofill_off')),
        action: SnackBarAction(
          label: avenText('aven_turn_on'),
          onPressed: () => unawaited(WebInput.openAutofillSettings()),
        ),
      ),
    );
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
          title: avenText('aven_popup_title'),
          message: url,
          cancelLabel: avenText('aven_cancel'),
          confirmLabel: avenText('aven_open'),
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
    if (AvenFlavor.isMobile) return;
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
          builder: (context) => VideoPlayerPage(
            video: video,
            initialSource: initial,
            pageUrl: _pageUrl,
            pageTitle: _pageTitle,
          ),
        ),
      );
      unawaited(_refreshWatching());
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
    _notify(
      avenText(_desktopSite ? 'aven_desktop_now_on' : 'aven_desktop_now_off'),
      icon: _desktopSite ? Icons.desktop_windows_outlined : Icons.smartphone,
    );
    if (!_onStart) {
      setState(() {
        _pageError = null;
        _readerOn = false;
      });
      await _controller.reload();
    }
  }

  /// Remembers [tabs] for Undo; returns how many were worth remembering.
  int _rememberClosed(Iterable<_PageTab> tabs) {
    var count = 0;
    for (final tab in tabs) {
      final url = tab.url;
      if (tab.incognito || url == null || !isAvenWebUrl(url)) continue;
      _closedTabs.removeWhere((item) => item.url == url);
      _closedTabs.insert(0, (url: url, title: tab.title));
      count++;
    }
    if (_closedTabs.length > 15) _closedTabs.removeRange(15, _closedTabs.length);
    return count;
  }

  void _offerUndo(int count) {
    if (!AvenFlavor.isMobile || count == 0 || !mounted) return;
    // Oldest first, so Undo brings the tabs back in their old order.
    final items = _closedTabs.take(count).toList().reversed.toList();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          count == 1 ? avenText('aven_tab_closed') : avenText('aven_tabs_closed', [count]),
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 84),
        duration: const Duration(seconds: 4),
        // With an action Flutter keeps the bar up until tapped; let it time out.
        persist: false,
        action: SnackBarAction(
          label: avenText('aven_undo'),
          onPressed: () => _reopenClosed(items),
        ),
      ));
  }

  void _reopenClosed(List<({String url, String title})> items) {
    if (items.isEmpty || !mounted) return;
    _closedTabs.removeWhere((closed) => items.any((item) => item.url == closed.url));
    // Close all leaves one blank tab behind; reuse it.
    final blank = _tabs.length == 1 && _tabs.first.url == null;
    setState(() {
      if (blank) _tabs.clear();
      for (final item in items) {
        _tabs.add(_PageTab()
          ..url = item.url
          ..title = item.title);
      }
    });
    _selectTab(_tabs.length - 1);
  }

  void _closeAllTabs() {
    final remembered = _rememberClosed(_tabs);
    _offerUndo(remembered);
    setState(() {
      _tabs
        ..clear()
        ..add(_PageTab());
      _tabIndex = 0;
      _phoneTabsOpen = false;
    });
    unawaited(_controller.setPrivate(false));
    unawaited(_persistTabs());
    _showStart();
  }

  Future<void> _restoreTabs() async {
    final saved = await _store.loadOpenTabs();
    if (!mounted || saved.tabs.isEmpty) return;
    final hasPage = saved.tabs.any((tab) => tab.url != null);
    if (!hasPage && saved.tabs.length <= 1) return;
    setState(() {
      _tabs
        ..clear()
        ..addAll(
          saved.tabs.map((tab) {
            Uint8List? preview;
            final raw = tab.preview;
            if (raw != null) {
              try {
                preview = base64Decode(raw);
              } catch (_) {}
            }
            return _PageTab()
              ..url = tab.url
              ..title = tab.title
              ..preview = preview;
          }),
        );
      _tabIndex = saved.index.clamp(0, _tabs.length - 1);
    });
    final url = _tabs[_tabIndex].url;
    if (url != null && isAvenWebUrl(url)) {
      await _openInput(url);
    }
  }

  Future<void> _persistTabs() async {
    if (!AvenFlavor.isMobile) return;
    final visible = <({String? url, String title, String? preview, bool incognito})>[];
    var active = 0;
    for (var i = 0; i < _tabs.length; i++) {
      final tab = _tabs[i];
      if (tab.incognito) continue;
      if (i == _tabIndex) active = visible.length;
      final bytes = tab.preview;
      visible.add((
        url: tab.url,
        title: tab.title,
        preview: bytes == null || bytes.isEmpty ? null : base64Encode(bytes),
        incognito: false,
      ));
    }
    if (_tabIndex < _tabs.length && _tabs[_tabIndex].incognito && visible.isNotEmpty) {
      active = visible.length - 1;
    }
    await _store.saveOpenTabs(visible, active);
  }

  void _schedulePreview() {
    if (!AvenFlavor.isMobile || _onStart) return;
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 800), () async {
      await _captureCurrentTab();
      await _persistTabs();
      if (mounted && _phoneTabsOpen) setState(() {});
    });
  }

  Future<void> _captureCurrentTab() async {
    if (!AvenFlavor.isMobile || _onStart) return;
    if (_tabIndex < 0 || _tabIndex >= _tabs.length) return;
    final bytes = await WebInput.pagePreview();
    if (bytes == null || !mounted || _tabIndex >= _tabs.length) return;
    _tabs[_tabIndex].preview = bytes;
  }

  Future<void> _openTabGrid() async {
    await _captureCurrentTab();
    await _persistTabs();
    if (!mounted) return;
    setState(() => _phoneTabsOpen = true);
  }

  Future<void> _applyFind(String query, {bool forward = true}) async {
    if (query.trim().isEmpty) {
      await _controller.clearFind();
      if (mounted) {
        setState(() {
          _findCurrent = 0;
          _findTotal = 0;
        });
      }
      return;
    }
    final found = await _controller.findInPage(query, forward: forward);
    if (!mounted) return;
    setState(() {
      _findCurrent = found['current'] ?? 0;
      _findTotal = found['total'] ?? 0;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      unawaited(_persistTabs());
    }
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
        ..title = avenText('aven_private_tab'));
      _tabIndex = _tabs.length - 1;
      _phoneTabsOpen = false;
    });
    await _controller.setPrivate(true);
    _showStart();
    _notify(avenText('aven_private_started'), icon: Icons.visibility_off_outlined);
  }

  Future<void> _openInNewTab(String url, {bool incognito = false}) async {
    if (!isAvenWebUrl(url)) return;
    setState(() {
      _tabs.add(
        _PageTab()
          ..incognito = incognito
          ..title = incognito ? avenText('aven_private_tab') : avenText('aven_new_tab')
          ..url = url,
      );
      _tabIndex = _tabs.length - 1;
      _phoneTabsOpen = false;
    });
    await _controller.setPrivate(incognito);
    await _openInput(url);
  }

  /// Long-press "open in new tab": the tab waits in the background, like
  /// other browsers, and the bar offers to switch to it.
  void _openInBackground(String url) {
    if (!isAvenWebUrl(url)) return;
    final host = Uri.tryParse(url)?.host ?? url;
    final tab = _PageTab()
      ..url = url
      ..title = host;
    setState(() => _tabs.add(tab));
    unawaited(_persistTabs());
    _notify(
      avenText('aven_opened_new_tab'),
      icon: Icons.tab_outlined,
      action: avenText('aven_switch'),
      onAction: () {
        final index = _tabs.indexOf(tab);
        if (index >= 0) _selectTab(index);
      },
    );
  }

  Future<void> _showContextMenu(Map<String, String> info) async {
    if (!mounted || !AvenFlavor.isMobile) return;
    final link = info['link'] ?? '';
    final src = info['src'] ?? '';
    final title = (info['title'] ?? '').trim();
    final hasLink = isAvenWebUrl(link);
    final hasImage = isAvenWebUrl(src);
    if (!hasLink && !hasImage) return;
    final target = hasLink ? link : src;
    final host = Uri.tryParse(target)?.host ?? target;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AvenTone.background(context),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        Future<void> go(Future<void> Function() action) async {
          Navigator.pop(context);
          await action();
        }

        Widget row(IconData icon, String label, Future<void> Function() action) {
          return InkWell(
            onTap: () => unawaited(go(action)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Icon(icon, size: 22, color: AvenTone.text(context)),
                  const SizedBox(width: 18),
                  Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // What was pressed: the image itself, or the link's site.
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: hasImage
                            ? Image.network(
                                src,
                                fit: BoxFit.cover,
                                cacheWidth: 156,
                                errorBuilder: (context, error, stack) => ColoredBox(
                                  color: AvenTone.elevated(context),
                                  child: const Icon(Icons.image_outlined),
                                ),
                              )
                            : ColoredBox(
                                color: AvenTone.elevated(context),
                                child: Center(child: _SiteIcon(url: link, size: 26)),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.isEmpty ? host : title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            target,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: AvenTone.textMuted(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (hasLink) ...[
                  const SizedBox(height: 18),
                  GridView.count(
                    crossAxisCount: 5,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 4,
                    childAspectRatio: 0.7,
                    children: [
                      _MenuTile(
                        icon: Icons.tab_outlined,
                        label: avenText('aven_open_new_tab'),
                        onTap: () => unawaited(go(() async => _openInBackground(link))),
                      ),
                      _MenuTile(
                        icon: Icons.visibility_off_outlined,
                        label: avenText('aven_private'),
                        onTap: () => unawaited(go(() => _openInNewTab(link, incognito: true))),
                      ),
                      _MenuTile(
                        icon: Icons.link,
                        label: avenText('aven_copy_link'),
                        onTap: () => unawaited(go(() async {
                          await Clipboard.setData(ClipboardData(text: link));
                          _notify(avenText('aven_link_copied'), icon: Icons.link);
                        })),
                      ),
                      _MenuTile(
                        icon: Icons.share_outlined,
                        label: avenText('aven_share'),
                        onTap: () => unawaited(go(() => WebInput.share(link))),
                      ),
                      _MenuTile(
                        icon: Icons.connected_tv,
                        label: avenText('aven_cast_short'),
                        onTap: () => unawaited(go(() => _shareWithTv(link: link))),
                      ),
                    ],
                  ),
                ],
                if (hasImage) ...[
                  const SizedBox(height: 12),
                  _MenuCard(
                    children: [
                      row(Icons.image_outlined, avenText('aven_open_image'),
                          () async => _openInBackground(src)),
                      row(Icons.download_outlined, avenText('aven_save_image'),
                          () => WebInput.saveUrl(src)),
                      row(Icons.copy, avenText('aven_copy_image'), () async {
                        await Clipboard.setData(ClipboardData(text: src));
                        _notify(avenText('aven_link_copied'), icon: Icons.link);
                      }),
                    ],
                  ),
                ],
              ],
            ),
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
          content: Text(avenText('aven_perm_wants', [host, label]), style: TextStyle(color: ink)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(avenText('aven_block')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(avenText('aven_allow')),
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
    if (_onStart) return;
    final info = await WebInput.pageSecurity();
    if (!mounted) return;
    final mode = info['mode'] ?? _connection;
    final host = info['host']?.isNotEmpty == true
        ? info['host']!
        : Uri.tryParse(_pageUrl ?? '')?.host ?? '';
    final headline = switch (mode) {
      'secure' => avenText('aven_secure'),
      'warning' => avenText('aven_warning'),
      'insecure' => avenText('aven_insecure'),
      _ => avenText('aven_security_unknown'),
    };
    final detail = switch (mode) {
      'secure' => avenText('aven_secure_detail'),
      'warning' => avenText('aven_warning_detail'),
      'insecure' => avenText('aven_insecure_detail'),
      _ => avenText('aven_security_unknown_detail'),
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
                Text(avenText('aven_certificate'), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(avenText('aven_cert_subject', [subject])),
                if (issuer.isNotEmpty) Text(avenText('aven_cert_issuer', [issuer])),
                if ((info['validFrom'] ?? '').isNotEmpty)
                  Text(avenText('aven_cert_from', [info['validFrom']!])),
                if ((info['validTo'] ?? '').isNotEmpty)
                  Text(avenText('aven_cert_to', [info['validTo']!])),
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
    final host = _onStart ? '' : (Uri.tryParse(_pageUrl ?? '')?.host ?? '');
    final items = <Map<String, String>>[
      if (host.isNotEmpty)
        for (final id in const ['location', 'camera', 'microphone'])
          {'id': id, 'value': await _store.loadSitePermission(host, id), 'fallback': 'ask'},
    ];
    if (!mounted) return;
    final secure = _connection == 'secure';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AvenTone.background(context),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final ink = AvenTone.text(context);
        final muted = AvenTone.textMuted(context);
        if (host.isEmpty) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune, size: 36, color: muted),
                  const SizedBox(height: 12),
                  Text(avenText('aven_site_settings_empty'), textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        }
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AvenTone.elevated(context),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(child: _SiteIcon(url: _pageUrl, size: 26)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            host,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          // Connection state; opens the certificate details.
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              Navigator.pop(context);
                              unawaited(_showSecurity());
                            },
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
                              decoration: BoxDecoration(
                                color: (secure ? const Color(0xFF1E8E3E) : AvenColors.live)
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    secure ? Icons.lock : Icons.lock_open,
                                    size: 15,
                                    color: secure ? const Color(0xFF1E8E3E) : AvenColors.live,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    avenText(secure ? 'aven_secure' : 'aven_insecure'),
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink),
                                  ),
                                  Icon(Icons.chevron_right, size: 16, color: muted),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    avenText('aven_site_settings'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: muted),
                  ),
                ),
                _MenuCard(
                  children: [
                    for (final item in items)
                      _SitePermRow(
                        id: item['id'] ?? '',
                        label: permissionLabel(item['id'] ?? ''),
                        value: item['value'] ?? 'ask',
                        fallback: item['fallback'] ?? 'ask',
                        onChanged: (value) =>
                            unawaited(_store.saveSitePermission(host, item['id'] ?? '', value)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// A download opened straight from the start screen leaves an empty page;
  /// go back to where the viewer was instead.
  Future<void> _leaveDownloadPage(String url) async {
    if (!mounted || _onStart) return;
    if (_pageUrl != null && _pageUrl != url && isAvenWebUrl(_pageUrl)) return;
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else if (mounted) {
      _showStart();
    }
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

  /// Sends the page (or its playing video) to an Aven TV; [link] sends that
  /// link instead, from the long-press menu.
  Future<void> _shareWithTv({String? link}) async {
    final media = link == null ? _castMediaUrl : null;
    final play = media != null && _isStreamUrl(media);
    final url = link ?? (play ? media : _pageUrl);
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
    _notify(
      ok ? avenText('aven_cast_sent') : avenText('aven_cast_unreachable'),
      icon: ok ? Icons.connected_tv : Icons.tv_off_outlined,
    );
  }

  Future<void> _sharePage() async {
    final url = _pageUrl;
    if (url == null || url.isEmpty) return;
    final title = _pageTitle?.trim() ?? '';
    final text = title.isEmpty ? url : '$title\n$url';
    await WebInput.share(text);
  }

  void _selectTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs[index];
    setState(() => _tabIndex = index);
    unawaited(_persistTabs());
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
    _offerUndo(_rememberClosed([_tabs[index]]));
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
    unawaited(_persistTabs());
  }

  Future<void> _handleBack() async {
    // One remote press can arrive both as a key and as a system back.
    final now = DateTime.now();
    if (now.difference(_lastBack) < const Duration(milliseconds: 400)) return;
    if (_exitDialogOpen) return;
    _lastBack = now;
    if (AvenFlavor.isMobile) {
      if (_fullscreenVideo != null) {
        final exit = _exitFullscreen;
        setState(() {
          _fullscreenVideo = null;
          _exitFullscreen = null;
        });
        exit?.call();
        _onPageFullscreen(false);
        return;
      }
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

  /// Phone toolbar; it floats over the bottom of the page (see build).
  Widget _phoneBar() {
    return _PhoneTopBar(
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
                onTabs: () => unawaited(_openTabGrid()),
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
                  _addressFocus.unfocus();
                  setState(() => _findOpen = true);
                  // The menu sheet hands focus back as it closes; take it after that.
                  Future<void>.delayed(const Duration(milliseconds: 300), () {
                    if (mounted && _findOpen) _findFocus.requestFocus();
                  });
                },
                onDownloads: () => unawaited(_openLibrary(section: 2)),
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
                onReadLater: () => unawaited(_readLater()),
                onRemote: () => unawaited(_openTvRemote()),
              );
  }

  @override
  void dispose() {
    _downloadPoll?.cancel();
    _pull.dispose();
    _findFocus.dispose();
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
    _previewTimer?.cancel();
    _address.removeListener(_onAddressEdited);
    _findText.dispose();
    _address.dispose();
    _addressFocus.dispose();
    _startFocus.dispose();
    _surfaceFocus.dispose();
    _menuFocus.dispose();
    _menuVoiceFocus.dispose();
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
                closed: _closedTabs,
                onReopen: (index) {
                  if (index < 0 || index >= _closedTabs.length) return;
                  setState(() => _phoneTabsOpen = false);
                  _reopenClosed([_closedTabs[index]]);
                },
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
                showBookmarks: _homeBookmarks,
                onRemoveHistory: (url) => unawaited(() async {
                  final before = _history;
                  final removed = before.where((item) => item.url == url).toList();
                  final next = await _store.removeHistory(url);
                  if (!mounted) return;
                  setState(() => _history = next);
                  _notify(
                    avenText('aven_recent_removed'),
                    icon: Icons.history,
                    action: avenText('aven_undo'),
                    onAction: () => unawaited(() async {
                      for (final item in removed.reversed) {
                        await _store.addHistory(item);
                      }
                      final restored = await _store.loadHistory();
                      if (mounted) setState(() => _history = restored);
                    }()),
                  );
                }()),
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
                watching: _watching,
                onResume: (entry) => unawaited(_openInput(entry.page ?? entry.key)),
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
                onReadLater: () => unawaited(_readLater()),
                onLibrary: _openLibrary,
                onToggleAdBlock: _toggleAdBlock,
                onToggleReader: () => unawaited(_toggleReader()),
                onZoomOut: () => _setZoom(_zoom - 10),
                onZoomIn: () => _setZoom(_zoom + 10),
                onZoomReset: () => _setZoom(100),
                onSettings: _openSettings,
                onExit: _confirmExit,
                voiceFocus: _menuVoiceFocus,
                voiceBusy: _voiceBusy,
                onVoice: () => unawaited(_voiceSearch()),
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
            // The remote cursor over fullscreen video is a TV thing.
            if (_fullscreenVideo != null && !AvenFlavor.isMobile)
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
                  if (!AvenFlavor.isMobile || _pageFullscreen) return page;
                  return SafeArea(
                    bottom: false,
                    child: ListenableBuilder(
                    listenable: Listenable.merge([_startFocus, _addressFocus, _address]),
                    builder: (context, _) {
                  // Start screen: the search bar sits in the middle; on a page it moves up.
                  final atTop = !_onStart;
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final barsAway = atTop && _barsHidden;
                      final fieldAway = barsAway || (atTop && _addressTucked);
                      final fieldTop = atTop
                          ? (fieldAway ? -68.0 : 4.0)
                          : _phoneSearchTop(constraints.maxHeight);
                      // Both bars float over the page: it fills the screen under
                      // them and does not reflow as they slide away.
                      return Stack(
                        children: [
                          Padding(
                            // The page stops above the system navigation bar.
                            padding: EdgeInsets.only(
                              bottom: MediaQuery.viewPaddingOf(context).bottom,
                            ),
                            child: page,
                          ),
                          if (!_onStart)
                            ValueListenableBuilder<double>(
                              valueListenable: _pull,
                              builder: (context, pull, _) {
                                if (pull <= 0 && !_pullRefreshing) return const SizedBox.shrink();
                                final shown = _pullRefreshing ? 1.0 : pull.clamp(0.0, 1.2);
                                return Positioned(
                                  top: (fieldAway ? 8 : 68) + 44 * shown,
                                  left: 0,
                                  right: 0,
                                  child: IgnorePointer(
                                    child: Center(
                                      child: Material(
                                        elevation: 3,
                                        shape: const CircleBorder(),
                                        color: AvenTone.elevated(context),
                                        child: Padding(
                                          padding: const EdgeInsets.all(9),
                                          child: SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.4,
                                              value: _pullRefreshing ? null : shown.clamp(0.0, 1.0),
                                              color: AvenTone.text(context),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
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
                              onHide: _onStart
                                  ? null
                                  : () {
                                      _addressFocus.unfocus();
                                      setState(() => _addressTucked = true);
                                    },
                            ),
                          ),
                          // Floating toolbar: slides off the bottom while a page scrolls
                          // down or the keyboard is up; the find bar replaces it.
                          if (!_findOpen)
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              left: 12,
                              right: 12,
                              bottom: (_barsHidden && !_onStart) ||
                                      MediaQuery.viewInsetsOf(context).bottom > 0
                                  ? -96
                                  : 12 + MediaQuery.viewPaddingOf(context).bottom,
                              child: _phoneBar(),
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
                                            avenText('aven_recent_opened'),
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
            if (AvenFlavor.isMobile && !_pageFullscreen && _toastDownload != null)
              _DownloadToast(
                item: _toastDownload!,
                onOpen: () {
                  final id = _toastDownload?['id'] ?? '';
                  if (id.isEmpty) return;
                  unawaited(WebInput.openDownload(id));
                  setState(() => _toastHoldId = null);
                },
                onCancel: () {
                  final id = _toastDownload?['id'] ?? '';
                  if (id.isEmpty) return;
                  unawaited(WebInput.removeDownload(id));
                },
                onDismiss: () => setState(() => _toastHoldId = null),
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
                          focusNode: _findFocus,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: avenText('aven_find'),
                            isDense: true,
                            border: InputBorder.none,
                          ),
                          onChanged: (value) => unawaited(_applyFind(value)),
                        ),
                      ),
                      if (_findText.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            '$_findCurrent/$_findTotal',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AvenTone.textMuted(context),
                            ),
                          ),
                        ),
                      IconButton(
                        onPressed: () => unawaited(_applyFind(_findText.text, forward: false)),
                        icon: const Icon(Icons.keyboard_arrow_up),
                        tooltip: avenText('aven_find_previous'),
                      ),
                      IconButton(
                        onPressed: () => unawaited(_applyFind(_findText.text)),
                        icon: const Icon(Icons.keyboard_arrow_down),
                        tooltip: avenText('aven_find_next'),
                      ),
                      IconButton(
                        onPressed: () {
                          unawaited(_controller.clearFind());
                          setState(() {
                            _findOpen = false;
                            _findCurrent = 0;
                            _findTotal = 0;
                          });
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
