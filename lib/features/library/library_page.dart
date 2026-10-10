import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/aven_strings.dart';
import '../../core/platform/aven_flavor.dart';
import '../../core/theme/aven_theme.dart';
import '../../core/platform/aven_layout.dart';
import '../../data/settings_store.dart';
import '../browser/gecko_engine.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.store, this.initialSection = 0});

  final BrowserStore store;
  final int initialSection;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<String> get _sections => AvenFlavor.isMobile
      ? [avenText('aven_bookmarks'), avenText('aven_history'), avenText('aven_downloads')]
      : [avenText('aven_bookmarks'), avenText('aven_history')];
  static List<IconData> get _icons => AvenFlavor.isMobile
      ? const [Icons.star_outline, Icons.history, Icons.download_outlined]
      : const [Icons.star_outline, Icons.history];
  static const _linkLimit = 40;

  int _section = 0;
  bool _onLeft = true;
  List<WebLink> _bookmarks = const [];
  List<WebLink> _history = const [];
  List<Map<String, String>> _downloads = const [];
  Timer? _downloadPoll;
  late final List<FocusNode> _leftFocus = List.generate(
    AvenFlavor.isMobile ? 3 : 2,
    (index) => FocusNode(debugLabel: 'library-left-$index'),
  );
  late final List<FocusNode> _rightFocus =
      List.generate(_linkLimit + 2, (index) => FocusNode(debugLabel: 'library-right-$index'));
  late final List<FocusNode> _deleteFocus =
      List.generate(_linkLimit, (index) => FocusNode(debugLabel: 'library-delete-$index'));

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection.clamp(0, _sections.length - 1);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusLeft(_section));
  }

  @override
  void dispose() {
    for (final node in _leftFocus) {
      node.dispose();
    }
    for (final node in _rightFocus) {
      node.dispose();
    }
    for (final node in _deleteFocus) {
      node.dispose();
    }
    _downloadPoll?.cancel();
    super.dispose();
  }

  bool get _downloadsActive => _downloads.any((item) {
        final status = item['status'];
        return downloadIsActive(status);
      });

  void _syncDownloadPoll() {
    final watch = _section == 2 && _downloadsActive;
    if (watch && _downloadPoll == null) {
      _downloadPoll = Timer.periodic(const Duration(milliseconds: 700), (_) {
        unawaited(_refreshDownloads());
      });
    } else if (!watch) {
      _downloadPoll?.cancel();
      _downloadPoll = null;
    }
  }

  Future<void> _refreshDownloads() async {
    if (!AvenFlavor.isMobile) return;
    final downloads = await GeckoPageEngine.fetchDownloads();
    if (!mounted) return;
    setState(() => _downloads = downloads);
    _syncDownloadPoll();
  }

  String _downloadLabel(Map<String, String> item) {
    return downloadStatusLabel(item['status'], item['progress']);
  }

  Widget _downloadActions(Map<String, String> item) {
    final id = item['id'] ?? '';
    final done = item['status'] == 'success';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (done)
          IconButton(
            tooltip: avenText('aven_open'),
            onPressed: id.isEmpty ? null : () => unawaited(GeckoPageEngine.openSaved(id)),
            icon: const Icon(Icons.open_in_new, size: 20),
          ),
        IconButton(
          tooltip: done ? avenText('aven_delete') : avenText('aven_cancel'),
          onPressed: id.isEmpty
              ? null
              : () async {
                  await GeckoPageEngine.cancelDownload(id);
                  await _refreshDownloads();
                },
          icon: Icon(done ? Icons.delete_outline : Icons.close, size: 20),
        ),
      ],
    );
  }

  double _downloadProgress(Map<String, String> item) {
    if (item['status'] == 'success') return 1;
    final raw = int.tryParse(item['progress'] ?? '') ?? -1;
    if (raw < 0) return -1;
    return raw / 100;
  }

  List<WebLink> get _visibleLinks {
    if (_section == 2) return const [];
    final source = _section == 0 ? _bookmarks : _history;
    return source.take(_linkLimit).toList();
  }

  int get _rightCount {
    if (_section == 2) return _downloads.isEmpty ? 1 : _downloads.length;
    final links = _visibleLinks;
    if (links.isEmpty) return 1;
    if (_section == 1) return links.length + 1; // clear button first
    return links.length;
  }

  Future<void> _load() async {
    final bookmarks = await widget.store.loadBookmarks();
    final history = await widget.store.loadHistory();
    final downloads = AvenFlavor.isMobile
        ? await GeckoPageEngine.fetchDownloads()
        : const <Map<String, String>>[];
    if (!mounted) return;
    setState(() {
      _bookmarks = bookmarks;
      _history = history;
      _downloads = downloads;
    });
    _syncDownloadPoll();
  }

  Future<void> _removeBookmarkAt(int linkIndex) async {
    final links = _visibleLinks;
    if (linkIndex < 0 || linkIndex >= links.length) return;
    final target = links[linkIndex];
    final next = await widget.store.saveBookmarks(
      _bookmarks.where((item) => item.url != target.url).toList(),
    );
    if (!mounted) return;
    setState(() => _bookmarks = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final count = _rightCount;
      if (count <= 0 || _bookmarks.isEmpty) {
        _focusLeft(_section);
        return;
      }
      final nextIndex = linkIndex.clamp(0, count - 1);
      _requestRight(nextIndex);
    });
  }

  Future<void> _clearHistory() async {
    final range = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AvenTone.elevated(context),
      showDragHandle: true,
      builder: (context) {
        void pick(String value) => Navigator.pop(context, value);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  avenText('aven_clear_history'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              ListTile(title: Text(avenText('aven_range_15m')), onTap: () => pick('15m')),
              ListTile(title: Text(avenText('aven_range_1h')), onTap: () => pick('1h')),
              ListTile(title: Text(avenText('aven_range_24h')), onTap: () => pick('24h')),
              ListTile(title: Text(avenText('aven_range_7d')), onTap: () => pick('7d')),
              ListTile(title: Text(avenText('aven_range_4w')), onTap: () => pick('4w')),
              ListTile(title: Text(avenText('aven_range_all')), onTap: () => pick('all')),
            ],
          ),
        );
      },
    );
    if (range == null || !mounted) return;
    final newerThan = switch (range) {
      '15m' => const Duration(minutes: 15),
      '1h' => const Duration(hours: 1),
      '24h' => const Duration(hours: 24),
      '7d' => const Duration(days: 7),
      '4w' => const Duration(days: 28),
      _ => null,
    };
    await widget.store.clearHistory(newerThan: newerThan);
    if (!mounted) return;
    setState(() => _history = const []);
    await _load();
    if (mounted) _focusLeft(1);
  }

  void _ensureVisible(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = node.context;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _requestRight(int index) {
    final count = _rightCount;
    if (count <= 0) return;
    final node = _rightFocus[index.clamp(0, count - 1)];
    node.requestFocus();
    _ensureVisible(node);
  }

  void _requestDelete(int linkIndex) {
    final links = _visibleLinks;
    if (linkIndex < 0 || linkIndex >= links.length) return;
    final node = _deleteFocus[linkIndex];
    node.requestFocus();
    _ensureVisible(node);
  }

  void _focusLeft(int index) {
    if (!_onLeft) setState(() => _onLeft = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _leftFocus[index.clamp(0, _leftFocus.length - 1)];
      node.requestFocus();
    });
  }

  void _focusRight([int index = 0]) {
    if (_onLeft) setState(() => _onLeft = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestRight(index);
    });
  }

  KeyEventResult _onLeftKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown && index < _sections.length - 1) {
      setState(() => _section = index + 1);
      _leftFocus[index + 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && index > 0) {
      setState(() => _section = index - 1);
      _leftFocus[index - 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space) {
      setState(() => _section = index);
      _focusRight();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onRightKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final count = _rightCount;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _focusLeft(_section);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight && _section == 0 && _bookmarks.isNotEmpty) {
      final linkIndex = index;
      if (linkIndex >= 0 && linkIndex < _visibleLinks.length) {
        _requestDelete(linkIndex);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowDown && index < count - 1) {
      _requestRight(index + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && index > 0) {
      _requestRight(index - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      if (_section == 0 && _bookmarks.isNotEmpty) {
        final linkIndex = index;
        if (linkIndex >= 0 && linkIndex < _visibleLinks.length) {
          _removeBookmarkAt(linkIndex);
          return KeyEventResult.handled;
        }
      }
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space) {
      _activateRight(index);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onDeleteKey(int linkIndex, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final count = _visibleLinks.length;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _requestRight(linkIndex);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && linkIndex < count - 1) {
      _requestRight(linkIndex + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && linkIndex > 0) {
      _requestRight(linkIndex - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      _removeBookmarkAt(linkIndex);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _activateRight(int index) {
    if (_section == 2) {
      if (index < 0 || index >= _downloads.length) return;
      final item = _downloads[index];
      final id = item['id'] ?? '';
      if (item['status'] == 'success' && id.isNotEmpty) {
        unawaited(GeckoPageEngine.openSaved(id));
      }
      return;
    }
    final links = _visibleLinks;
    if (_section == 1) {
      if (index == 0) {
        if (_history.isNotEmpty) _clearHistory();
        return;
      }
      final link = links[index - 1];
      Navigator.pop(context, link.url);
      return;
    }
    if (links.isEmpty) return;
    Navigator.pop(context, links[index].url);
  }

  @override
  Widget build(BuildContext context) {
    final compact = AvenLayout.isCompact(context);
    return Scaffold(
      backgroundColor: compact
          ? Theme.of(context).scaffoldBackgroundColor
          : AvenColors.accentBlue,
      body: SafeArea(
        child: compact
            ? Column(
                children: [
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        Expanded(
                          child: Text(
                            avenText('aven_library'),
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (var index = 0; index < _sections.length; index++)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              selected: _section == index,
                              label: Text(_sections[index]),
                              onSelected: (_) {
                                setState(() => _section = index);
                                _syncDownloadPoll();
                                _focusRight();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AvenColors.elevated),
                  Expanded(child: _panel(compact: true)),
                ],
              )
            : Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    width: _onLeft ? 272 : 96,
                    child: Material(
                      color: AvenColors.surface,
                      clipBehavior: Clip.none,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                        clipBehavior: Clip.none,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                            child: SizedBox(
                              height: 22,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Opacity(
                                  opacity: _onLeft ? 1 : 0,
                                  child: Text(
                                    avenText('aven_library'),
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          for (var index = 0; index < _sections.length; index++)
                            _LibraryTile(
                              focusNode: _leftFocus[index],
                              autofocus: index == widget.initialSection,
                              selected: _section == index,
                              compact: !_onLeft,
                              onKeyEvent: (event) => _onLeftKey(index, event),
                              onFocus: () {
                                if (_section == index && _onLeft) return;
                                setState(() {
                                  _section = index;
                                  _onLeft = true;
                                });
                              },
                              onTap: () {
                                setState(() => _section = index);
                                _focusRight();
                              },
                              leading: Icon(_icons[index], size: 24),
                              title: _sections[index],
                            ),
                        ],
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1, color: AvenColors.row),
                  Expanded(child: _panel()),
                ],
              ),
      ),
    );
  }

  Widget _panel({bool compact = false}) {
    final links = _visibleLinks;
    return ListView(
      padding: EdgeInsets.all(compact ? 16 : 28),
      clipBehavior: Clip.none,
      children: [
        Text(
          _sections[_section],
          style: const TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 16),
        if (_section == 2 && _downloads.isEmpty)
          _LibraryTile(
            focusNode: _rightFocus[0],
            selected: false,
            onKeyEvent: (event) => _onRightKey(0, event),
            onTap: () {},
            leading: const Icon(Icons.download_outlined, size: 24),
            title: avenText('aven_no_downloads'),
            subtitle: avenText('aven_no_downloads_detail'),
          ),
        if (_section == 2)
          for (var index = 0; index < _downloads.length; index++)
            _LibraryTile(
              focusNode: _rightFocus[index],
              selected: false,
              onKeyEvent: (event) => _onRightKey(index, event),
              onTap: () => _activateRight(index),
              leading: const Icon(Icons.download_done, size: 24),
              title: _downloads[index]['title']?.isNotEmpty == true
                  ? _downloads[index]['title']
                  : avenText('aven_download'),
              subtitle: _downloadLabel(_downloads[index]),
              progress: _downloadProgress(_downloads[index]),
              trailing: _downloadActions(_downloads[index]),
            ),
        if (_section == 1)
          _LibraryTile(
            focusNode: _rightFocus[0],
            selected: false,
            onKeyEvent: (event) => _onRightKey(0, event),
            onFocus: () {
              if (_onLeft) setState(() => _onLeft = false);
              _ensureVisible(_rightFocus[0]);
            },
            onTap: () => _activateRight(0),
            leading: const Icon(Icons.delete_outline, size: 24),
            title: avenText('aven_clear_history'),
            subtitle: links.isEmpty
                ? avenText('aven_history_empty')
                : avenText('aven_history_count', [links.length]),
          ),
        if (links.isEmpty && _section == 0)
          _LibraryTile(
            focusNode: _rightFocus[0],
            selected: false,
            onKeyEvent: (event) => _onRightKey(0, event),
            onFocus: () {
              if (_onLeft) setState(() => _onLeft = false);
              _ensureVisible(_rightFocus[0]);
            },
            onTap: () {},
            leading: const Icon(Icons.info_outline, size: 24),
            title: avenText('aven_no_bookmarks'),
            subtitle: avenText('aven_no_bookmarks_detail'),
          ),
        if (links.isEmpty && _section == 1)
          const SizedBox.shrink()
        else
          for (var index = 0; index < links.length; index++)
            _LibraryTile(
              focusNode: _rightFocus[_section == 1 ? index + 1 : index],
              selected: false,
              onKeyEvent: (event) => _onRightKey(_section == 1 ? index + 1 : index, event),
              onFocus: () {
                if (_onLeft) setState(() => _onLeft = false);
                _ensureVisible(_rightFocus[_section == 1 ? index + 1 : index]);
              },
              onTap: () => _activateRight(_section == 1 ? index + 1 : index),
              leading: _Favicon(url: links[index].url),
              title: links[index].title,
              subtitle: links[index].url,
              trailing: _section == 0
                  ? _DeleteButton(
                      focusNode: _deleteFocus[index],
                      onKeyEvent: (event) => _onDeleteKey(index, event),
                      onTap: () => _removeBookmarkAt(index),
                    )
                  : null,
            ),
      ],
    );
  }
}

class _Favicon extends StatelessWidget {
  const _Favicon({required this.url});

  final String url;

  String get _src {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty) return '';
    return 'https://www.google.com/s2/favicons?domain=$host&sz=64';
  }

  @override
  Widget build(BuildContext context) {
    if (_src.isEmpty) {
      return const Icon(Icons.public, size: 24);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        _src,
        width: 24,
        height: 24,
        errorBuilder: (context, error, stack) => const Icon(Icons.public, size: 24),
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({
    required this.focusNode,
    required this.onKeyEvent,
    required this.onTap,
  });

  final FocusNode focusNode;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final VoidCallback onTap;

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
            child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              hoverColor: Colors.transparent,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.delete_outline,
                  size: 22,
                  color: AvenTone.textMuted(context),
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

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.focusNode,
    required this.selected,
    required this.onKeyEvent,
    required this.onTap,
    required this.leading,
    this.title,
    this.subtitle,
    this.progress,
    this.trailing,
    this.autofocus = false,
    this.compact = false,
    this.onFocus,
  });

  final FocusNode focusNode;
  final bool selected;
  final bool autofocus;
  final bool compact;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final VoidCallback onTap;
  final VoidCallback? onFocus;
  final Widget leading;
  final String? title;
  final String? subtitle;
  final double? progress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      autofocus: autofocus,
      onKeyEvent: (node, event) => onKeyEvent(event),
      onFocusChange: (focused) {
        if (focused) onFocus?.call();
      },
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          return AvenFocusZoom(
            focused: focused,
            scale: 1.0,
            borderRadius: 10,
            child: Material(
            color: selected
                ? AvenTone.text(context).withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.none,
            child: IconTheme(
              data: IconThemeData(
                color: AvenTone.text(context),
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: AvenTone.text(context),
                ),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(10),
                  hoverColor: Colors.transparent,
                  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 10 : 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: 28, height: 28, child: Center(child: leading)),
                        if (title != null && !compact) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                if (subtitle != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      subtitle!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AvenTone.textMuted(context),
                                      ),
                                    ),
                                  ),
                                if (progress != null) ...[
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: progress! < 0 ? null : progress!.clamp(0, 1),
                                    minHeight: 3,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        if (trailing != null && !compact) ...[
                          const SizedBox(width: 8),
                          trailing!,
                        ],
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
