import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/aven_theme.dart';
import '../../data/settings_store.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.store, this.initialSection = 0});

  final BrowserStore store;
  final int initialSection;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  static const _sections = ['Yer imleri', 'Geçmiş'];
  static const _icons = [Icons.star_outline, Icons.history];
  static const _linkLimit = 40;

  int _section = 0;
  bool _onLeft = true;
  List<WebLink> _bookmarks = const [];
  List<WebLink> _history = const [];
  late final List<FocusNode> _leftFocus =
      List.generate(_sections.length, (index) => FocusNode(debugLabel: 'library-left-$index'));
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
    super.dispose();
  }

  List<WebLink> get _visibleLinks {
    final source = _section == 0 ? _bookmarks : _history;
    return source.take(_linkLimit).toList();
  }

  int get _rightCount {
    final links = _visibleLinks;
    if (links.isEmpty) return 1;
    if (_section == 1) return links.length + 1; // clear button first
    return links.length;
  }

  Future<void> _load() async {
    final bookmarks = await widget.store.loadBookmarks();
    final history = await widget.store.loadHistory();
    if (!mounted) return;
    setState(() {
      _bookmarks = bookmarks;
      _history = history;
    });
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
    await widget.store.clearHistory();
    if (!mounted) return;
    setState(() => _history = const []);
    _focusLeft(1);
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
    return Scaffold(
      backgroundColor: AvenColors.accentBlue,
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: _onLeft ? 240 : 84,
            child: ClipRect(
              child: Material(
                color: AvenColors.surface,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                      child: SizedBox(
                        height: 22,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Opacity(
                            opacity: _onLeft ? 1 : 0,
                            child: const Text('Kitaplık', style: TextStyle(fontSize: 18)),
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
          ),
          const VerticalDivider(width: 1, color: AvenColors.row),
          Expanded(child: _panel()),
        ],
      ),
    );
  }

  Widget _panel() {
    final links = _visibleLinks;
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text(
          _section == 0 ? 'Yer imleri' : 'Geçmiş',
          style: const TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 16),
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
            title: 'Geçmişi temizle',
            subtitle: links.isEmpty ? 'Geçmiş boş.' : '${links.length} kayıt silinir.',
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
            title: 'Henüz yer imi yok',
            subtitle: 'Siteleri menüden kaydedebilirsin.',
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
            color: focused ? AvenColors.danger : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              hoverColor: AvenColors.danger.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.delete_outline,
                  size: 22,
                  color: focused ? AvenColors.mist : AvenColors.textMuted,
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
            scale: 1.05,
            child: Material(
            color: focused
                ? AvenColors.hover
                : selected
                ? AvenColors.row
                : Colors.transparent,
            child: IconTheme(
              data: IconThemeData(
                color: AvenColors.text,
              ),
              child: DefaultTextStyle.merge(
                style: const TextStyle(
                  color: AvenColors.text,
                ),
                child: InkWell(
                  onTap: onTap,
                  hoverColor: AvenColors.hover,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(width: 28, height: 28, child: Center(child: leading)),
                        if (title != null && !compact) ...[
                          const SizedBox(width: 14),
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
                                        color: focused
                                            ? AvenColors.text.withValues(alpha: 0.75)
                                            : AvenColors.textMuted,
                                      ),
                                    ),
                                  ),
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
