import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/aven_theme.dart';
import '../../core/url/url_input.dart';
import '../../data/settings_store.dart';
import '../../platform/web_input.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store, required this.input});

  final BrowserStore store;
  final WebInput input;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _sections = ['Arama', 'Ağ', 'Tarayıcı', 'Performans'];
  static const _icons = [Icons.search, Icons.lan, Icons.language, Icons.speed];

  int _section = 0;
  bool _onLeft = true;
  SearchEngine _engine = SearchEngine.google;
  AdBlock _block = AdBlock.off;
  BrowserAgent _agent = BrowserAgent.defaultAgent;
  bool _lite = false;
  late final List<FocusNode> _leftFocus =
      List.generate(_sections.length, (index) => FocusNode(debugLabel: 'settings-left-$index'));
  late final List<FocusNode> _rightFocus =
      List.generate(10, (index) => FocusNode(debugLabel: 'settings-right-$index'));

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusLeft(0));
  }

  @override
  void dispose() {
    for (final node in _leftFocus) {
      node.dispose();
    }
    for (final node in _rightFocus) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final engine = await widget.store.loadEngine();
    final block = await widget.store.loadAdBlock();
    final agent = await widget.store.loadAgent();
    final lite = await widget.store.loadLiteBrowsing();
    if (!mounted) return;
    setState(() {
      _engine = engine;
      _block = block;
      _agent = agent;
      _lite = lite;
    });
  }

  Future<void> _selectBlock(AdBlock block) async {
    await widget.store.saveAdBlock(block);
    await widget.input.setAdBlock(block.name);
    if (!mounted) return;
    setState(() => _block = block);
  }

  Future<void> _selectEngine(SearchEngine engine) async {
    await widget.store.saveEngine(engine);
    if (!mounted) return;
    setState(() => _engine = engine);
  }

  Future<void> _selectAgent(BrowserAgent agent) async {
    await widget.store.saveAgent(agent);
    if (!mounted) return;
    setState(() => _agent = agent);
  }

  Future<void> _selectLite(bool enabled) async {
    await widget.store.saveLiteBrowsing(enabled);
    if (!mounted) return;
    setState(() => _lite = enabled);
  }

  void _focusLeft(int index) {
    if (!_onLeft) setState(() => _onLeft = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _leftFocus[index.clamp(0, _leftFocus.length - 1)].requestFocus();
    });
  }

  void _focusRight([int index = 0]) {
    if (_onLeft) setState(() => _onLeft = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final count = _rightCount;
      if (count <= 0) return;
      _rightFocus[index.clamp(0, count - 1)].requestFocus();
    });
  }

  int get _rightCount => switch (_section) {
    0 => SearchEngine.values.length,
    1 => AdBlock.values.length,
    2 => BrowserAgent.values.length,
    _ => 2,
  };

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
    if (key == LogicalKeyboardKey.arrowDown && index < count - 1) {
      _rightFocus[index + 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && index > 0) {
      _rightFocus[index - 1].requestFocus();
      return KeyEventResult.handled;
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

  void _activateRight(int index) {
    switch (_section) {
      case 0:
        _selectEngine(SearchEngine.values[index]);
      case 1:
        _selectBlock(AdBlock.values[index]);
      case 2:
        _selectAgent(BrowserAgent.values[index]);
      default:
        _selectLite(index == 0);
    }
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
                            child: const Text('Ayarlar', style: TextStyle(fontSize: 18)),
                          ),
                        ),
                      ),
                    ),
                    for (var index = 0; index < _sections.length; index++)
                      _FocusTile(
                        focusNode: _leftFocus[index],
                        autofocus: index == 0,
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
          const VerticalDivider(width: 1, color: AvenColors.accentBlue),
          Expanded(child: _panel()),
        ],
      ),
    );
  }

  Widget _panel() {
    final items = switch (_section) {
      0 => [
        for (var index = 0; index < SearchEngine.values.length; index++)
          (
            SearchEngine.values[index].label,
            null as String?,
            _engine == SearchEngine.values[index],
          ),
      ],
      1 => [
        for (var index = 0; index < AdBlock.values.length; index++)
          (
            AdBlock.values[index].label,
            switch (AdBlock.values[index]) {
              AdBlock.off => 'Sistem DNS. Reklamlar engellenmez (film siteleri için önerilir).',
              AdBlock.adguard => 'Bilinen reklam ağları + kozmetik filtre (yerel mega liste yok).',
              AdBlock.ublock => 'Bilinen reklam ağları + kozmetik filtre (yerel mega liste yok).',
            },
            _block == AdBlock.values[index],
          ),
      ],
      2 => [
        for (var index = 0; index < BrowserAgent.values.length; index++)
          (
            BrowserAgent.values[index].label,
            BrowserAgent.values[index].detail,
            _agent == BrowserAgent.values[index],
          ),
      ],
      _ => [
        (
          'Açık',
          'Görseller açık kalır; animasyonlar kesilir, videolar durur, içerik tembel yüklenir.',
          _lite,
        ),
        (
          'Kapalı',
          'Siteler normal yüklenir.',
          !_lite,
        ),
      ],
    };

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text(
          switch (_section) {
            0 => 'Varsayılan arama motoru',
            1 => 'Reklam engelleme',
            2 => 'User agent',
            _ => 'Hafif gezinme',
          },
          style: const TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 16),
        for (var index = 0; index < items.length; index++)
          _FocusTile(
            focusNode: _rightFocus[index],
            selected: items[index].$3,
            onKeyEvent: (event) => _onRightKey(index, event),
            onTap: () => _activateRight(index),
            leading: Icon(
              items[index].$3 ? Icons.radio_button_checked : Icons.radio_button_off,
            ),
            title: items[index].$1,
            subtitle: items[index].$2,
          ),
      ],
    );
  }
}

class _FocusTile extends StatelessWidget {
  const _FocusTile({
    required this.focusNode,
    required this.selected,
    required this.onKeyEvent,
    required this.onTap,
    required this.leading,
    this.title,
    this.subtitle,
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
                ? AvenColors.surface
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
                    SizedBox(width: 24, child: leading),
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
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AvenColors.textMuted,
                                  ),
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
            ),
          ),
          );
        },
      ),
    );
  }
}
