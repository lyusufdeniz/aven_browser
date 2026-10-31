import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/aven_strings.dart';
import '../../core/theme/aven_theme.dart';
import '../../core/platform/aven_flavor.dart';
import '../../core/platform/aven_layout.dart';
import '../../core/aven_app_info.dart';
import '../../core/url/url_input.dart';
import '../../data/bookmark_file.dart';
import '../../data/error_reports.dart';
import '../../data/settings_store.dart';
import '../../platform/web_input.dart';
import '../player/subtitle_look.dart';

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
    avenText('aven_subtitles'),
    avenText('aven_about'),
  ];
  static const _icons = [
    Icons.shield_outlined,
    Icons.home_outlined,
    Icons.search,
    Icons.speed,
    Icons.language,
    Icons.closed_caption_outlined,
    Icons.info_outline,
  ];

  // off → local → DNS; default → desktop → mobile → tv; engines keep enum order.
  static const _engines = SearchEngine.values;
  static final _blocks = AdBlock.available;
  static const _agents = BrowserAgent.values;

  int _section = 0;
  bool _onLeft = true;
  SearchEngine _engine = SearchEngine.google;
  AdBlock _block = AdBlock.off;
  BrowserAgent _agent = BrowserAgent.defaultAgent;
  bool _lite = false;
  bool _homeSuggestions = true;
  bool _homeBookmarks = true;
  SubtitleStyle _subtitles = const SubtitleStyle();
  late final List<FocusNode> _leftFocus =
      List.generate(7, (index) => FocusNode(debugLabel: 'settings-left-$index'));
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
    final homeBookmarks = await widget.store.loadHomeBookmarks();
    final subtitles = await widget.store.loadSubtitleStyle();
    if (!mounted) return;
    setState(() {
      _subtitles = subtitles;
      _engine = engine;
      _block = block;
      _agent = agent;
      _lite = lite;
      _homeSuggestions = homeSuggestions;
      _homeBookmarks = homeBookmarks;
    });
  }

  Future<void> _selectBlock(AdBlock block) async {
    await widget.store.saveAdBlock(block);
    // DNS/VPN only for the DNS engelleme mode — yerel liste VPN istemez.
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

  Future<void> _selectTheme(String choice) async {
    await widget.store.saveThemeChoice(choice);
    avenThemeChoice.value = choice;
    if (mounted) setState(() {});
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  Future<void> _importBookmarks() async {
    final html = await WebInput.openDocument();
    if (html == null || !mounted) return;
    final found = BookmarkFile.parse(html);
    if (found.isEmpty) {
      _toast(avenText('aven_import_none'));
      return;
    }
    final current = await widget.store.loadBookmarks();
    final known = current.map((item) => item.url).toSet();
    final added = found.where((item) => !known.contains(item.url)).toList();
    await widget.store.saveBookmarks([...current, ...added]);
    if (mounted) _toast(avenText('aven_imported', [added.length]));
  }

  Future<void> _export(String file, String folder, List<WebLink> links) async {
    final ok = await WebInput.createDocument(file, BookmarkFile.build(folder, links));
    if (ok && mounted) _toast(avenText('aven_exported'));
  }

  Future<void> _showErrorReports() async {
    var reports = ErrorReports.load();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AvenTone.elevated(context),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              avenText('aven_error_reports'),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton(
                            onPressed: reports.isEmpty
                                ? null
                                : () => unawaited(WebInput.share(
                                      reports.map((item) => item.text).join('\n\n-----\n\n'),
                                    )),
                            child: Text(avenText('aven_share_reports')),
                          ),
                          TextButton(
                            onPressed: reports.isEmpty
                                ? null
                                : () {
                                    ErrorReports.clear();
                                    setLocal(() => reports = ErrorReports.load());
                                    setState(() {});
                                    _toast(avenText('aven_reports_cleared'));
                                  },
                            child: Text(avenText('aven_clear_reports')),
                          ),
                        ],
                      ),
                    ),
                    if (reports.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        child: Text(avenText('aven_error_reports_none')),
                      )
                    else
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final item in reports)
                              ListTile(
                                leading: const Icon(Icons.bug_report_outlined),
                                title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                                subtitle: Text(_stamp(item.at)),
                                onTap: () => unawaited(WebInput.share(item.text)),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _stamp(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
  }

  Future<void> _selectSubtitles(SubtitleStyle style) async {
    await widget.store.saveSubtitleStyle(style);
    if (!mounted) return;
    setState(() => _subtitles = style);
  }

  Future<void> _selectHomeBookmarks(bool enabled) async {
    await widget.store.saveHomeBookmarks(enabled);
    if (!mounted) return;
    setState(() => _homeBookmarks = enabled);
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
    1 => 4,
    2 => _engines.length,
    3 => 2,
    4 => _agents.length,
    5 => _subtitleOptionCount,
    _ => 2, // Hakkında
  };

  static final _subtitleOptionCount = SubtitleStyle.sizes.length +
      SubtitleStyle.backgrounds.length +
      SubtitleStyle.colors.length;

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
        // Suggestions: show, hide; bookmarks: show, hide.
        if (index < 2) {
          _selectHomeSuggestions(index == 0);
        } else {
          _selectHomeBookmarks(index == 2);
        }
      case 2:
        _selectEngine(_engines[index]);
      case 3:
        _selectLite(index == 0);
      case 4:
        _selectAgent(_agents[index]);
      case 5:
        _selectSubtitleOption(index);
      default:
        break;
    }
  }

  /// Subtitle rows run size → background → color in one focus list.
  void _selectSubtitleOption(int index) {
    const sizes = SubtitleStyle.sizes;
    const backgrounds = SubtitleStyle.backgrounds;
    if (index < sizes.length) {
      _selectSubtitles(_subtitles.copyWith(size: sizes[index]));
    } else if (index < sizes.length + backgrounds.length) {
      _selectSubtitles(
        _subtitles.copyWith(background: backgrounds[index - sizes.length]),
      );
    } else {
      _selectSubtitles(_subtitles.copyWith(
        color: SubtitleStyle.colors[index - sizes.length - backgrounds.length],
      ));
    }
  }

  /// Position of [value] in the size → background → color option list.
  static int _subtitleIndexOf(String value) => [
        ...SubtitleStyle.sizes,
        ...SubtitleStyle.backgrounds,
        ...SubtitleStyle.colors,
      ].indexOf(value);

  static String _subtitleOptionLabel(String value) => switch (value) {
        'small' => avenText('aven_size_small'),
        'medium' => avenText('aven_size_medium'),
        'large' => avenText('aven_size_large'),
        'xlarge' => avenText('aven_size_xlarge'),
        'none' => avenText('aven_subtitle_bg_none'),
        'shade' => avenText('aven_subtitle_bg_shade'),
        'solid' => avenText('aven_subtitle_bg_solid'),
        'white' => avenText('aven_color_white'),
        _ => avenText('aven_color_yellow'),
      };

  Widget _subtitlePanel(bool compact) {
    final groups = [
      (avenText('aven_subtitle_size'), SubtitleStyle.sizes, _subtitles.size),
      (
        avenText('aven_subtitle_background'),
        SubtitleStyle.backgrounds,
        _subtitles.background,
      ),
      (avenText('aven_subtitle_color'), SubtitleStyle.colors, _subtitles.color),
    ];
    final rows = <Widget>[];
    var index = 0;
    for (final group in groups) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 18));
      rows.add(_SectionLabel(group.$1));
      for (final value in group.$2) {
        final row = index++;
        rows.add(_SettingRow(
          focusNode: _rightFocus[row],
          onKeyEvent: (event) => _onRightKey(row, event),
          onTap: () => _activateRight(row),
          checked: value == group.$3,
          title: _subtitleOptionLabel(value),
        ));
      }
    }
    return ListView(
      padding: _panelPadding(compact),
      clipBehavior: Clip.none,
      children: [
        _SectionLabel(avenText('aven_subtitles')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            constraints: const BoxConstraints(minHeight: 120),
            alignment: Alignment.bottomCenter,
            padding: const EdgeInsets.fromLTRB(12, 28, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF5B6B7A), Color(0xFFB59A72)],
              ),
            ),
            child: SubtitleLook(
              text: avenText('aven_subtitle_preview'),
              style: _subtitles,
            ),
          ),
        ),
        ...rows,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = AvenLayout.isCompact(context);
    return Scaffold(
      backgroundColor: compact
          ? Theme.of(context).scaffoldBackgroundColor
          : AvenColors.background,
      body: SafeArea(
        child: compact
            ? _phoneSettings(context)
            : LayoutBuilder(
                builder: (context, box) {
                  final navWidth = (box.maxWidth * 0.34).clamp(200.0, 320.0);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: navWidth,
                        child: Material(
                          color: AvenColors.panel,
                          clipBehavior: Clip.none,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(12, 28, 12, 16),
                            clipBehavior: Clip.none,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
                                child: Text(
                                  avenText('aven_settings'),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              for (var index = 0; index < _sections.length; index++)
                                _FocusTile(
                                  focusNode: _leftFocus[index],
                                  autofocus: index == 0,
                                  selected: _section == index && !_onLeft,
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
                                  leading: Icon(_icons[index], size: 22),
                                  title: _sections[index],
                                ),
                            ],
                          ),
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        color: AvenColors.text.withValues(alpha: 0.06),
                      ),
                      Expanded(child: _panel()),
                    ],
                  );
                },
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
        for (final group in [
          (avenText('aven_subtitle_size'), SubtitleStyle.sizes, _subtitles.size),
          (
            avenText('aven_subtitle_background'),
            SubtitleStyle.backgrounds,
            _subtitles.background,
          ),
          (avenText('aven_subtitle_color'), SubtitleStyle.colors, _subtitles.color),
        ]) ...[
          _PhoneSettingsHeading('${avenText('aven_subtitles')} · ${group.$1}'),
          for (final value in group.$2)
            _PhoneSettingsOption(
              title: _subtitleOptionLabel(value),
              selected: value == group.$3,
              onTap: () => _selectSubtitleOption(
                _subtitleIndexOf(value),
              ),
            ),
        ],
        _PhoneSettingsHeading(avenText('aven_default_browser')),
        FutureBuilder<bool>(
          future: WebInput.isDefaultBrowser(),
          builder: (context, snapshot) {
            final isDefault = snapshot.data == true;
            return _PhoneSettingsOption(
              title: isDefault ? avenText('aven_default_is') : avenText('aven_default_set'),
              subtitle: isDefault ? null : avenText('aven_default_not'),
              icon: isDefault ? Icons.check_circle_outline : Icons.public,
              selected: false,
              onTap: () => unawaited(() async {
                final ok = await WebInput.requestDefaultBrowser();
                if (!mounted) return;
                setState(() {});
                if (ok) _toast(avenText('aven_default_is'));
              }()),
            );
          },
        ),
        _PhoneSettingsHeading(avenText('aven_data')),
        _PhoneSettingsOption(
          title: avenText('aven_import_bookmarks'),
          subtitle: avenText('aven_import_bookmarks_detail'),
          icon: Icons.file_download_outlined,
          selected: false,
          onTap: () => unawaited(_importBookmarks()),
        ),
        _PhoneSettingsOption(
          title: avenText('aven_export_bookmarks'),
          subtitle: avenText('aven_export_detail'),
          icon: Icons.file_upload_outlined,
          selected: false,
          onTap: () => unawaited(() async {
            await _export(
              'aven-bookmarks.html',
              avenText('aven_bookmarks'),
              await widget.store.loadBookmarks(),
            );
          }()),
        ),
        _PhoneSettingsOption(
          title: avenText('aven_export_history'),
          subtitle: avenText('aven_export_detail'),
          icon: Icons.history,
          selected: false,
          onTap: () => unawaited(() async {
            await _export(
              'aven-history.html',
              avenText('aven_history'),
              await widget.store.loadHistory(),
            );
          }()),
        ),
        _PhoneSettingsOption(
          title: avenText('aven_error_reports'),
          subtitle: () {
            final count = ErrorReports.load().length;
            return count == 0
                ? avenText('aven_error_reports_none')
                : avenText('aven_error_reports_detail', [count]);
          }(),
          icon: Icons.bug_report_outlined,
          selected: false,
          onTap: () => unawaited(_showErrorReports()),
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
    if (_section == 5) return _subtitlePanel(compact);
    if (_section == 1) {
      final rows = [
        (avenText('aven_show'), avenText('aven_show_detail'), _homeSuggestions),
        (avenText('aven_hide'), avenText('aven_hide_detail'), !_homeSuggestions),
        (avenText('aven_show'), avenText('aven_home_bookmarks_show'), _homeBookmarks),
        (avenText('aven_hide'), avenText('aven_home_bookmarks_hide'), !_homeBookmarks),
      ];
      Widget row(int index) => _SettingRow(
            focusNode: _rightFocus[index],
            onKeyEvent: (event) => _onRightKey(index, event),
            onTap: () => _activateRight(index),
            checked: rows[index].$3,
            title: rows[index].$1,
            subtitle: rows[index].$2,
          );
      return ListView(
        padding: _panelPadding(compact),
        clipBehavior: Clip.none,
        children: [
          _SectionLabel(avenText('aven_home_suggestions')),
          row(0),
          row(1),
          const SizedBox(height: 18),
          _SectionLabel(avenText('aven_home_bookmarks')),
          row(2),
          row(3),
        ],
      );
    }
    if (_section == 6) {
      return ListView(
        padding: _panelPadding(compact),
        clipBehavior: Clip.none,
        children: [
          _SectionLabel(avenText('aven_about')),
          _SettingRow(
            focusNode: _rightFocus[0],
            onKeyEvent: (event) => _onRightKey(0, event),
            onTap: () {},
            title: avenText('aven_version'),
            value: AvenAppInfo.version,
          ),
          _SettingRow(
            focusNode: _rightFocus[1],
            onKeyEvent: (event) => _onRightKey(1, event),
            onTap: () {},
            title: avenText('aven_developer'),
            value: AvenAppInfo.developer,
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
      padding: _panelPadding(compact),
      clipBehavior: Clip.none,
      children: [
        _SectionLabel(
          switch (_section) {
            0 => avenText('aven_adblock'),
            1 => avenText('aven_home_suggestions'),
            2 => avenText('aven_search_engine'),
            3 => avenText('aven_lite'),
            _ => avenText('aven_user_agent'),
          },
        ),
        for (var index = 0; index < items.length; index++)
          _SettingRow(
            focusNode: _rightFocus[index],
            onKeyEvent: (event) => _onRightKey(index, event),
            onTap: () => _activateRight(index),
            checked: items[index].$3,
            title: items[index].$1,
            subtitle: items[index].$2,
          ),
      ],
    );
  }

  EdgeInsets _panelPadding(bool compact) => compact
      ? const EdgeInsets.all(16)
      : const EdgeInsets.fromLTRB(16, 28, 20, 24);
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
    required this.title,
    this.autofocus = false,
    this.onFocus,
  });

  final FocusNode focusNode;
  final bool selected;
  final bool autofocus;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final VoidCallback onTap;
  final VoidCallback? onFocus;
  final Widget leading;
  final String title;

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
          final ink = focused ? AvenColors.onFocus : AvenColors.text;
          return AvenFocusZoom(
            focused: focused,
            scale: 1.0,
            borderRadius: 10,
            showHalo: false,
            child: Material(
            color: focused
                ? AvenColors.focusFill
                : selected
                    ? AvenColors.text.withValues(alpha: 0.08)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.none,
            child: IconTheme(
              data: IconThemeData(color: ink),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: ink),
                child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              hoverColor: Colors.transparent,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    SizedBox(width: 24, child: leading),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16),
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

/// Small caps heading above a group of setting rows.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: AvenColors.textMuted,
        ),
      ),
    );
  }
}

/// TV setting row: title on the left, a radio or value on the side, hairline
/// divider below; turns into a light pill while focused.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.focusNode,
    required this.onKeyEvent,
    required this.onTap,
    required this.title,
    this.subtitle,
    this.value,
    this.checked,
  });

  final FocusNode focusNode;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final VoidCallback onTap;
  final String title;
  final String? subtitle;
  final String? value;
  final bool? checked;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) => onKeyEvent(event),
      onFocusChange: (focused) {
        final ctx = focusNode.context;
        if (!focused || ctx == null) return;
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
        );
      },
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          final ink = focused ? AvenColors.onFocus : AvenColors.text;
          return GestureDetector(
            onTap: onTap,
            // Plain Container: a radius and a one-sided border cannot lerp.
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: focused ? AvenColors.focusFill : Colors.transparent,
                borderRadius: focused ? BorderRadius.circular(10) : null,
                border: focused
                    ? null
                    : Border(
                        bottom: BorderSide(
                          color: AvenColors.text.withValues(alpha: 0.07),
                        ),
                      ),
              ),
              child: Row(
                children: [
                  if (checked != null) ...[
                    Icon(
                      checked!
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 22,
                      color: ink,
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: ink,
                          ),
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              subtitle!,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.3,
                                color: ink.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (value != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      value!,
                      style: TextStyle(
                        fontSize: 14,
                        color: ink.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
