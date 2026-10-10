import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/aven_strings.dart';
import '../../core/theme/aven_theme.dart';
import '../../core/platform/aven_flavor.dart';
import '../../core/platform/aven_layout.dart';
import '../../core/aven_app_info.dart';
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
  List<String> get _sections => [
    avenText('aven_adblock'),
    avenText('aven_home_screen'),
    avenText('aven_search'),
    avenText('aven_performance'),
    avenText('aven_browser'),
    avenText('aven_about'),
  ];
  static const _icons = [
    Icons.shield_outlined,
    Icons.home_outlined,
    Icons.search,
    Icons.speed,
    Icons.language,
    Icons.info_outline,
  ];

  // off → local → DNS; default → desktop → mobile → tv; engines keep enum order.
  static const _engines = SearchEngine.values;
  static const _blocks = AdBlock.values;
  static const _agents = BrowserAgent.values;

  int _section = 0;
  bool _onLeft = true;
  SearchEngine _engine = SearchEngine.google;
  AdBlock _block = AdBlock.off;
  BrowserAgent _agent = BrowserAgent.defaultAgent;
  bool _lite = false;
  bool _homeSuggestions = true;
  late final List<FocusNode> _leftFocus =
      List.generate(6, (index) => FocusNode(debugLabel: 'settings-left-$index'));
  late final List<FocusNode> _rightFocus =
      List.generate(10, (index) => FocusNode(debugLabel: 'settings-right-$index'));

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || AvenLayout.isCompact(context)) return;
      _focusLeft(0);
    });
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
    final lite = await widget.store.loadLiteBrowsing(fallback: !AvenFlavor.isMobile);
    final homeSuggestions = await widget.store.loadHomeSuggestions();
    if (!mounted) return;
    setState(() {
      _engine = engine;
      _block = block;
      _agent = agent;
      _lite = lite;
      _homeSuggestions = homeSuggestions;
    });
  }

  Future<void> _selectBlock(AdBlock block) async {
    await widget.store.saveAdBlock(block);
    // DNS/VPN only for the DNS engelleme mode — yerel liste VPN istemez.
    await widget.input.setAdBlock(block.name, connectDns: block.usesDns);
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

  Future<void> _selectTheme(String choice) async {
    await widget.store.saveThemeChoice(choice);
    avenThemeChoice.value = choice;
    if (mounted) setState(() {});
  }

  Future<void> _selectHomeSuggestions(bool enabled) async {
    await widget.store.saveHomeSuggestions(enabled);
    if (!mounted) return;
    setState(() => _homeSuggestions = enabled);
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
    0 => _blocks.length,
    1 => 2,
    2 => _engines.length,
    3 => 2,
    4 => _agents.length,
    _ => 2, // Hakkında
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
        _selectBlock(_blocks[index]);
      case 1:
        // Göster, Gizle
        _selectHomeSuggestions(index == 0);
      case 2:
        _selectEngine(_engines[index]);
      case 3:
        _selectLite(index == 0);
      case 4:
        _selectAgent(_agents[index]);
      default:
        break;
    }
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
            ? _phoneSettings(context)
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
                                    avenText('aven_settings'),
                                    style: const TextStyle(fontSize: 18),
                                  ),
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
                  const VerticalDivider(width: 1, color: AvenColors.accentBlue),
                  Expanded(child: _panel()),
                ],
              ),
      ),
    );
  }

  Widget _phoneSettings(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 28),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(avenText('aven_settings'), style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
        _PhoneSettingsHeading(avenText('aven_adblock')),
        for (final block in _blocks)
          _PhoneSettingsOption(
            title: block.label,
            subtitle: block.detail,
            selected: _block == block,
            onTap: () => _selectBlock(block),
          ),
        _PhoneSettingsHeading(avenText('aven_search')),
        for (final engine in _engines)
          _PhoneSettingsOption(
            title: engine.label,
            selected: _engine == engine,
            onTap: () => _selectEngine(engine),
          ),
        _PhoneSettingsHeading(avenText('aven_appearance')),
        _PhoneSettingsOption(
          title: avenText('aven_theme_system'),
          subtitle: avenText('aven_theme_system_detail'),
          selected: avenThemeChoice.value == 'system',
          onTap: () => _selectTheme('system'),
        ),
        _PhoneSettingsOption(
          title: avenText('aven_theme_light'),
          subtitle: avenText('aven_theme_light_detail'),
          selected: avenThemeChoice.value == 'light',
          onTap: () => _selectTheme('light'),
        ),
        _PhoneSettingsOption(
          title: avenText('aven_theme_dark'),
          subtitle: avenText('aven_theme_dark_detail'),
          selected: avenThemeChoice.value == 'dark',
          onTap: () => _selectTheme('dark'),
        ),
        _PhoneSettingsHeading(avenText('aven_performance')),
        _PhoneSettingsOption(
          title: avenText('aven_on'),
          subtitle: avenText('aven_perf_on_detail'),
          selected: _lite,
          onTap: () => _selectLite(true),
        ),
        _PhoneSettingsOption(
          title: avenText('aven_off'),
          subtitle: avenText('aven_perf_off_detail'),
          selected: !_lite,
          onTap: () => _selectLite(false),
        ),
        _PhoneSettingsHeading(avenText('aven_about')),
        _PhoneSettingsOption(
          title: avenText('aven_version'),
          subtitle: AvenAppInfo.version,
          icon: Icons.tag,
          selected: false,
          onTap: () {},
        ),
        _PhoneSettingsOption(
          title: avenText('aven_developer'),
          subtitle: AvenAppInfo.developer,
          icon: Icons.public,
          selected: false,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _panel({bool compact = false}) {
    if (_section == 5) {
      return ListView(
        padding: EdgeInsets.all(compact ? 16 : 28),
        clipBehavior: Clip.none,
        children: [
          Text(
            AvenAppInfo.name,
            style: TextStyle(
              fontFamily: 'Cal Sans',
              fontSize: compact ? 28 : 34,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.6,
              color: AvenColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            avenText('aven_about'),
            style: const TextStyle(fontSize: 16, color: AvenColors.textMuted),
          ),
          const SizedBox(height: 20),
          _FocusTile(
            focusNode: _rightFocus[0],
            selected: false,
            onKeyEvent: (event) => _onRightKey(0, event),
            onTap: () {},
            leading: const Icon(Icons.tag, size: 22),
            title: avenText('aven_version'),
            subtitle: AvenAppInfo.version,
          ),
          _FocusTile(
            focusNode: _rightFocus[1],
            selected: false,
            onKeyEvent: (event) => _onRightKey(1, event),
            onTap: () {},
            leading: const Icon(Icons.public, size: 22),
            title: avenText('aven_developer'),
            subtitle: AvenAppInfo.developer,
          ),
        ],
      );
    }

    final items = switch (_section) {
      0 => [
        for (final block in _blocks)
          (
            block.label,
            block.detail,
            _block == block,
          ),
      ],
      1 => [
        (
          avenText('aven_show'),
          avenText('aven_show_detail'),
          _homeSuggestions,
        ),
        (
          avenText('aven_hide'),
          avenText('aven_hide_detail'),
          !_homeSuggestions,
        ),
      ],
      2 => [
        for (final engine in _engines)
          (
            engine.label,
            null as String?,
            _engine == engine,
          ),
      ],
      3 => [
        (
          avenText('aven_on'),
          avenText('aven_perf_on_detail'),
          _lite,
        ),
        (
          avenText('aven_off'),
          avenText('aven_perf_off_detail'),
          !_lite,
        ),
      ],
      _ => [
        for (final agent in _agents)
          (
            agent.label,
            agent.detail,
            _agent == agent,
          ),
      ],
    };

    return ListView(
      padding: EdgeInsets.all(compact ? 16 : 28),
      clipBehavior: Clip.none,
      children: [
        Text(
          switch (_section) {
            0 => avenText('aven_adblock'),
            1 => avenText('aven_home_suggestions'),
            2 => avenText('aven_search_engine'),
            3 => avenText('aven_lite'),
            _ => avenText('aven_user_agent'),
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

class _PhoneSettingsHeading extends StatelessWidget {
  const _PhoneSettingsHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, color: AvenTone.textMuted(context)),
      ),
    );
  }
}

class _PhoneSettingsOption extends StatelessWidget {
  const _PhoneSettingsOption({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(
        icon ?? (selected ? Icons.radio_button_checked : Icons.radio_button_off),
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
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
            scale: 1.0,
            borderRadius: 10,
            child: Material(
            color: selected
                ? AvenColors.text.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.none,
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
                    SizedBox(width: 24, child: leading),
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
