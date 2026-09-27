part of '../browser_page.dart';

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

/// Leaves the search field and moves focus down (overrides TextField arrows).
class _SearchLeaveDownIntent extends Intent {
  const _SearchLeaveDownIntent();
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
    this.menuOpen = false,
  });

  final _PageError error;
  final VoidCallback onRetry;
  final VoidCallback onHome;
  final bool menuOpen;

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

  @override
  void didUpdateWidget(covariant _PageErrorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.menuOpen && !oldWidget.menuOpen) {
      _focusGuard?.cancel();
      _retryFocus.unfocus();
      _homeFocus.unfocus();
    } else if (!widget.menuOpen && oldWidget.menuOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _claimFocus());
    }
  }

  void _onFocusChanged() {
    if (widget.menuOpen) return;
    if (_retryFocus.hasFocus || _homeFocus.hasFocus) {
      _focusGuard?.cancel();
      return;
    }
    _focusGuard?.cancel();
    _focusGuard = Timer(const Duration(milliseconds: 80), _claimFocus);
  }

  void _claimFocus() {
    if (!mounted || widget.menuOpen) return;
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
    return ExcludeFocus(
      excluding: widget.menuOpen,
      child: FocusScope(
        canRequestFocus: !widget.menuOpen,
        autofocus: !widget.menuOpen,
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
          borderRadius: BorderRadius.circular(scrolling ? 10 : 16),
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
            : Icon(_icon, size: 22, color: AvenColors.text),
      ),
    );
  }
}

class _StartPage extends StatefulWidget {
  const _StartPage({
    required this.address,
    required this.focusNode,
    required this.editing,
    required this.engine,
    required this.bookmarks,
    required this.history,
    required this.showSuggestions,
    required this.onTapField,
    required this.onLeaveField,
    required this.onSubmit,
    required this.onOpenBookmark,
    required this.onOpenBookmarks,
    required this.onOpenHistory,
    required this.onSettings,
  });

  final TextEditingController address;
  final FocusNode focusNode;
  final bool editing;
  final SearchEngine engine;
  final List<WebLink> bookmarks;
  final List<WebLink> history;
  final bool showSuggestions;
  final VoidCallback onTapField;
  final VoidCallback onLeaveField;
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
  static const _suggestLimit = 8;
  static const _suggestions = <_Suggestion>[
    _Suggestion(
      title: 'IMDb',
      url: 'https://www.imdb.com/',
      logo: 'assets/suggestions/imdb.svg',
    ),
    _Suggestion(
      title: 'SofaScore',
      url: 'https://www.sofascore.com/',
      logo: 'assets/suggestions/sofascore.svg',
    ),
    _Suggestion(
      title: 'Wikipedia',
      url: 'https://www.wikipedia.org/',
      logo: 'assets/suggestions/wikipedia.svg',
    ),
    _Suggestion(
      title: 'Google News',
      url: 'https://news.google.com/',
      logo: 'assets/suggestions/googlenews.svg',
    ),
    _Suggestion(
      title: 'The Weather Channel',
      url: 'https://weather.com/',
      logo: 'assets/suggestions/weather.svg',
    ),
  ];

  late final List<FocusNode> _suggestFocus =
      List.generate(_suggestions.length, (_) => FocusNode());
  late final List<FocusNode> _bookmarkFocus =
      List.generate(_bookmarkLimit, (_) => FocusNode());
  late final List<FocusNode> _actionFocus = List.generate(3, (_) => FocusNode());
  late final List<FocusNode> _queryFocus =
      List.generate(_suggestLimit, (_) => FocusNode());
  final _voiceFocus = FocusNode();
  late final Listenable _suggestRailListenable = Listenable.merge(_suggestFocus);
  late final Listenable _bookmarkRailListenable =
      Listenable.merge(_bookmarkFocus);
  final _pageScroll = ScrollController();
  final _suggestScroll = ScrollController();
  final _bookmarkScroll = ScrollController();

  static const _suggestItemWidth = 220.0;
  static const _suggestGap = 14.0;

  List<SearchSuggestion> _querySuggestions = const [];
  Timer? _suggestDebounce;
  int _suggestEpoch = 0;
  String _lastSuggestQuery = '';
  bool _voiceBusy = false;

  @override
  void initState() {
    super.initState();
    widget.address.addListener(_onAddressChanged);
    for (var i = 0; i < _suggestFocus.length; i++) {
      final index = i;
      _suggestFocus[index].addListener(() {
        if (_suggestFocus[index].hasFocus) {
          _scrollSuggestTo(index);
        }
      });
    }
    for (var i = 0; i < _bookmarkFocus.length; i++) {
      final index = i;
      _bookmarkFocus[index].addListener(() {
        if (_bookmarkFocus[index].hasFocus) {
          _scrollBookmarkTo(index);
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
  void didUpdateWidget(covariant _StartPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.address != widget.address) {
      oldWidget.address.removeListener(_onAddressChanged);
      widget.address.addListener(_onAddressChanged);
    }
    if (!widget.editing && _querySuggestions.isNotEmpty) {
      // Keep suggestions while the field still has text; clear only when empty.
      if (widget.address.text.trim().length < 2) {
        _clearQuerySuggestions();
      }
    }
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    widget.address.removeListener(_onAddressChanged);
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
    for (final node in _queryFocus) {
      node.dispose();
    }
    _voiceFocus.dispose();
    super.dispose();
  }

  void _clearQuerySuggestions() {
    _suggestDebounce?.cancel();
    _suggestEpoch++;
    _lastSuggestQuery = '';
    if (_querySuggestions.isEmpty) return;
    setState(() => _querySuggestions = const []);
  }

  void _onAddressChanged() {
    final text = widget.address.text.trim();
    if (text.length < 2) {
      _clearQuerySuggestions();
      return;
    }
    _suggestDebounce?.cancel();
    _suggestDebounce = Timer(const Duration(milliseconds: 220), () {
      unawaited(_loadQuerySuggestions(text));
    });
  }

  Future<void> _loadQuerySuggestions(String query) async {
    if (!mounted || query != widget.address.text.trim()) return;
    if (query == _lastSuggestQuery && _querySuggestions.isNotEmpty) return;
    final epoch = ++_suggestEpoch;
    final links = (
      history: [
        for (final item in widget.history) (title: item.title, url: item.url),
      ],
      bookmarks: [
        for (final item in widget.bookmarks) (title: item.title, url: item.url),
      ],
    );
    final next = await buildAddressSuggestions(
      query,
      engine: widget.engine,
      history: links.history,
      bookmarks: links.bookmarks,
      limit: _suggestLimit,
    );
    if (!mounted || epoch != _suggestEpoch) return;
    if (query != widget.address.text.trim()) return;
    setState(() {
      _lastSuggestQuery = query;
      _querySuggestions = next;
    });
  }

  void _pickSuggestion(SearchSuggestion item) {
    widget.onSubmit(item.query);
  }

  void _ensureVisible(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = node.context;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.45,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  void _scrollSuggestTo(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_suggestScroll.hasClients) return;
      final extent = _suggestItemWidth + _suggestGap;
      final viewport = _suggestScroll.position.viewportDimension;
      final ideal = index * extent - (viewport - _suggestItemWidth) * 0.35;
      final target =
          ideal.clamp(0.0, _suggestScroll.position.maxScrollExtent);
      _suggestScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _scrollBookmarkTo(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_bookmarkScroll.hasClients) return;
      final extent = _suggestItemWidth + _suggestGap;
      final viewport = _bookmarkScroll.position.viewportDimension;
      final ideal = index * extent - (viewport - _suggestItemWidth) * 0.35;
      final target =
          ideal.clamp(0.0, _bookmarkScroll.position.maxScrollExtent);
      _bookmarkScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  static _Suggestion? _matchSuggestion(String url) {
    final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
    if (host.isEmpty) return null;
    bool hits(String needle) =>
        host == needle || host.endsWith('.$needle') || host.contains(needle);

    if (hits('imdb.com')) {
      return _suggestions.firstWhere((s) => s.title == 'IMDb');
    }
    if (hits('sofascore.com')) {
      return _suggestions.firstWhere((s) => s.title == 'SofaScore');
    }
    if (hits('wikipedia.org') || hits('wikipedia.com')) {
      return _suggestions.firstWhere((s) => s.title == 'Wikipedia');
    }
    if (hits('news.google.com') || host.contains('news.google')) {
      return _suggestions.firstWhere((s) => s.title == 'Google News');
    }
    if (hits('weather.com') || hits('theweatherchannel.com')) {
      return _suggestions.firstWhere((s) => s.title == 'The Weather Channel');
    }
    return null;
  }

  int get _bookmarkCount => widget.bookmarks.length.clamp(0, _bookmarkLimit);
  bool get _hasQuerySuggests => _querySuggestions.isNotEmpty;
  bool get _showSiteRail => widget.showSuggestions && !_hasQuerySuggests;

  void _leaveAddressField() {
    widget.onLeaveField();
    try {
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } catch (_) {}
  }

  void _requestNode(FocusNode node, {int attempt = 0}) {
    if (!mounted) return;
    if (node.context == null) {
      if (attempt >= 4) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _requestNode(node, attempt: attempt + 1);
      });
      return;
    }
    node.requestFocus();
    _ensureVisible(node);
  }

  /// Search → query list (if any) → action row.
  void _focusAfterSearch({bool afterRebuild = false}) {
    _leaveAddressField();
    void move() {
      if (!mounted) return;
      if (_hasQuerySuggests) {
        _requestNode(_queryFocus.first);
        return;
      }
      _requestNode(_actionFocus.first);
    }

    if (afterRebuild || widget.editing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => move());
    } else {
      move();
    }
  }

  /// Actions → site suggestions (if enabled) → bookmarks.
  void _focusAfterActions() {
    if (!mounted) return;
    if (widget.showSuggestions && !_hasQuerySuggests) {
      if (_suggestScroll.hasClients) _suggestScroll.jumpTo(0);
      _requestNode(_suggestFocus.first);
      return;
    }
    if (_bookmarkCount > 0) {
      if (_bookmarkScroll.hasClients) _bookmarkScroll.jumpTo(0);
      _requestNode(_bookmarkFocus.first);
    }
  }

  void _focusAboveSiteRail() {
    _requestNode(_actionFocus.first);
  }

  Future<void> _startVoiceSearch() async {
    if (_voiceBusy) return;
    setState(() => _voiceBusy = true);
    try {
      final spoken = await WebInput().recognizeSpeech();
      if (!mounted) return;
      final text = spoken?.trim() ?? '';
      if (text.isEmpty) return;
      widget.address.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      widget.onSubmit(text);
    } on PlatformException {
      // Emulator / TV without a speech service — keep silent.
    } catch (_) {
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  void _onVoiceKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _requestNode(widget.focusNode);
      return;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _focusAfterSearch();
      return;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp) {
      return;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space) {
      unawaited(_startVoiceSearch());
    }
  }

  void _onQueryKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    final count = _querySuggestions.length;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (index < count - 1) {
        _requestNode(_queryFocus[index + 1]);
      } else {
        _requestNode(_actionFocus.first);
      }
      return;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        _requestNode(_queryFocus[index - 1]);
      } else {
        _requestNode(widget.focusNode);
      }
      return;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space) {
      _pickSuggestion(_querySuggestions[index]);
    }
  }

  void _onSuggestKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight && index < _suggestions.length - 1) {
      _requestNode(_suggestFocus[index + 1]);
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft && index > 0) {
      _requestNode(_suggestFocus[index - 1]);
      return;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _focusAboveSiteRail();
      return;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_bookmarkCount > 0) {
        _requestNode(_bookmarkFocus.first);
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
      _requestNode(_bookmarkFocus[index + 1]);
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft && index > 0) {
      _requestNode(_bookmarkFocus[index - 1]);
      return;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (widget.showSuggestions) {
        _requestNode(_suggestFocus.first);
      } else {
        _focusAboveSiteRail();
      }
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
      _requestNode(_actionFocus[index + 1]);
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft && index > 0) {
      _requestNode(_actionFocus[index - 1]);
      return;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (_hasQuerySuggests) {
        _requestNode(_queryFocus[_querySuggestions.length - 1]);
      } else {
        _requestNode(widget.focusNode);
      }
      return;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (!_hasQuerySuggests &&
          (widget.showSuggestions || _bookmarkCount > 0)) {
        _focusAfterActions();
      }
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

  IconData _sourceIcon(SuggestionSource source) {
    return switch (source) {
      SuggestionSource.remote => Icons.search,
      SuggestionSource.history => Icons.history,
      SuggestionSource.bookmark => Icons.star_outline,
    };
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks = widget.bookmarks.take(_bookmarkLimit).toList();
    final showQuery = _hasQuerySuggests;
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: ColoredBox(
        color: AvenColors.background,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              controller: _pageScroll,
              physics: const ClampingScrollPhysics(),
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
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: _StartSearchField(
                                      controller: widget.address,
                                      focusNode: widget.focusNode,
                                      editing: widget.editing,
                                      onTap: widget.onTapField,
                                      onLeave: widget.onLeaveField,
                                      onSubmit: widget.onSubmit,
                                      onArrowDown: _focusAfterSearch,
                                      onArrowRight: () =>
                                          _requestNode(_voiceFocus),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  FocusTraversalOrder(
                                    order: const NumericFocusOrder(0.05),
                                    child: _VoiceSearchButton(
                                      focusNode: _voiceFocus,
                                      busy: _voiceBusy,
                                      onPressed: () =>
                                          unawaited(_startVoiceSearch()),
                                      onKeyEvent: _onVoiceKey,
                                    ),
                                  ),
                                ],
                              ),
                              if (showQuery) ...[
                                const SizedBox(height: 8),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: AvenColors.text.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AvenColors.text.withValues(alpha: 0.12),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      for (var i = 0; i < _querySuggestions.length; i++)
                                        FocusTraversalOrder(
                                          order: NumericFocusOrder(0.1 + i * 0.01),
                                          child: _QuerySuggestTile(
                                            suggestion: _querySuggestions[i],
                                            focusNode: _queryFocus[i],
                                            icon: _sourceIcon(_querySuggestions[i].source),
                                            onKeyEvent: (event) => _onQueryKey(i, event),
                                            onPressed: () =>
                                                _pickSuggestion(_querySuggestions[i]),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
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
                    if (!showQuery) ...[
                      if (_showSiteRail) ...[
                        const SizedBox(height: 22),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Öneriler',
                            style: TextStyle(
                              fontSize: 16,
                              color: AvenColors.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 168,
                          child: SingleChildScrollView(
                            controller: _suggestScroll,
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(0, 14, 48, 14),
                            child: Row(
                              children: [
                                for (var index = 0;
                                    index < _suggestions.length;
                                    index++) ...[
                                  if (index > 0)
                                    const SizedBox(width: _suggestGap),
                                  RepaintBoundary(
                                    child: FocusTraversalOrder(
                                      order: NumericFocusOrder(
                                        10 + index.toDouble(),
                                      ),
                                      child: _SuggestionPoster(
                                        suggestion: _suggestions[index],
                                        focusNode: _suggestFocus[index],
                                        railListenable: _suggestRailListenable,
                                        railNodes: _suggestFocus,
                                        onKeyEvent: (event) =>
                                            _onSuggestKey(index, event),
                                        onPressed: () => widget.onOpenBookmark(
                                          _suggestions[index].url,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
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
                          height: 168,
                          child: SingleChildScrollView(
                            controller: _bookmarkScroll,
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(0, 14, 48, 14),
                            child: Row(
                              children: [
                                for (var index = 0;
                                    index < bookmarks.length;
                                    index++) ...[
                                  if (index > 0)
                                    const SizedBox(width: _suggestGap),
                                  RepaintBoundary(
                                    child: FocusTraversalOrder(
                                      order: NumericFocusOrder(
                                        40 + index.toDouble(),
                                      ),
                                      child: _BookmarkPoster(
                                        link: bookmarks[index],
                                        matched: _matchSuggestion(
                                          bookmarks[index].url,
                                        ),
                                        focusNode: _bookmarkFocus[index],
                                        railListenable:
                                            _bookmarkRailListenable,
                                        railNodes: _bookmarkFocus,
                                        railNodeCount: bookmarks.length,
                                        onKeyEvent: (event) =>
                                            _onBookmarkKey(index, event),
                                        onPressed: () => widget.onOpenBookmark(
                                          bookmarks[index].url,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
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

class _QuerySuggestTile extends StatelessWidget {
  const _QuerySuggestTile({
    required this.suggestion,
    required this.focusNode,
    required this.icon,
    required this.onKeyEvent,
    required this.onPressed,
  });

  final SearchSuggestion suggestion;
  final FocusNode focusNode;
  final IconData icon;
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
          return Material(
            color: focused
                ? AvenColors.focus.withValues(alpha: 0.55)
                : Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: AvenColors.textMuted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        suggestion.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: focused ? FontWeight.w600 : FontWeight.w500,
                          color: AvenColors.text,
                        ),
                      ),
                    ),
                    if (suggestion.isUrl)
                      const Icon(Icons.north_east, size: 16, color: AvenColors.textMuted),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Suggestion {
  const _Suggestion({
    required this.title,
    required this.url,
    required this.logo,
  });

  final String title;
  final String url;
  final String logo;

  static const faceBackground = Color(0xFF000000);
}

class _SuggestionPoster extends StatelessWidget {
  const _SuggestionPoster({
    required this.suggestion,
    required this.focusNode,
    required this.railListenable,
    required this.railNodes,
    required this.onKeyEvent,
    required this.onPressed,
  });

  final _Suggestion suggestion;
  final FocusNode focusNode;
  final Listenable railListenable;
  final List<FocusNode> railNodes;
  final ValueChanged<KeyEvent> onKeyEvent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final face = _SuggestionLogo(
      suggestion: suggestion,
    );
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
        listenable: railListenable,
        child: face,
        builder: (context, child) {
          final focused = focusNode.hasFocus;
          final railActive = railNodes.any((node) => node.hasFocus);
          final dimmed = railActive && !focused;
          return AnimatedScale(
            scale: focused ? 1.08 : 1,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: dimmed ? 0.34 : 1,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: 220,
                height: 128,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: focused
                        ? AvenColors.text.withValues(alpha: 0.92)
                        : Colors.transparent,
                    width: focused ? 3 : 0,
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: AvenColors.text.withValues(alpha: 0.18),
                            blurRadius: 18,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onPressed,
                    borderRadius: BorderRadius.circular(14),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(focused ? 11 : 14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: _Suggestion.faceBackground),
                          child!,
                          if (dimmed)
                            ColoredBox(
                              color: AvenColors.background.withValues(alpha: 0.45),
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

class _SuggestionLogo extends StatelessWidget {
  const _SuggestionLogo({required this.suggestion});

  final _Suggestion suggestion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: SvgPicture.asset(
                suggestion.logo,
                fit: BoxFit.contain,
                // Keep brand fills from the SVG (no tint).
                placeholderBuilder: (_) => const Icon(
                  Icons.public,
                  size: 36,
                  color: AvenColors.text,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                suggestion.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  fontFamily: 'sans-serif',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                  color: AvenColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookmarkPoster extends StatelessWidget {
  const _BookmarkPoster({
    required this.link,
    required this.matched,
    required this.focusNode,
    required this.railListenable,
    required this.railNodes,
    required this.railNodeCount,
    required this.onKeyEvent,
    required this.onPressed,
  });

  final WebLink link;
  final _Suggestion? matched;
  final FocusNode focusNode;
  final Listenable railListenable;
  final List<FocusNode> railNodes;
  final int railNodeCount;
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
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final Widget face;
    if (suggestion != null) {
      face = Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: _Suggestion.faceBackground),
          _SuggestionLogo(suggestion: suggestion),
        ],
      );
    } else {
      final bg = _fallbackBg;
      face = Stack(
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
                filterQuality: FilterQuality.low,
                cacheWidth: (56 * dpr).round().clamp(56, 168),
                cacheHeight: (56 * dpr).round().clamp(56, 168),
                gaplessPlayback: true,
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
      );
    }
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
        listenable: railListenable,
        child: face,
        builder: (context, child) {
          final focused = focusNode.hasFocus;
          final railActive = railNodes
              .take(railNodeCount)
              .any((node) => node.hasFocus);
          final dimmed = railActive && !focused;
          return AnimatedScale(
            scale: focused ? 1.08 : 1,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: dimmed ? 0.34 : 1,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: 220,
                height: 128,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: focused
                        ? AvenColors.text.withValues(alpha: 0.92)
                        : Colors.transparent,
                    width: focused ? 3 : 0,
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: AvenColors.text.withValues(alpha: 0.18),
                            blurRadius: 18,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onPressed,
                    borderRadius: BorderRadius.circular(14),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(focused ? 11 : 14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          child!,
                          if (dimmed)
                            ColoredBox(
                              color: AvenColors.background.withValues(alpha: 0.45),
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
    required this.readerOn,
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
    required this.onToggleReader,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onZoomReset,
    required this.onSettings,
    required this.onExit,
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
  final bool readerOn;
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
  final VoidCallback onToggleReader;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomReset;
  final VoidCallback onSettings;
  final VoidCallback onExit;

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
                        readerOn: readerOn,
                        zoom: zoom,
                        onBack: onBack,
                        onForward: onForward,
                        onReload: onReload,
                        onHome: onHome,
                        onBookmark: onBookmark,
                        onLibrary: onLibrary,
                        onToggleAdBlock: onToggleAdBlock,
                        onToggleReader: onToggleReader,
                        onZoomOut: onZoomOut,
                        onZoomIn: onZoomIn,
                        onZoomReset: onZoomReset,
                        onSettings: onSettings,
                        onExit: onExit,
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

class _StartSearchField extends StatefulWidget {
  const _StartSearchField({
    required this.controller,
    required this.focusNode,
    required this.editing,
    required this.onTap,
    required this.onLeave,
    required this.onSubmit,
    required this.onArrowDown,
    this.onArrowRight,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool editing;
  final VoidCallback onTap;
  final VoidCallback onLeave;
  final ValueChanged<String> onSubmit;
  final VoidCallback onArrowDown;
  final VoidCallback? onArrowRight;

  @override
  State<_StartSearchField> createState() => _StartSearchFieldState();
}

class _StartSearchFieldState extends State<_StartSearchField> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.onKeyEvent = _onKey;
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _StartSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.onKeyEvent = null;
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.onKeyEvent = _onKey;
      widget.focusNode.addListener(_onFocusChanged);
    }
    if (widget.editing && !oldWidget.editing) {
      unawaited(_openKeyboard());
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    if (widget.focusNode.onKeyEvent == _onKey) {
      widget.focusNode.onKeyEvent = null;
    }
    super.dispose();
  }

  void _onFocusChanged() {
    if (widget.editing && widget.focusNode.hasFocus) {
      unawaited(_openKeyboard());
    }
  }

  Future<void> _openKeyboard() async {
    // Keep the same TextField mounted (readOnly flip) so the input connection
    // stays alive — recreating the field is what made TV IME fail before.
    for (final delay in const [16, 80, 200]) {
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (!mounted || !widget.editing) return;
      if (!widget.focusNode.hasFocus) widget.focusNode.requestFocus();
      try {
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      } catch (_) {}
      try {
        await WebInput().showKeyboard();
      } catch (_) {}
    }
  }

  void _beginEditing() {
    if (!widget.editing) widget.onTap();
    widget.focusNode.requestFocus();
    unawaited(_openKeyboard());
  }

  void _leaveEditing() {
    widget.onLeave();
    try {
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } catch (_) {}
    try {
      WebInput().showKeyboard(); // no-op if already typing; hide via TextInput
    } catch (_) {}
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (widget.editing) {
      if (key == LogicalKeyboardKey.arrowDown) {
        _leaveEditing();
        widget.onArrowDown();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Browse mode: D-pad must not open IME accidentally.
    if (key == LogicalKeyboardKey.arrowDown) {
      widget.onArrowDown();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onArrowRight?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (widget.controller.text.trim().isEmpty ||
          key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.gameButtonA) {
        _beginEditing();
      } else {
        widget.onSubmit(widget.controller.text);
      }
      return KeyEventResult.handled;
    }
    final typed = event.character;
    if (typed != null && _isTypingCharacter(typed)) {
      widget.controller.text = '${widget.controller.text}$typed';
      widget.controller.selection =
          TextSelection.collapsed(offset: widget.controller.text.length);
      _beginEditing();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing;
    return Shortcuts(
      shortcuts: editing
          ? const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.arrowDown):
                  _SearchLeaveDownIntent(),
            }
          : const <ShortcutActivator, Intent>{},
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SearchLeaveDownIntent: CallbackAction<_SearchLeaveDownIntent>(
            onInvoke: (_) {
              _leaveEditing();
              widget.onArrowDown();
              return null;
            },
          ),
        },
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.focusNode, widget.controller]),
          builder: (context, _) {
            final focused = widget.focusNode.hasFocus;
            return AvenFocusZoom(
              focused: focused,
              scale: 1.04,
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                // Same field always — only unlock input when editing.
                readOnly: !editing,
                showCursor: editing,
                enableInteractiveSelection: editing,
                autofocus: false,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                style: const TextStyle(fontSize: 20, color: AvenColors.text),
                cursorColor: AvenColors.text,
                onTap: _beginEditing,
                onSubmitted: widget.onSubmit,
                decoration: InputDecoration(
                  hintText: 'Site veya arama',
                  hintStyle: const TextStyle(color: AvenColors.textMuted),
                  filled: true,
                  fillColor: AvenColors.text.withValues(alpha: 0.08),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    borderSide: BorderSide(
                      color: AvenColors.text.withValues(alpha: 0.18),
                      width: 1.5,
                    ),
                  ),
                  disabledBorder: OutlineInputBorder(
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
                  focusedBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    borderSide: BorderSide(
                      color: focused ? AvenColors.hover : AvenColors.text.withValues(alpha: 0.18),
                      width: focused ? 3 : 1.5,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VoiceSearchButton extends StatelessWidget {
  const _VoiceSearchButton({
    required this.focusNode,
    required this.busy,
    required this.onPressed,
    required this.onKeyEvent,
  });

  final FocusNode focusNode;
  final bool busy;
  final VoidCallback onPressed;
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
            scale: 1.06,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: busy ? null : onPressed,
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: focused
                        ? AvenColors.hover
                        : AvenColors.text.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: focused
                          ? AvenColors.hover
                          : AvenColors.text.withValues(alpha: 0.18),
                      width: focused ? 3 : 1.5,
                    ),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: AvenColors.text,
                          ),
                        )
                      : Icon(
                          Icons.mic,
                          size: 26,
                          color: focused ? AvenColors.text : AvenColors.textMuted,
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
    Future<void>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      focusNode.requestFocus();
      try {
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      } catch (_) {}
      try {
        await WebInput().showKeyboard();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 140));
      if (!focusNode.hasFocus) focusNode.requestFocus();
      try {
        await WebInput().showKeyboard();
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    focusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      // While typing, Down moves into Google-style suggestions under the field.
      if (onArrow != null && key == LogicalKeyboardKey.arrowDown) {
        onArrow!(key);
        return KeyEventResult.handled;
      }
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
    required this.readerOn,
    required this.zoom,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onHome,
    required this.onBookmark,
    required this.onLibrary,
    required this.onToggleAdBlock,
    required this.onToggleReader,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onZoomReset,
    required this.onSettings,
    required this.onExit,
  });

  final FocusNode firstFocus;
  final FocusNode addressFocus;
  final bool canBack;
  final bool canForward;
  final bool saved;
  final bool adBlockOn;
  final bool readerOn;
  final int zoom;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final VoidCallback onHome;
  final VoidCallback onBookmark;
  final VoidCallback onLibrary;
  final VoidCallback onToggleAdBlock;
  final VoidCallback onToggleReader;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomReset;
  final VoidCallback onSettings;
  final VoidCallback onExit;

  @override
  State<_MenuBar> createState() => _MenuBarState();
}

class _MenuBarState extends State<_MenuBar> {
  late final List<FocusNode> _nodes = [
    widget.firstFocus,
    ...List.generate(12, (_) => FocusNode()),
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
      (
        widget.readerOn ? Icons.chrome_reader_mode : Icons.chrome_reader_mode_outlined,
        widget.readerOn ? 'Okuma açık' : 'Okuma modu',
        true,
        widget.onToggleReader,
        null,
      ),
      (Icons.remove, 'Uzaklaştır', true, widget.onZoomOut, null),
      (null, 'Yakınlaştırma', true, widget.onZoomReset, '%${widget.zoom}'),
      (Icons.add, 'Yakınlaştır', true, widget.onZoomIn, null),
      (Icons.settings, 'Ayarlar', true, widget.onSettings, null),
      (Icons.power_settings_new, 'Çıkış', true, widget.onExit, null),
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

