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
      400 => 'Ge├ğersiz istek',
      401 => 'Giri┼ş gerekli',
      403 => 'Eri┼şim engellendi',
      404 => 'Sayfa bulunamad─▒',
      408 => '─░stek zaman a┼ş─▒m─▒',
      410 => 'Sayfa kald─▒r─▒ld─▒',
      429 => '├çok fazla istek',
      500 => 'Sunucu hatas─▒',
      502 => 'A─ş ge├ğidi hatas─▒',
      503 => 'Servis kullan─▒lam─▒yor',
      504 => 'A─ş ge├ğidi zaman a┼ş─▒m─▒',
      _ when code >= 500 => 'Sunucu hatas─▒',
      _ => 'Sayfa y├╝klenemedi',
    };
    return _PageError(
      code: code,
      title: title,
      detail: 'Sunucu $code kodu d├Ând├╝rd├╝.',
      url: url,
    );
  }

  factory _PageError.fromResource(WebResourceError error) {
    final type = error.errorType;
    final title = switch (type) {
      WebResourceErrorType.hostLookup => 'Site bulunamad─▒',
      WebResourceErrorType.timeout => 'Ba─şlant─▒ zaman a┼ş─▒m─▒',
      WebResourceErrorType.connect => 'Ba─şlant─▒ kurulamad─▒',
      WebResourceErrorType.failedSslHandshake => 'G├╝venli ba─şlant─▒ ba┼şar─▒s─▒z',
      WebResourceErrorType.tooManyRequests => '├çok fazla istek',
      WebResourceErrorType.unsafeResource => 'G├╝vensiz kaynak',
      WebResourceErrorType.webContentProcessTerminated => 'Sayfa ├ğ├Âkt├╝',
      WebResourceErrorType.badUrl => 'Ge├ğersiz adres',
      WebResourceErrorType.fileNotFound => 'Sayfa bulunamad─▒',
      _ => 'Sayfa y├╝klenemedi',
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
                            label: 'Ba┼şlang─▒├ğ',
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
                            label: 'Ge├ğmi┼ş',
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
                        '├ûneriler',
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
      (Icons.arrow_forward, '─░leri', widget.canForward, widget.onForward, null),
      (Icons.refresh, 'Yenile', true, widget.onReload, null),
      (Icons.home, 'Ba┼şlang─▒├ğ', true, widget.onHome, null),
      (widget.saved ? Icons.star : Icons.star_border, 'Yer imi', true, widget.onBookmark, null),
      (Icons.history, 'Kitapl─▒k', true, widget.onLibrary, null),
      (
        widget.adBlockOn ? Icons.shield : Icons.shield_outlined,
        widget.adBlockOn ? 'Engelleme a├ğ─▒k' : 'Engelleme kapal─▒',
        true,
        widget.onToggleAdBlock,
        null,
      ),
      (Icons.remove, 'Uzakla┼şt─▒r', true, widget.onZoomOut, null),
      (null, 'Yak─▒nla┼şt─▒rma', true, widget.onZoomReset, '%${widget.zoom}'),
      (Icons.add, 'Yak─▒nla┼şt─▒r', true, widget.onZoomIn, null),
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
          'Bu kutunun WebView s├╝r├╝m├╝ eski. Android System WebView g├╝ncellenirse siteler daha d├╝zg├╝n a├ğ─▒l─▒r.',
        ),
      ),
    );
  }
}

