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
      400 => avenText('aven_error_invalid_request'),
      401 => avenText('aven_error_sign_in'),
      403 => avenText('aven_error_forbidden'),
      404 => avenText('aven_error_not_found'),
      408 => avenText('aven_error_timeout'),
      410 => avenText('aven_error_gone'),
      429 => avenText('aven_error_too_many'),
      500 => avenText('aven_error_server'),
      502 => avenText('aven_error_bad_gateway'),
      503 => avenText('aven_error_unavailable'),
      504 => avenText('aven_error_gateway_timeout'),
      _ when code >= 500 => avenText('aven_error_server'),
      _ => avenText('aven_error_load'),
    };
    return _PageError(
      code: code,
      title: title,
      detail: avenText('aven_error_http_code', [code]),
      url: url,
    );
  }

  factory _PageError.fromResource(WebResourceError error) {
    final type = error.errorType;
    final title = switch (type) {
      WebResourceErrorType.hostLookup => avenText('aven_error_host'),
      WebResourceErrorType.timeout => avenText('aven_error_connect_timeout'),
      WebResourceErrorType.connect => avenText('aven_error_connect'),
      WebResourceErrorType.failedSslHandshake => avenText('aven_error_ssl'),
      WebResourceErrorType.tooManyRequests => avenText('aven_error_too_many'),
      WebResourceErrorType.unsafeResource => avenText('aven_error_unsafe'),
      WebResourceErrorType.webContentProcessTerminated => avenText('aven_error_crashed'),
      WebResourceErrorType.badUrl => avenText('aven_error_bad_url'),
      WebResourceErrorType.fileNotFound => avenText('aven_error_not_found'),
      _ => avenText('aven_error_load'),
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
                fill: AvenColors.elevated,
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
                  AvenColors.rail,
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
                            color: AvenColors.text.withValues(alpha: 0.9),
                          ),
                        )
                      else
                        const Icon(Icons.wifi_off_rounded, size: 64, color: AvenColors.textMuted),
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
                          Flexible(child: FocusTraversalOrder(
                            order: const NumericFocusOrder(0),
                            child: _ErrorAction(
                              focusNode: _retryFocus,
                              label: avenText('aven_retry'),
                              icon: Icons.refresh,
                              onPressed: widget.onRetry,
                              onKeyEvent: (event) => _onKey(0, event),
                            ),
                          )),
                          const SizedBox(width: 14),
                          Flexible(child: FocusTraversalOrder(
                            order: const NumericFocusOrder(1),
                            child: _ErrorAction(
                              focusNode: _homeFocus,
                              label: avenText('aven_home'),
                              icon: Icons.home_outlined,
                              onPressed: widget.onHome,
                              onKeyEvent: (event) => _onKey(1, event),
                            ),
                          )),
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
            scale: 1.04,
            borderRadius: 12,
            showHalo: false,
            child: ExcludeFocus(
            child: TextButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
              style: TextButton.styleFrom(
                foregroundColor:
                    focused ? AvenColors.onFocus : AvenColors.text,
                backgroundColor:
                    focused ? AvenColors.focusFill : AvenColors.elevated,
                overlayColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: BorderSide.none,
                // Two of these share a phone-width row.
                minimumSize: Size(AvenFlavor.isMobile ? 0 : 160, 52),
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
        width: scrolling ? 28 : 26,
        height: scrolling ? 28 : 26,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(scrolling ? 9 : 12),
          color: AvenColors.background.withValues(alpha: 0.94),
          border: Border.all(
            color: AvenColors.text.withValues(alpha: scrolling ? 0.85 : 0.7),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: AvenColors.scrim,
              blurRadius: scrolling ? 8 : 6,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: _icon == null
            ? Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: AvenColors.text.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(3),
                ),
              )
            : Icon(_icon, size: 16, color: AvenColors.text),
      ),
    );
  }
}

class _StartPage extends StatefulWidget {
  const _StartPage({
    this.phone = false,
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
    required this.onOpenDownloads,
    required this.onSettings,
    this.watching = const [],
    this.onResume,
    this.showBookmarks = true,
    this.onRemoveHistory,
  });

  final bool showBookmarks;
  final ValueChanged<String>? onRemoveHistory;

  final bool phone;
  final List<WatchProgress> watching;
  final ValueChanged<WatchProgress>? onResume;
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
  final VoidCallback onOpenDownloads;
  final VoidCallback onSettings;

  @override
  State<_StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<_StartPage> {
  static const _bookmarkLimit = 24;
  static const _suggestLimit = 8;
  // TV home picks: video, live and music sites people open on a big screen.
  static const _suggestions = <_Suggestion>[
    _Suggestion(
      title: 'YouTube',
      url: 'https://www.youtube.com/',
      art: 'assets/suggestions/youtube.png',
      hosts: ['youtube.com', 'youtu.be'],
    ),
    _Suggestion(
      title: 'Netflix',
      url: 'https://www.netflix.com/',
      art: 'assets/suggestions/netflix.png',
      hosts: ['netflix.com'],
    ),
    _Suggestion(
      title: 'Prime Video',
      url: 'https://www.primevideo.com/',
      art: 'assets/suggestions/prime.webp',
      hosts: ['primevideo.com'],
    ),
    _Suggestion(
      title: 'Disney+',
      url: 'https://www.disneyplus.com/',
      art: 'assets/suggestions/disney.webp',
      hosts: ['disneyplus.com'],
    ),
    _Suggestion(
      title: 'HBO Max',
      url: 'https://www.hbomax.com/',
      art: 'assets/suggestions/max.png',
      hosts: ['hbomax.com', 'max.com'],
    ),
    _Suggestion(
      title: 'Twitch',
      url: 'https://www.twitch.tv/',
      art: 'assets/suggestions/twitch.png',
      hosts: ['twitch.tv'],
    ),
    _Suggestion(
      title: 'Kick',
      url: 'https://kick.com/',
      art: 'assets/suggestions/kick.png',
      hosts: ['kick.com'],
    ),
    _Suggestion(
      title: 'Spotify',
      url: 'https://open.spotify.com/',
      art: 'assets/suggestions/spotify.webp',
      hosts: ['spotify.com'],
    ),
  ];

  late final List<FocusNode> _suggestFocus =
      List.generate(_suggestions.length, (_) => FocusNode());
  late final List<FocusNode> _bookmarkFocus =
      List.generate(_bookmarkLimit, (_) => FocusNode());
  // TV home actions: library, settings.
  late final List<FocusNode> _actionFocus = List.generate(2, (_) => FocusNode());
  static const _watchLimit = 8;
  late final List<FocusNode> _watchFocus = List.generate(_watchLimit, (_) => FocusNode());
  late final Listenable _watchRailListenable = Listenable.merge(_watchFocus);
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
    for (final node in _watchFocus) {
      node.dispose();
    }
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
    for (final suggestion in _suggestions) {
      for (final known in suggestion.hosts) {
        if (host == known || host.endsWith('.$known')) return suggestion;
      }
    }
    return null;
  }

  int get _bookmarkCount =>
      widget.showBookmarks ? widget.bookmarks.length.clamp(0, _bookmarkLimit) : 0;
  int get _watchCount => widget.watching.length.clamp(0, _watchLimit);
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

  /// Actions → continue watching → site suggestions (if enabled) → bookmarks.
  void _focusAfterActions() {
    if (!mounted) return;
    if (_watchCount > 0 && !_hasQuerySuggests) {
      _requestNode(_watchFocus.first);
      return;
    }
    _focusBelowWatching();
  }

  void _focusBelowWatching() {
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
    _requestNode(_watchCount > 0 ? _watchFocus.first : _actionFocus.first);
  }

  void _onWatchKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight && index < _watchCount - 1) {
      _requestNode(_watchFocus[index + 1]);
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft && index > 0) {
      _requestNode(_watchFocus[index - 1]);
      return;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _requestNode(_actionFocus.first);
      return;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _focusBelowWatching();
      return;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space) {
      widget.onResume?.call(widget.watching[index]);
    }
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
    if (key == LogicalKeyboardKey.arrowRight && index < _actionFocus.length - 1) {
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
          (widget.showSuggestions || _bookmarkCount > 0 || _watchCount > 0)) {
        _focusAfterActions();
      }
      return;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space) {
      if (index == 0) {
        widget.onOpenBookmarks();
      } else {
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

  /// Phone start: fixed, no scrolling. The search bar floats at the middle
  /// (see the omnibox in BrowserPage); recents fill only the room left.
  Widget _phoneStart(BuildContext context, double height) {
    const recentRow = 64.0;
    // The search bar is placed in the full area, which also covers the
    // system navigation bar this page stops above.
    final full = height + MediaQuery.viewPaddingOf(context).bottom;
    final top = (_phoneSearchTop(full) - 8 - 48 - 28).clamp(8.0, double.infinity);
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        // Keyboard or split screen: keep the column valid instead of overflowing.
        height: height < 420 ? 420 : height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: top + 8),
            const Text(
              'aven',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cal Sans',
                fontSize: 48,
                fontWeight: FontWeight.w600,
                letterSpacing: -1.2,
                height: 1,
              ),
            ),
            // Room for the floating search bar.
            const SizedBox(height: 28 + 56 + 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _PhoneShortcut(
                  icon: Icons.history,
                  label: avenText('aven_history'),
                  onPressed: widget.onOpenHistory,
                ),
                _PhoneShortcut(
                  icon: Icons.star_outline,
                  label: avenText('aven_bookmarks'),
                  onPressed: widget.onOpenBookmarks,
                ),
                _PhoneShortcut(
                  icon: Icons.download_outlined,
                  label: avenText('aven_downloads'),
                  onPressed: widget.onOpenDownloads,
                ),
                _PhoneShortcut(
                  icon: Icons.settings,
                  label: avenText('aven_settings'),
                  onPressed: widget.onSettings,
                ),
              ],
            ),
            Expanded(
              child: Padding(
                // Clear of the floating toolbar.
                padding: const EdgeInsets.only(bottom: 84),
                child: LayoutBuilder(
                builder: (context, box) {
                  const watchRow = 28.0 + 22 + 84;
                  final watching = widget.watching.take(_watchLimit).toList();
                  final showWatch = watching.isNotEmpty && box.maxHeight >= watchRow;
                  final room = box.maxHeight - (showWatch ? watchRow : 0);
                  final fits = ((room - 28 - 22 - 8) / recentRow).floor();
                  final items = widget.history.take(fits.clamp(0, 4)).toList();
                  if (items.isEmpty && !showWatch) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showWatch) ...[
                        const SizedBox(height: 28),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                          child: Text(
                            avenText('aven_continue_watching'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AvenTone.textMuted(context),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 84,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            itemCount: watching.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 10),
                            itemBuilder: (context, index) => _WatchCard(
                              entry: watching[index],
                              onPressed: () => widget.onResume?.call(watching[index]),
                            ),
                          ),
                        ),
                      ],
                      if (items.isEmpty) const SizedBox.shrink() else ...[
                      const SizedBox(height: 28),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                        child: Text(
                          avenText('aven_recent'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AvenTone.textMuted(context),
                          ),
                        ),
                      ),
                      for (final item in items)
                        SizedBox(
                          height: recentRow,
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.only(left: 8),
                            leading: _SiteIcon(url: item.url),
                            trailing: IconButton(
                              onPressed: () => widget.onRemoveHistory?.call(item.url),
                              icon: Icon(Icons.close, size: 18, color: AvenTone.textMuted(context)),
                              tooltip: avenText('aven_remove_recent'),
                            ),
                            title: Text(
                              item.title.trim().isEmpty ? item.url : item.title.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              Uri.tryParse(item.url)?.host ?? item.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => widget.onSubmit(item.url),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks = widget.bookmarks.take(_bookmarkCount).toList();
    final showQuery = _hasQuerySuggests;
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: ColoredBox(
        color: widget.phone
            ? Theme.of(context).scaffoldBackgroundColor
            : AvenColors.background,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (widget.phone) return _phoneStart(context, constraints.maxHeight);
            return SingleChildScrollView(
              controller: _pageScroll,
              physics: const ClampingScrollPhysics(),
              clipBehavior: Clip.none,
              padding: EdgeInsets.fromLTRB(
                widget.phone ? 16 : 28,
                widget.phone ? 8 : 16,
                widget.phone ? 16 : 28,
                48,
              ),
              child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 64).clamp(0.0, double.infinity),
                  maxWidth: 980,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      'aven',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cal Sans',
                        fontSize: widget.phone ? 48 : 56,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1.2,
                        height: 1,
                      ),
                    ),
                    if (!widget.phone) ...[
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
                    ],
                    if (!widget.phone) const SizedBox(height: 16),
                    if (!widget.phone)
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FocusTraversalOrder(
                              order: const NumericFocusOrder(1),
                              child: _StartAction(
                                focusNode: _actionFocus[0],
                                icon: Icons.video_library_outlined,
                                label: avenText('aven_library'),
                                // Opens on bookmarks; history, downloads and the
                                // reading list are tabs inside.
                                onPressed: widget.onOpenBookmarks,
                                onKeyEvent: (event) => _onActionKey(0, event),
                              ),
                            ),
                            const SizedBox(width: 14),
                            FocusTraversalOrder(
                              order: const NumericFocusOrder(2),
                              child: _StartAction(
                                focusNode: _actionFocus[1],
                                icon: Icons.settings,
                                label: avenText('aven_settings'),
                                onPressed: widget.onSettings,
                                onKeyEvent: (event) => _onActionKey(1, event),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!widget.phone && !showQuery) ...[
                      if (_watchCount > 0) ...[
                        const SizedBox(height: 22),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            avenText('aven_continue_watching'),
                            style: TextStyle(
                              fontSize: 16,
                              color: AvenColors.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 172,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(4, 18, 48, 18),
                            child: Row(
                              children: [
                                for (var index = 0; index < _watchCount; index++) ...[
                                  if (index > 0) const SizedBox(width: _suggestGap),
                                  FocusTraversalOrder(
                                    order: NumericFocusOrder(5 + index * 0.01),
                                    child: _WatchCard(
                                      entry: widget.watching[index],
                                      tv: true,
                                      focusNode: _watchFocus[index],
                                      railListenable: _watchRailListenable,
                                      onKeyEvent: (event) => _onWatchKey(index, event),
                                      onPressed: () => widget.onResume?.call(widget.watching[index]),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (_showSiteRail) ...[
                        const SizedBox(height: 22),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            avenText('aven_suggestions'),
                            style: TextStyle(
                              fontSize: 16,
                              color: AvenColors.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          // Art card, its name underneath, and room for the focus lift.
                          height: 204,
                          child: SingleChildScrollView(
                            controller: _suggestScroll,
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(4, 18, 48, 18),
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
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            avenText('aven_bookmarks'),
                            style: TextStyle(
                              fontSize: 16,
                              color: AvenColors.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 188,
                          child: SingleChildScrollView(
                            controller: _bookmarkScroll,
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(4, 18, 48, 18),
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
                ? AvenColors.text.withValues(alpha: 0.10)
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
    required this.art,
    required this.hosts,
  });

  final String title;
  final String url;

  /// 16:9 brand artwork that fills the card.
  final String art;

  /// Sites whose bookmarks reuse this artwork.
  final List<String> hosts;

  static const faceBackground = Color(0xFF000000);
}

/// TV home suggestion: full-bleed brand art with the name underneath; the
/// focused card lifts, gets a white ring and a soft glow, the rest dim.
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

  static const width = 228.0;
  static const artHeight = 128.0;

  @override
  Widget build(BuildContext context) {
    final art = _SuggestionLogo(suggestion: suggestion);
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
        child: art,
        builder: (context, child) {
          final focused = focusNode.hasFocus;
          final dimmed = railNodes.any((node) => node.hasFocus) && !focused;
          return GestureDetector(
            onTap: onPressed,
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedScale(
                    scale: focused ? 1.06 : 1,
                    duration: AvenFocusMotion.duration,
                    curve: AvenFocusMotion.curve,
                    child: AnimatedContainer(
                      duration: AvenFocusMotion.duration,
                      curve: AvenFocusMotion.curve,
                      width: width,
                      height: artHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: focused
                            ? [
                                BoxShadow(
                                  color: AvenColors.text.withValues(alpha: 0.22),
                                  blurRadius: 24,
                                  spreadRadius: 1,
                                ),
                              ]
                            : const [],
                      ),
                      foregroundDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: focused ? AvenColors.text : AvenColors.text.withValues(alpha: 0.08),
                          width: focused ? 3 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedOpacity(
                          opacity: dimmed ? 0.45 : 1,
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AnimatedDefaultTextStyle(
                    duration: AvenFocusMotion.duration,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: focused ? FontWeight.w700 : FontWeight.w500,
                      color: focused
                          ? AvenColors.text
                          : AvenColors.textMuted.withValues(alpha: dimmed ? 0.6 : 1),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(suggestion.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
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
    final px = (_SuggestionPoster.width * MediaQuery.devicePixelRatioOf(context)).round();
    return Image.asset(
      suggestion.art,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: px,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stack) => const ColoredBox(
        color: _Suggestion.faceBackground,
        child: Center(child: Icon(Icons.public, size: 36, color: AvenColors.text)),
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
            scale: focused ? 1.04 : 1,
            duration: AvenFocusMotion.duration,
            curve: AvenFocusMotion.curve,
            child: SizedBox(
              width: 228,
              height: 136,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onPressed,
                        borderRadius: BorderRadius.circular(14),
                        overlayColor:
                            const WidgetStatePropertyAll(Colors.transparent),
                        child: AnimatedOpacity(
                          opacity: dimmed ? 0.34 : 1,
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                child!,
                                if (dimmed)
                                  ColoredBox(
                                    color: AvenColors.background
                                        .withValues(alpha: 0.45),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 2,
                    top: 2,
                    right: 2,
                    bottom: 2,
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: AvenFocusMotion.duration,
                        curve: AvenFocusMotion.curve,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: focused
                                ? AvenColors.text.withValues(alpha: 0.88)
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
          const radius = 12.0;
          final ink = focused ? AvenColors.onFocus : AvenColors.text;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(radius),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              child: AnimatedContainer(
                duration: AvenFocusMotion.duration,
                curve: AvenFocusMotion.curve,
                width: 168,
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: focused ? AvenColors.focusFill : AvenColors.elevated,
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 20, color: ink),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                    ),
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

/// Top of the phone search bar on the start screen: the middle of the page.
/// BrowserPage places the omnibox here; the start page leaves room for it.
/// Continue watching: the page's title, its site and how far the video got.
class _WatchCard extends StatelessWidget {
  const _WatchCard({
    required this.entry,
    required this.onPressed,
    this.tv = false,
    this.focusNode,
    this.railListenable,
    this.onKeyEvent,
  });

  final WatchProgress entry;
  final VoidCallback onPressed;
  final bool tv;
  final FocusNode? focusNode;
  final Listenable? railListenable;
  final ValueChanged<KeyEvent>? onKeyEvent;

  Widget _face(BuildContext context, bool focused) {
    final ink = tv ? AvenColors.text : AvenTone.text(context);
    final muted = tv ? AvenColors.textMuted : AvenTone.textMuted(context);
    final host = Uri.tryParse(entry.page ?? '')?.host ?? '';
    final title = entry.title.trim().isEmpty ? host : entry.title.trim();
    return AnimatedContainer(
      duration: AvenFocusMotion.duration,
      curve: AvenFocusMotion.curve,
      width: tv ? 300 : 220,
      height: tv ? 136 : 76,
      padding: EdgeInsets.fromLTRB(12, tv ? 14 : 10, 12, tv ? 14 : 10),
      decoration: BoxDecoration(
        color: tv ? AvenColors.panel : AvenTone.elevated(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focused ? ink.withValues(alpha: 0.88) : Colors.transparent,
          width: 2.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.play_circle_outline, size: tv ? 26 : 20, color: ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: tv ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: tv ? 16 : 14, fontWeight: FontWeight.w600, color: ink),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            host,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: entry.fraction,
              minHeight: 4,
              color: ink,
              backgroundColor: ink.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!tv) {
      return InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: _face(context, false),
      );
    }
    final node = focusNode!;
    return Focus(
      focusNode: node,
      onKeyEvent: (_, event) {
        onKeyEvent?.call(event);
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
        listenable: railListenable ?? node,
        builder: (context, _) {
          final focused = node.hasFocus;
          return AnimatedScale(
            scale: focused ? 1.04 : 1,
            duration: AvenFocusMotion.duration,
            curve: AvenFocusMotion.curve,
            child: GestureDetector(onTap: onPressed, child: _face(context, focused)),
          );
        },
      ),
    );
  }
}

/// Site favicon (Google's favicon service), a globe when there is none.
class _SiteIcon extends StatelessWidget {
  const _SiteIcon({required this.url, this.size = 20});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(Icons.public, size: size, color: AvenTone.textMuted(context));
    final host = Uri.tryParse(url ?? '')?.host ?? '';
    if (host.isEmpty) return fallback;
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 5),
      child: Image.network(
        'https://www.google.com/s2/favicons?domain=$host&sz=64',
        width: size,
        height: size,
        fit: BoxFit.contain,
        cacheWidth: px,
        cacheHeight: px,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) => fallback,
      ),
    );
  }
}

double _phoneSearchTop(double height) => ((height - 52) / 2 - 28).clamp(4.0, double.infinity);

class _PhoneShortcut extends StatelessWidget {
  const _PhoneShortcut({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AvenTone.elevated(context),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneOmnibox extends StatelessWidget {
  const _PhoneOmnibox({
    required this.address,
    required this.addressFocus,
    required this.editing,
    required this.canShare,
    required this.voiceBusy,
    required this.onVoice,
    required this.loading,
    required this.progress,
    required this.onTapField,
    required this.onSubmit,
    required this.onShare,
    this.onHide,
    this.incognito = false,
    this.connection = 'unknown',
    this.onSecurity,
  });

  final TextEditingController address;
  final FocusNode addressFocus;
  final bool editing;
  final bool canShare;
  final bool voiceBusy;
  final VoidCallback onVoice;
  final ValueNotifier<bool> loading;
  final ValueNotifier<int> progress;
  final VoidCallback onTapField;
  final ValueChanged<String> onSubmit;
  final VoidCallback onShare;

  /// Tucks the bar away so the top of the page shows; null on the start screen.
  final VoidCallback? onHide;
  final bool incognito;
  final String connection;
  final VoidCallback? onSecurity;

  @override
  Widget build(BuildContext context) {
    final ink = incognito ? Colors.white : AvenTone.text(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Material(
        color: incognito ? const Color(0xFF2A2A32) : AvenTone.elevated(context),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.45),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: address,
              focusNode: addressFocus,
              onTap: onTapField,
              textInputAction: TextInputAction.go,
              onSubmitted: onSubmit,
              style: TextStyle(fontSize: 16, color: ink),
              cursorColor: ink,
              decoration: InputDecoration(
                isDense: true,
                hintText: incognito ? avenText('aven_search_private') : avenText('aven_search_hint'),
                hintStyle: TextStyle(color: AvenTone.textMuted(context)),
                prefixIcon: _securityIcon(ink),
                prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 40),
                suffixIcon: ListenableBuilder(
                  listenable: Listenable.merge([address, addressFocus]),
                  builder: (context, _) {
                    final showClear = addressFocus.hasFocus && address.text.isNotEmpty;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showClear)
                          IconButton(
                            onPressed: address.clear,
                            icon: Icon(Icons.close, size: 20, color: ink),
                            tooltip: avenText('aven_clear'),
                          ),
                        IconButton(
                          onPressed: voiceBusy ? null : onVoice,
                          icon: Icon(
                            voiceBusy ? Icons.hourglass_top : Icons.mic_none,
                            size: 22,
                            color: ink,
                          ),
                          tooltip: avenText('aven_voice'),
                        ),
                        IconButton(
                          onPressed: canShare ? onShare : null,
                          icon: Icon(
                            Icons.share_outlined,
                            size: 22,
                            color: canShare ? ink : ink.withValues(alpha: 0.28),
                          ),
                          tooltip: avenText('aven_share'),
                        ),
                        if (onHide != null && !addressFocus.hasFocus)
                          IconButton(
                            onPressed: onHide,
                            icon: Icon(Icons.expand_less, size: 24, color: ink),
                            tooltip: avenText('aven_hide_address'),
                          ),
                      ],
                    );
                  },
                ),
                suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 40),
                filled: true,
                fillColor: AvenTone.elevated(context),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: const OutlineInputBorder(borderSide: BorderSide.none),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: loading,
              builder: (context, busy, _) {
                if (!busy) return const SizedBox(height: 2);
                return ValueListenableBuilder<int>(
                  valueListenable: progress,
                  builder: (context, value, _) {
                    return LinearProgressIndicator(
                      value: (value / 100).clamp(0.04, 1.0),
                      minHeight: 2,
                      color: ink,
                      backgroundColor: ink.withValues(alpha: 0.12),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _securityIcon(Color ink) {
    if (connection == 'unknown') {
      return Icon(
        incognito ? Icons.visibility_off_outlined : Icons.search,
        size: 22,
        color: ink,
      );
    }
    final (IconData icon, Color color) = switch (connection) {
      'secure' => (Icons.lock, const Color(0xFF188038)),
      'warning' => (Icons.warning_amber, const Color(0xFFE37400)),
      _ => (Icons.lock_open, const Color(0xFFD93025)),
    };
    return IconButton(
      onPressed: onSecurity,
      tooltip: avenText('aven_connection'),
      icon: Icon(icon, size: 20, color: incognito ? Colors.white : color),
    );
  }
}

class _SitePermRow extends StatefulWidget {
  const _SitePermRow({
    required this.id,
    required this.label,
    required this.value,
    required this.fallback,
    required this.onChanged,
  });

  final String id;
  final String label;
  final String value;
  final String fallback;
  final ValueChanged<String> onChanged;

  @override
  State<_SitePermRow> createState() => _SitePermRowState();
}

class _SitePermRowState extends State<_SitePermRow> {
  late String _value = widget.value;

  IconData get _permIcon => switch (widget.id) {
    'location' => Icons.location_on_outlined,
    'camera' => Icons.photo_camera_outlined,
    'microphone' => Icons.mic_none,
    'notifications' => Icons.notifications_none,
    'storage' => Icons.sd_storage_outlined,
    'autoplay' => Icons.play_circle_outline,
    _ => Icons.tune,
  };

  String _choiceLabel(String value) => switch (value) {
    'allow' => avenText('aven_allow'),
    'block' => avenText('aven_block'),
    _ => avenText('aven_ask'),
  };

  @override
  Widget build(BuildContext context) {
    final ink = AvenTone.text(context);
    final muted = AvenTone.textMuted(context);
    const choices = ['ask', 'allow', 'block'];
    final usingDefault = _value == widget.fallback;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AvenTone.background(context),
                  shape: BoxShape.circle,
                ),
                child: Icon(_permIcon, size: 19, color: ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    Text(
                      usingDefault
                          ? '${_choiceLabel(_value)} · ${avenText('aven_default')}'
                          : _choiceLabel(_value),
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Segmented choice: the selected part slides under the label.
          LayoutBuilder(
            builder: (context, box) {
              final part = box.maxWidth / choices.length;
              return Container(
                height: 40,
                decoration: BoxDecoration(
                  color: AvenTone.background(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      left: part * choices.indexOf(_value).clamp(0, 2) + 3,
                      top: 3,
                      bottom: 3,
                      width: part - 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: ink,
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (final value in choices)
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                if (_value == value) return;
                                HapticFeedback.selectionClick();
                                setState(() => _value = value);
                                widget.onChanged(value);
                              },
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 180),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _value == value ? AvenTone.background(context) : ink,
                                  ),
                                  child: Text(_choiceLabel(value)),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DownloadToast extends StatelessWidget {
  const _DownloadToast({
    required this.item,
    required this.onOpen,
    required this.onCancel,
    required this.onDismiss,
  });

  final Map<String, String> item;
  final VoidCallback onOpen;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final status = item['status'] ?? '';
    final raw = int.tryParse(item['progress'] ?? '') ?? -1;
    final done = status == 'success';
    final value = done ? 1.0 : (raw < 0 ? null : raw / 100);
    final title = (item['title'] ?? '').trim().isEmpty ? avenText('aven_download') : item['title']!.trim();
    final label = downloadStatusLabel(status, item['progress']);
    return Material(
      color: AvenTone.elevated(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: AvenTone.textMuted(context)),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: value, minHeight: 3),
            Align(
              alignment: Alignment.centerRight,
              child: done
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(onPressed: onDismiss, child: Text(avenText('aven_close'))),
                        TextButton(onPressed: onOpen, child: Text(avenText('aven_open_file'))),
                      ],
                    )
                  : TextButton(onPressed: onCancel, child: Text(avenText('aven_cancel'))),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneTopBar extends StatelessWidget {
  const _PhoneTopBar({
    required this.tabCount,
    required this.canBack,
    required this.canForward,
    required this.saved,
    required this.adBlockOn,
    required this.readerOn,
    required this.zoom,
    required this.desktopSite,
    required this.onBack,
    required this.onForward,
    required this.onNewTab,
    required this.onTabs,
    required this.onBookmark,
    required this.onLibrary,
    required this.onToggleAdBlock,
    required this.onToggleReader,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onZoomReset,
    required this.onSettings,
    required this.onToggleDesktop,
    required this.onIncognito,
    required this.onFind,
    required this.onDownloads,
    required this.onCast,
    required this.playingVideo,
    required this.onSiteSettings,
    required this.canShare,
    required this.canReload,
    required this.onReload,
    required this.onReadLater,
    required this.onRemote,
  });

  final VoidCallback onReadLater;
  final VoidCallback onRemote;
  final int tabCount;
  final bool canBack;
  final bool canForward;
  final bool saved;
  final bool adBlockOn;
  final bool readerOn;
  final int zoom;
  final bool desktopSite;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onNewTab;
  final VoidCallback onTabs;
  final VoidCallback onBookmark;
  final VoidCallback onLibrary;
  final VoidCallback onToggleAdBlock;
  final VoidCallback onToggleReader;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomReset;
  final VoidCallback onSettings;
  final VoidCallback onToggleDesktop;
  final VoidCallback onIncognito;
  final VoidCallback onFind;
  final VoidCallback onDownloads;
  final VoidCallback onCast;
  final bool playingVideo;
  final VoidCallback onSiteSettings;
  final bool canShare;
  final bool canReload;
  final VoidCallback onReload;

  void _openMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AvenTone.background(context),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        void run(VoidCallback action) {
          Navigator.pop(context);
          action();
        }

        var shownZoom = zoom;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GridView.count(
                  crossAxisCount: 5,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 4,
                  childAspectRatio: 0.7,
                  children: [
                    _MenuTile(
                      icon: Icons.add,
                      label: avenText('aven_new_tab'),
                      onTap: () => run(onNewTab),
                    ),
                    _MenuTile(
                      icon: Icons.visibility_off_outlined,
                      label: avenText('aven_private'),
                      onTap: () => run(onIncognito),
                    ),
                    _MenuTile(
                      icon: saved ? Icons.star : Icons.star_border,
                      label: avenText('aven_bookmark'),
                      active: saved,
                      onTap: canShare ? () => run(onBookmark) : null,
                    ),
                    _MenuTile(
                      icon: Icons.bookmark_add_outlined,
                      label: avenText('aven_read_later'),
                      onTap: canShare ? () => run(onReadLater) : null,
                    ),
                    _MenuTile(
                      icon: Icons.refresh,
                      label: avenText('aven_reload'),
                      onTap: canReload ? () => run(onReload) : null,
                    ),
                    _MenuTile(
                      icon: Icons.history,
                      label: avenText('aven_library'),
                      onTap: () => run(onLibrary),
                    ),
                    _MenuTile(
                      icon: Icons.download_outlined,
                      label: avenText('aven_downloads'),
                      onTap: () => run(onDownloads),
                    ),
                    _MenuTile(
                      icon: Icons.search,
                      label: avenText('aven_find'),
                      onTap: canReload ? () => run(onFind) : null,
                    ),
                    _MenuTile(
                      icon: Icons.connected_tv,
                      label: avenText('aven_cast_short'),
                      onTap: canShare ? () => run(onCast) : null,
                    ),
                    _MenuTile(
                      icon: Icons.settings_remote_outlined,
                      label: avenText('aven_tv_remote'),
                      onTap: () => run(onRemote),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _MenuCard(
                  children: [
                    _MenuSwitch(
                      icon: Icons.desktop_windows_outlined,
                      label: avenText('aven_site_desktop'),
                      value: desktopSite,
                      onChanged: () => run(onToggleDesktop),
                    ),
                    _MenuSwitch(
                      icon: Icons.chrome_reader_mode_outlined,
                      label: avenText('aven_reader_on'),
                      value: readerOn,
                      onChanged: canReload ? () => run(onToggleReader) : null,
                    ),
                    _MenuSwitch(
                      icon: adBlockOn ? Icons.shield : Icons.shield_outlined,
                      label: avenText('aven_adblock'),
                      value: adBlockOn,
                      onChanged: () => run(onToggleAdBlock),
                    ),
                    // Zoom changes live, so the sheet stays open and shows the value.
                    StatefulBuilder(
                      builder: (context, setLocal) {
                        return _MenuZoom(
                          zoom: shownZoom,
                          onOut: () {
                            onZoomOut();
                            setLocal(() => shownZoom = (shownZoom - 10).clamp(50, 300));
                          },
                          onIn: () {
                            onZoomIn();
                            setLocal(() => shownZoom = (shownZoom + 10).clamp(50, 300));
                          },
                          onReset: () {
                            onZoomReset();
                            setLocal(() => shownZoom = 100);
                          },
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MenuButton(
                        icon: Icons.tune,
                        label: avenText('aven_site_settings'),
                        onTap: canShare ? () => run(onSiteSettings) : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MenuButton(
                        icon: Icons.settings_outlined,
                        label: avenText('aven_settings'),
                        onTap: () => run(onSettings),
                      ),
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

  @override
  Widget build(BuildContext context) {
    final ink = AvenTone.text(context);
    // A rounded bar floating over the page, not a strip glued to the bottom.
    return Material(
      color: AvenTone.elevated(context),
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      child: SizedBox(
          height: 56,
          child: Row(
            children: [
              Expanded(
                child: IconButton(
                  onPressed: canBack ? onBack : null,
                  icon: Icon(Icons.arrow_back, color: canBack ? ink : ink.withValues(alpha: 0.28)),
                  tooltip: avenText('aven_back'),
                ),
              ),
              Expanded(
                child: IconButton(
                  onPressed: canForward ? onForward : null,
                  icon: Icon(Icons.arrow_forward, color: canForward ? ink : ink.withValues(alpha: 0.28)),
                  tooltip: avenText('aven_forward'),
                ),
              ),
              Expanded(
                child: IconButton(
                  onPressed: onNewTab,
                  icon: Icon(Icons.add, color: ink),
                  tooltip: avenText('aven_new_tab'),
                ),
              ),
              Expanded(
                child: IconButton(
                  onPressed: onTabs,
                  tooltip: avenText('aven_tabs'),
                  icon: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: ink, width: 1.6),
                    ),
                    child: Text(
                      '$tabCount',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: IconButton(
                  onPressed: () => _openMenu(context),
                  icon: Icon(Icons.more_vert, color: ink),
                  tooltip: avenText('aven_menu'),
                ),
              ),
            ],
          ),
        ),
    );
  }
}

class _CastTvSheet extends StatefulWidget {
  const _CastTvSheet();

  @override
  State<_CastTvSheet> createState() => _CastTvSheetState();
}

class _CastTvSheetState extends State<_CastTvSheet> {
  final _input = WebInput();
  List<({String name, String host, int port})> _devices = const [];
  String? _message;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    unawaited(_scan());
  }

  Future<void> _scan() async {
    try {
      final found = await _input.discoverTvs();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _devices = found.devices;
        _message = found.error == 'permission'
            ? avenText('aven_cast_permission')
            : found.devices.isEmpty
                ? avenText('aven_cast_none')
                : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = avenText('aven_cast_failed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _busy
          ? Padding(
              padding: const EdgeInsets.all(28),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 16),
                  Text(avenText('aven_cast_searching')),
                ],
              ),
            )
          : ListView(
              shrinkWrap: true,
              children: [
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Text(_message!),
                  ),
                for (final device in _devices)
                  ListTile(
                    leading: const Icon(Icons.tv),
                    title: Text(device.name),
                    subtitle: Text(device.host),
                    onTap: () => Navigator.pop(context, device),
                  ),
              ],
            ),
    );
  }
}

class _PhoneTabGrid extends StatelessWidget {
  const _PhoneTabGrid({
    required this.tabs,
    required this.tabIndex,
    required this.onCloseGrid,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onCloseAll,
    required this.onNewTab,
    required this.onIncognito,
    required this.closed,
    required this.onReopen,
  });

  final List<({String url, String title})> closed;
  final ValueChanged<int> onReopen;
  final List<_PageTab> tabs;
  final int tabIndex;
  final VoidCallback onCloseGrid;
  final ValueChanged<int> onSelectTab;
  final ValueChanged<int> onCloseTab;
  final VoidCallback onCloseAll;
  final VoidCallback onNewTab;
  final VoidCallback onIncognito;

  void _showClosed(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AvenTone.elevated(context),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    avenText('aven_recently_closed'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                if (closed.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Text(avenText('aven_recently_closed_empty')),
                  ),
                for (var index = 0; index < closed.length; index++)
                  ListTile(
                    leading: _SiteIcon(url: closed[index].url),
                    title: Text(closed[index].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      Uri.tryParse(closed[index].url)?.host ?? closed[index].url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      onReopen(index);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AvenTone.background(context),
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  IconButton(
                    onPressed: onCloseGrid,
                    icon: const Icon(Icons.close),
                  ),
                  Expanded(
                    child: Text(
                      tabs.length == 1
                          ? avenText('aven_tab_count_one')
                          : avenText('aven_tab_count', [tabs.length]),
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                  IconButton(
                    onPressed: closed.isEmpty ? null : () => _showClosed(context),
                    tooltip: avenText('aven_recently_closed'),
                    icon: const Icon(Icons.restore),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.78,
                ),
                itemCount: tabs.length,
                itemBuilder: (context, index) {
                  final tab = tabs[index];
                  final selected = index == tabIndex;
                  final url = tab.url;
                  return Material(
                    color: tab.incognito
                        ? const Color(0xFF2A2A32)
                        : AvenTone.elevated(context),
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      onTap: () => onSelectTab(index),
                      borderRadius: BorderRadius.circular(18),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected ? AvenTone.text(context) : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (tab.incognito)
                                    const Icon(Icons.visibility_off_outlined, size: 18, color: Colors.white70)
                                  else
                                    _SiteIcon(url: url, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      tab.incognito ? avenText('aven_private_title', [tab.title]) : tab.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: tab.incognito ? Colors.white : null,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => onCloseTab(index),
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                                ],
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: tab.preview == null
                                      ? Container(
                                          width: double.infinity,
                                          color: tab.incognito
                                              ? const Color(0xFF1C1C22)
                                              : AvenTone.background(context),
                                          child: Icon(
                                            tab.incognito ? Icons.visibility_off_outlined : Icons.public,
                                            color: AvenTone.textMuted(context),
                                          ),
                                        )
                                      : Image.memory(
                                          tab.preview!,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          gaplessPlayback: true,
                                        ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                url == null || url.isEmpty
                                    ? avenText('aven_new_tab')
                                    : (Uri.tryParse(url)?.host ?? url),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: tab.incognito ? Colors.white70 : AvenTone.textMuted(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: onCloseAll,
                    child: Text(avenText('aven_close_all')),
                  ),
                  TextButton(
                    onPressed: onIncognito,
                    child: Text(avenText('aven_private')),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: onNewTab,
                    icon: const Icon(Icons.add),
                    label: Text(avenText('aven_new_tab')),
                  ),
                ],
              ),
            ),
          ],
        ),
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
    required this.onReadLater,
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
  final VoidCallback onReadLater;
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
              color: AvenColors.panel.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.none,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
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
                      const SizedBox(height: 10),
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
                        onReadLater: onReadLater,
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
            // No zoom wrapper — field already has its own focused border.
            return TextField(
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
                cursorColor: AvenColors.accent,
                onTap: _beginEditing,
                onSubmitted: widget.onSubmit,
                decoration: InputDecoration(
                  hintText: avenText('aven_search_site'),
                  hintStyle: const TextStyle(color: AvenColors.textMuted),
                  filled: true,
                  fillColor: AvenColors.elevated,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    borderSide: BorderSide.none,
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    borderSide: BorderSide.none,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    borderSide: const BorderSide(
                      color: AvenColors.accent,
                      width: 2,
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
            scale: 1.05,
            borderRadius: 10,
            showHalo: false,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: busy ? null : onPressed,
                borderRadius: BorderRadius.circular(10),
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                child: Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: focused
                        ? AvenColors.focusFill
                        : AvenColors.elevated,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : Icon(
                          Icons.mic,
                          size: 26,
                          color: focused
                              ? AvenColors.onFocus
                              : AvenColors.textMuted,
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
        return TextField(
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
        hintText: avenText('aven_search_site'),
        filled: true,
        fillColor: AvenColors.elevated,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: compact ? 8 : 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide.none,
        ),
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: const BorderSide(
            color: AvenColors.accent,
            width: 2,
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
    required this.onReadLater,
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
  final VoidCallback onReadLater;
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
    ...List.generate(13, (_) => FocusNode()),
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
      (Icons.arrow_back, avenText('aven_back'), widget.canBack, widget.onBack, null),
      (Icons.arrow_forward, avenText('aven_forward'), widget.canForward, widget.onForward, null),
      (Icons.refresh, avenText('aven_reload'), true, widget.onReload, null),
      (Icons.home, avenText('aven_home'), true, widget.onHome, null),
      (widget.saved ? Icons.star : Icons.star_border, avenText('aven_bookmark'), true, widget.onBookmark, null),
      (Icons.bookmark_add_outlined, avenText('aven_read_later'), true, widget.onReadLater, null),
      (Icons.history, avenText('aven_library'), true, widget.onLibrary, null),
      (
        widget.adBlockOn ? Icons.shield : Icons.shield_outlined,
        widget.adBlockOn ? avenText('aven_adblock_on') : avenText('aven_adblock_off_short'),
        true,
        widget.onToggleAdBlock,
        null,
      ),
      (
        widget.readerOn ? Icons.chrome_reader_mode : Icons.chrome_reader_mode_outlined,
        widget.readerOn ? avenText('aven_reader_short') : avenText('aven_reader_on'),
        true,
        widget.onToggleReader,
        null,
      ),
      (Icons.remove, avenText('aven_zoom_out'), true, widget.onZoomOut, null),
      (null, avenText('aven_zoom'), true, widget.onZoomReset, '%${widget.zoom}'),
      (Icons.add, avenText('aven_zoom_in'), true, widget.onZoomIn, null),
      (Icons.settings, avenText('aven_settings'), true, widget.onSettings, null),
      (Icons.power_settings_new, avenText('aven_exit'), true, widget.onExit, null),
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
        final button = Focus(
          focusNode: node,
          onKeyEvent: _onKey,
          child: ExcludeFocus(
            child: label != null
                ? TextButton(
                    onPressed: enabled ? onPressed : () {},
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      fixedSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      backgroundColor:
                          focused ? AvenColors.focusFill : Colors.transparent,
                      foregroundColor:
                          focused ? AvenColors.onFocus : AvenColors.text,
                      overlayColor: Colors.transparent,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      label!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : IconButton(
                    onPressed: enabled ? onPressed : () {},
                    icon: Icon(icon),
                    iconSize: 22,
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      fixedSize: const Size(44, 44),
                      backgroundColor:
                          focused ? AvenColors.focusFill : Colors.transparent,
                      overlayColor: Colors.transparent,
                      foregroundColor: focused
                          ? AvenColors.onFocus
                          : !enabled
                              ? AvenColors.textMuted
                              : AvenColors.text,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
          ),
        );

        return SizedBox(
          width: label != null ? 52 : 48,
          height: 70,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              AvenFocusZoom(
                focused: focused,
                scale: 1.0,
                borderRadius: 10,
                showHalo: false,
                child: button,
              ),
              if (focused)
                Positioned(
                  bottom: 50,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AvenColors.elevated,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      child: Text(
                        tooltip,
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.15,
                          color: AvenColors.text,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
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
      color: AvenColors.text.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(avenText('aven_webview_old')),
      ),
    );
  }
}

class _OpeningPlayerOverlay extends StatelessWidget {
  const _OpeningPlayerOverlay();

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: ColoredBox(
        color: AvenColors.barrier,
        child: Center(
          child: Material(
            elevation: 16,
            color: AvenColors.panel.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AvenColors.text,
                    ),
                  ),
                  SizedBox(width: 16),
                  Text(
                    avenText('aven_player_opening'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AvenColors.text,
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

/// Phone menu: round quick action with a label under it.
class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final ink = AvenTone.text(context);
    final circle = active ? ink : AvenTone.elevated(context);
    final glyph = active ? AvenTone.background(context) : ink;
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        // Icons line up across a row even when a label wraps to two lines.
        child: Column(
          children: [
            const SizedBox(height: 4),
            DecoratedBox(
              decoration: BoxDecoration(color: circle, shape: BoxShape.circle),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(icon, size: 22, color: glyph),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.2, color: ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// Phone menu: rounded group of page options.
class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final divider = AvenTone.text(context).withValues(alpha: 0.07);
    return Material(
      color: AvenTone.elevated(context),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 56, color: divider),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Phone menu: option with a switch on the right.
class _MenuSwitch extends StatelessWidget {
  const _MenuSwitch({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: InkWell(
        onTap: onChanged,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AvenTone.text(context)),
              const SizedBox(width: 18),
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 15)),
              ),
              Switch(
                value: value,
                // The theme's off track is the card colour; keep it visible here.
                inactiveTrackColor: AvenTone.background(context),
                onChanged: enabled ? (_) => onChanged!() : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phone menu: zoom stepper; the value updates while the sheet is open.
class _MenuZoom extends StatelessWidget {
  const _MenuZoom({
    required this.zoom,
    required this.onOut,
    required this.onIn,
    required this.onReset,
  });

  final int zoom;
  final VoidCallback onOut;
  final VoidCallback onIn;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final ink = AvenTone.text(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Icon(Icons.text_fields, size: 22, color: ink),
          const SizedBox(width: 18),
          Expanded(child: Text(avenText('aven_zoom'), style: const TextStyle(fontSize: 15))),
          IconButton(onPressed: zoom > 50 ? onOut : null, icon: const Icon(Icons.remove)),
          InkWell(
            onTap: onReset,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Text(
                '$zoom%',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          IconButton(onPressed: zoom < 300 ? onIn : null, icon: const Icon(Icons.add)),
        ],
      ),
    );
  }
}

/// Phone menu: wide rounded button at the bottom.
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = AvenTone.text(context);
    return Opacity(
      opacity: onTap != null ? 1 : 0.38,
      child: Material(
        color: AvenTone.elevated(context),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: ink),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
