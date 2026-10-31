import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/l10n/aven_strings.dart';
import '../core/platform/aven_flavor.dart';

import '../core/url/url_input.dart';

class WebLink {
  const WebLink({required this.title, required this.url, this.savedAt});

  final String title;
  final String url;
  final int? savedAt;

  String toJson() => jsonEncode({
    'title': title,
    'url': url,
    if (savedAt != null) 'savedAt': savedAt,
  });

  static WebLink? fromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final url = decoded['url'];
      final title = decoded['title'];
      if (url is! String || url.isEmpty) return null;
      final label = title is String && title.trim().isNotEmpty ? title : url;
      final savedAt = decoded['savedAt'];
      return WebLink(
        title: label,
        url: url,
        savedAt: savedAt is int ? savedAt : null,
      );
    } catch (_) {
      return null;
    }
  }
}

enum AdBlock {
  off,
  local,
  adguard;

  /// TV has no DNS (VPN) mode: the in-app host list and EasyList already
  /// cover the browser, and a VPN prompt is pointless there.
  static List<AdBlock> get available =>
      AvenFlavor.isMobile ? AdBlock.values : const [AdBlock.off, AdBlock.local];

  static AdBlock fromName(String? name) {
    // Legacy "ublock" preference maps to AdGuard (option removed).
    final mode = name == 'ublock'
        ? AdBlock.adguard
        : AdBlock.values.firstWhere((item) => item.name == name, orElse: () => AdBlock.off);
    // A DNS choice saved on TV before the option was removed becomes the local list.
    return available.contains(mode) ? mode : AdBlock.local;
  }

  String get label => switch (this) {
    AdBlock.off => avenText('aven_off'),
    AdBlock.local => avenText('aven_adblock_local'),
    AdBlock.adguard => avenText('aven_adblock_dns'),
  };

  String get detail => switch (this) {
    AdBlock.off => avenText('aven_adblock_off_detail'),
    AdBlock.local => avenText('aven_adblock_local_detail'),
    AdBlock.adguard => avenText('aven_adblock_dns_detail'),
  };

  /// True when host intercept / cosmetics should run.
  bool get isEnabled => this != AdBlock.off;

  /// True when DNS VPN should be requested.
  bool get usesDns => this == AdBlock.adguard;
}

enum BrowserAgent {
  defaultAgent,
  desktop,
  mobile,
  tv;

  static BrowserAgent fromName(String? name) {
    return BrowserAgent.values.firstWhere(
      (item) => item.name == name,
      orElse: () => BrowserAgent.defaultAgent,
    );
  }

  String get label => switch (this) {
    BrowserAgent.defaultAgent => avenText('aven_agent_default'),
    BrowserAgent.desktop => avenText('aven_agent_desktop'),
    BrowserAgent.mobile => avenText('aven_agent_mobile'),
    BrowserAgent.tv => avenText('aven_agent_tv'),
  };

  String get detail => switch (this) {
    BrowserAgent.defaultAgent => avenText('aven_agent_default_detail'),
    BrowserAgent.desktop => avenText('aven_agent_desktop_detail'),
    BrowserAgent.mobile => avenText('aven_agent_mobile_detail'),
    BrowserAgent.tv => avenText('aven_agent_tv_detail'),
  };

  String? get value => switch (this) {
    BrowserAgent.defaultAgent => null,
    BrowserAgent.desktop =>
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    BrowserAgent.mobile =>
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
    BrowserAgent.tv =>
      'Mozilla/5.0 (Linux; Android 12; SHIELD Android TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
  };
}

/// How the Aven player draws subtitles: text size, box behind the text and
/// text color. Values are stored as the plain option names below.
class SubtitleStyle {
  const SubtitleStyle({
    this.size = 'medium',
    this.background = 'shade',
    this.color = 'white',
  });

  static const sizes = ['small', 'medium', 'large', 'xlarge'];
  static const backgrounds = ['none', 'shade', 'solid'];
  static const colors = ['white', 'yellow'];

  final String size;
  final String background;
  final String color;

  SubtitleStyle copyWith({String? size, String? background, String? color}) {
    return SubtitleStyle(
      size: size ?? this.size,
      background: background ?? this.background,
      color: color ?? this.color,
    );
  }
}

/// A page kept for later; [file] holds the offline copy when one was saved.
class ReadingItem {
  const ReadingItem({required this.title, required this.url, required this.savedAt, this.file});

  final String title;
  final String url;
  final int savedAt;
  final String? file;

  String toJson() => jsonEncode({
    'title': title,
    'url': url,
    'savedAt': savedAt,
    if (file != null) 'file': file,
  });

  static ReadingItem? fromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final url = decoded['url'];
      final savedAt = decoded['savedAt'];
      if (url is! String || url.isEmpty || savedAt is! int) return null;
      final title = decoded['title'];
      final file = decoded['file'];
      return ReadingItem(
        title: title is String && title.trim().isNotEmpty ? title : url,
        url: url,
        savedAt: savedAt,
        file: file is String && file.isNotEmpty ? file : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Where a video was left: [key] is the page (or the media URL without a page).
class WatchProgress {
  const WatchProgress({
    required this.key,
    required this.page,
    required this.title,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  final String key;
  final String? page;
  final String title;
  final Duration position;
  final Duration duration;
  final int updatedAt;

  double get fraction => duration.inMilliseconds <= 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  String toJson() => jsonEncode({
    'key': key,
    if (page != null) 'page': page,
    'title': title,
    'pos': position.inMilliseconds,
    'dur': duration.inMilliseconds,
    'at': updatedAt,
  });

  static WatchProgress? fromJson(String raw) {
    try {
      final d = jsonDecode(raw);
      if (d is! Map || d['key'] is! String) return null;
      final page = d['page'];
      final title = d['title'];
      return WatchProgress(
        key: d['key'] as String,
        page: page is String && page.isNotEmpty ? page : null,
        title: title is String ? title : '',
        position: Duration(milliseconds: (d['pos'] as num?)?.toInt() ?? 0),
        duration: Duration(milliseconds: (d['dur'] as num?)?.toInt() ?? 0),
        updatedAt: (d['at'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

class BrowserStore {
  static const _bookmarksKey = 'bookmarks';
  static const _historyKey = 'history';
  static const _engineKey = 'search_engine';
  static const _accountKey = 'google_account';
  static const _adBlockKey = 'ad_block';
  static const _adBlockLastKey = 'ad_block_last';
  static const _agentKey = 'user_agent';
  static const _liteKey = 'lite_browsing';
  static const _homeSuggestionsKey = 'home_suggestions';
  static const _sitePermPrefix = 'site_perm|';
  static const _subtitleSizeKey = 'subtitle_size';
  static const _subtitleBackgroundKey = 'subtitle_background';
  static const _subtitleColorKey = 'subtitle_color';
  static const _themeKey = 'theme_choice';
  static const _readingKey = 'reading_list';
  static const _watchKey = 'watch_progress';

  Future<SearchEngine> loadEngine() async {
    final prefs = await SharedPreferences.getInstance();
    return SearchEngine.fromName(prefs.getString(_engineKey));
  }

  Future<void> saveEngine(SearchEngine engine) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_engineKey, engine.name);
  }

  Future<String?> loadAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_accountKey);
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<AdBlock> loadAdBlock() async {
    final prefs = await SharedPreferences.getInstance();
    // One-shot: mega host lists broke some media players — force off once.
    if (prefs.getBool('ad_block_safe_v1') != true) {
      await prefs.setBool('ad_block_safe_v1', true);
      await prefs.setString(_adBlockKey, AdBlock.off.name);
      return AdBlock.off;
    }
    final raw = prefs.getString(_adBlockKey);
    if (raw == null || raw.isEmpty) return AdBlock.off;
    final mode = AdBlock.fromName(raw);
    if (raw == 'ublock' || raw != mode.name) {
      await prefs.setString(_adBlockKey, mode.name);
      await prefs.setString(_adBlockLastKey, mode.name);
    }
    return mode;
  }

  Future<AdBlock> loadAdBlockProvider() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_adBlockLastKey);
    // First enable: prefer local list (no VPN). Settings choice is remembered.
    if (raw == null || raw.isEmpty) return AdBlock.local;
    final stored = AdBlock.fromName(raw);
    return stored == AdBlock.off ? AdBlock.local : stored;
  }

  Future<void> saveAdBlock(AdBlock mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adBlockKey, mode.name);
    if (mode != AdBlock.off) {
      await prefs.setString(_adBlockLastKey, mode.name);
    }
  }

  Future<BrowserAgent> loadAgent() async {
    final prefs = await SharedPreferences.getInstance();
    return BrowserAgent.fromName(prefs.getString(_agentKey));
  }

  Future<void> saveAgent(BrowserAgent agent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_agentKey, agent.name);
  }

  Future<bool> loadLiteBrowsing({bool fallback = true}) async {
    final prefs = await SharedPreferences.getInstance();
    // TV defaults to calm browsing. Phones pass fallback: false.
    return prefs.getBool(_liteKey) ?? fallback;
  }

  Future<void> saveLiteBrowsing(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_liteKey, enabled);
  }

  Future<String> loadThemeChoice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeKey) ?? 'system';
  }

  Future<void> saveThemeChoice(String choice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, choice);
  }

  static const _openTabsKey = 'open_tabs';
  static const _openTabIndexKey = 'open_tab_index';

  Future<({List<({String? url, String title, String? preview})> tabs, int index})>
      loadOpenTabs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_openTabsKey) ?? const <String>[];
    final tabs = <({String? url, String title, String? preview})>[];
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is! Map) continue;
        final url = decoded['url'];
        final title = decoded['title'];
        final preview = decoded['preview'];
        tabs.add((
          url: url is String && url.isNotEmpty ? url : null,
          title: title is String && title.trim().isNotEmpty ? title : avenText('aven_new_tab'),
          preview: preview is String && preview.isNotEmpty ? preview : null,
        ));
      } catch (_) {}
    }
    final index = prefs.getInt(_openTabIndexKey) ?? 0;
    return (tabs: tabs, index: index);
  }

  Future<void> saveOpenTabs(
    List<({String? url, String title, String? preview, bool incognito})> tabs,
    int index,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final kept = [
      for (final tab in tabs)
        if (!tab.incognito)
          jsonEncode({
            if (tab.url != null && tab.url!.isNotEmpty) 'url': tab.url,
            'title': tab.title,
            if (tab.preview != null && tab.preview!.isNotEmpty) 'preview': tab.preview,
          }),
    ];
    if (kept.isEmpty) {
      await prefs.remove(_openTabsKey);
      await prefs.remove(_openTabIndexKey);
      return;
    }
    await prefs.setStringList(_openTabsKey, kept);
    await prefs.setInt(_openTabIndexKey, index.clamp(0, kept.length - 1));
  }

  static const _homeBookmarksKey = 'home_bookmarks';

  /// TV: bookmark cards on the home screen.
  Future<bool> loadHomeBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_homeBookmarksKey) ?? true;
  }

  Future<void> saveHomeBookmarks(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_homeBookmarksKey, enabled);
  }

  Future<bool> loadHomeSuggestions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_homeSuggestionsKey) ?? true;
  }

  Future<void> saveHomeSuggestions(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_homeSuggestionsKey, enabled);
  }

  /// "allow", "block" or "ask" for a page permission ("location", "camera", "microphone").
  Future<String> loadSitePermission(String host, String id) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('$_sitePermPrefix$host|$id');
    return value == 'allow' || value == 'block' ? value! : 'ask';
  }

  Future<void> saveSitePermission(String host, String id, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_sitePermPrefix$host|$id';
    if (value == 'ask') {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  Future<SubtitleStyle> loadSubtitleStyle() async {
    final prefs = await SharedPreferences.getInstance();
    String pick(String key, List<String> allowed, String fallback) {
      final value = prefs.getString(key);
      return allowed.contains(value) ? value! : fallback;
    }

    const base = SubtitleStyle();
    return SubtitleStyle(
      size: pick(_subtitleSizeKey, SubtitleStyle.sizes, base.size),
      background: pick(
        _subtitleBackgroundKey,
        SubtitleStyle.backgrounds,
        base.background,
      ),
      color: pick(_subtitleColorKey, SubtitleStyle.colors, base.color),
    );
  }

  Future<void> saveSubtitleStyle(SubtitleStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_subtitleSizeKey, style.size);
    await prefs.setString(_subtitleBackgroundKey, style.background);
    await prefs.setString(_subtitleColorKey, style.color);
  }

  Future<void> saveAccount(String? email) async {
    final prefs = await SharedPreferences.getInstance();
    if (email == null || email.isEmpty) {
      await prefs.remove(_accountKey);
    } else {
      await prefs.setString(_accountKey, email);
    }
  }

  Future<List<WebLink>> loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    return _readList(prefs, _bookmarksKey);
  }

  Future<List<WebLink>> saveBookmarks(List<WebLink> links) async {
    // Room for a bookmark file imported from another browser.
    final trimmed = links.take(2000).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_bookmarksKey, trimmed.map((link) => link.toJson()).toList());
    return trimmed;
  }

  Future<List<WebLink>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return _readList(prefs, _historyKey);
  }

  Future<List<WebLink>> addHistory(WebLink link) async {
    final current = await loadHistory();
    final next = [
      link,
      ...current.where((item) => item.url != link.url),
    ].take(150).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, next.map((item) => item.toJson()).toList());
    return next;
  }

  Future<List<WebLink>> removeHistory(String url) async {
    final next = (await loadHistory()).where((item) => item.url != url).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, next.map((item) => item.toJson()).toList());
    return next;
  }

  Future<void> clearHistory({Duration? newerThan}) async {
    final prefs = await SharedPreferences.getInstance();
    if (newerThan == null) {
      await prefs.remove(_historyKey);
      return;
    }
    final cutoff = DateTime.now().subtract(newerThan).millisecondsSinceEpoch;
    final kept = (await loadHistory()).where((item) {
      final at = item.savedAt;
      if (at == null) return true;
      return at < cutoff;
    }).toList();
    await prefs.setStringList(_historyKey, kept.map((item) => item.toJson()).toList());
  }

  static const _defaultAskedKey = 'default_browser_asked';

  /// The phone asks once to become the default browser; Settings keeps the option.
  Future<bool> loadDefaultBrowserAsked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_defaultAskedKey) ?? false;
  }

  Future<void> saveDefaultBrowserAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_defaultAskedKey, true);
  }

  Future<List<ReadingItem>> loadReadingList() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_readingKey) ?? const <String>[];
    return raw.map(ReadingItem.fromJson).whereType<ReadingItem>().toList();
  }

  Future<List<ReadingItem>> saveReadingList(List<ReadingItem> items) async {
    final kept = items.take(100).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_readingKey, kept.map((item) => item.toJson()).toList());
    return kept;
  }

  Future<List<WatchProgress>> loadWatchProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_watchKey) ?? const <String>[];
    return raw.map(WatchProgress.fromJson).whereType<WatchProgress>().toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<WatchProgress?> findWatchProgress(String key) async {
    for (final item in await loadWatchProgress()) {
      if (item.key == key) return item;
    }
    return null;
  }

  /// Saves [entry], or drops the key when [entry] is null (video finished).
  Future<void> saveWatchProgress(String key, WatchProgress? entry) async {
    final current = await loadWatchProgress();
    final next = [
      ?entry,
      ...current.where((item) => item.key != key),
    ].take(20).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_watchKey, next.map((item) => item.toJson()).toList());
  }

  List<WebLink> _readList(SharedPreferences prefs, String key) {
    final raw = prefs.getStringList(key) ?? const <String>[];
    return raw.map(WebLink.fromJson).whereType<WebLink>().toList();
  }
}
