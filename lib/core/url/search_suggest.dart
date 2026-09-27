import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'url_input.dart';

/// Remote + local address-bar suggestions (Google-style).
class SearchSuggestion {
  const SearchSuggestion({
    required this.label,
    required this.query,
    this.isUrl = false,
    this.source = SuggestionSource.remote,
  });

  final String label;
  final String query;
  final bool isUrl;
  final SuggestionSource source;
}

enum SuggestionSource { remote, history, bookmark }

Uri suggestEndpoint(SearchEngine engine, String query) {
  final q = query.trim();
  return switch (engine) {
    SearchEngine.google => Uri.https(
        'suggestqueries.google.com',
        '/complete/search',
        {'client': 'firefox', 'hl': 'tr', 'q': q},
      ),
    SearchEngine.duckduckgo => Uri.https(
        'duckduckgo.com',
        '/ac/',
        {'q': q, 'type': 'list'},
      ),
    SearchEngine.bing => Uri.https(
        'api.bing.com',
        '/osjson.aspx',
        {'query': q},
      ),
    SearchEngine.yandex => Uri.https(
        'suggest.yandex.com',
        '/suggest-ff.cgi',
        {'part': q, 'uil': 'tr'},
      ),
  };
}

/// Parses Firefox/Chrome-style `[query, [s1, s2, ...]]` JSON.
List<String> parseSuggestPayload(String body, SearchEngine engine) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return const [];
  try {
    final decoded = jsonDecode(trimmed);
    if (engine == SearchEngine.duckduckgo && decoded is List) {
      // DDG list mode: [query, [phrases...]] or [{phrase: ...}, ...]
      if (decoded.length >= 2 && decoded[1] is List) {
        return _stringList(decoded[1] as List);
      }
      return [
        for (final item in decoded)
          if (item is Map && item['phrase'] is String)
            (item['phrase'] as String).trim(),
      ].where((s) => s.isNotEmpty).toList();
    }
    if (decoded is List && decoded.length >= 2 && decoded[1] is List) {
      return _stringList(decoded[1] as List);
    }
  } catch (_) {}
  return const [];
}

List<String> _stringList(List<dynamic> raw) {
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}

Future<List<String>> fetchRemoteSuggestions(
  String query, {
  SearchEngine engine = SearchEngine.google,
  Duration timeout = const Duration(milliseconds: 2500),
}) async {
  final q = query.trim();
  if (q.length < 2) return const [];
  final client = HttpClient();
  client.connectionTimeout = timeout;
  try {
    final request = await client.getUrl(suggestEndpoint(engine, q)).timeout(timeout);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 (Linux; Android 12; SHIELD Android TV) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    return parseSuggestPayload(body, engine);
  } catch (_) {
    return const [];
  } finally {
    client.close(force: true);
  }
}

List<SearchSuggestion> localSuggestions(
  String query, {
  List<({String title, String url})> history = const [],
  List<({String title, String url})> bookmarks = const [],
  int limit = 4,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final out = <SearchSuggestion>[];
  final seen = <String>{};

  void add(SuggestionSource source, String title, String url) {
    if (out.length >= limit) return;
    final host = Uri.tryParse(url)?.host ?? '';
    final hay = '$title $url $host'.toLowerCase();
    if (!hay.contains(q)) return;
    final key = url.toLowerCase();
    if (!seen.add(key)) return;
    final label = title.trim().isEmpty ? url : title.trim();
    out.add(
      SearchSuggestion(
        label: label,
        query: url,
        isUrl: true,
        source: source,
      ),
    );
  }

  for (final item in bookmarks) {
    add(SuggestionSource.bookmark, item.title, item.url);
  }
  for (final item in history) {
    add(SuggestionSource.history, item.title, item.url);
  }
  return out;
}

Future<List<SearchSuggestion>> buildAddressSuggestions(
  String query, {
  SearchEngine engine = SearchEngine.google,
  List<({String title, String url})> history = const [],
  List<({String title, String url})> bookmarks = const [],
  int limit = 8,
}) async {
  final q = query.trim();
  if (q.length < 2) return const [];
  final local = localSuggestions(
    q,
    history: history,
    bookmarks: bookmarks,
    limit: 3,
  );
  final remote = await fetchRemoteSuggestions(q, engine: engine);
  final seen = <String>{
    for (final item in local) item.query.toLowerCase(),
  };
  final merged = <SearchSuggestion>[...local];
  for (final phrase in remote) {
    if (merged.length >= limit) break;
    final key = phrase.toLowerCase();
    if (!seen.add(key)) continue;
    merged.add(
      SearchSuggestion(
        label: phrase,
        query: phrase,
        source: SuggestionSource.remote,
      ),
    );
  }
  return merged;
}
