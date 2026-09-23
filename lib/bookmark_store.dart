import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'url_input.dart';

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
  adguard,
  ublock;

  static AdBlock fromName(String? name) {
    return AdBlock.values.firstWhere((item) => item.name == name, orElse: () => AdBlock.off);
  }

  String get label => switch (this) {
    AdBlock.off => 'Kapalı',
    AdBlock.adguard => 'AdGuard',
    AdBlock.ublock => 'uBlock',
  };
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
    BrowserAgent.defaultAgent => 'Varsayılan',
    BrowserAgent.desktop => 'Masaüstü',
    BrowserAgent.mobile => 'Mobil',
    BrowserAgent.tv => 'Android TV',
  };

  String get detail => switch (this) {
    BrowserAgent.defaultAgent => 'Sistem WebView kimliği.',
    BrowserAgent.desktop => 'Chrome masaüstü gibi görünür.',
    BrowserAgent.mobile => 'Telefon Chrome gibi görünür.',
    BrowserAgent.tv => 'Android TV tarayıcısı gibi görünür.',
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

class BrowserStore {
  static const _bookmarksKey = 'bookmarks';
  static const _historyKey = 'history';
  static const _engineKey = 'search_engine';
  static const _accountKey = 'google_account';
  static const _adBlockKey = 'ad_block';
  static const _adBlockLastKey = 'ad_block_last';
  static const _agentKey = 'user_agent';
  static const _liteKey = 'lite_browsing';

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
    return AdBlock.fromName(prefs.getString(_adBlockKey));
  }

  Future<AdBlock> loadAdBlockProvider() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = AdBlock.fromName(prefs.getString(_adBlockLastKey));
    return stored == AdBlock.off ? AdBlock.adguard : stored;
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

  Future<bool> loadLiteBrowsing() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_liteKey) ?? false;
  }

  Future<void> saveLiteBrowsing(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_liteKey, enabled);
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
    final trimmed = links.take(200).toList();
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

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  List<WebLink> _readList(SharedPreferences prefs, String key) {
    final raw = prefs.getStringList(key) ?? const <String>[];
    return raw.map(WebLink.fromJson).whereType<WebLink>().toList();
  }
}
