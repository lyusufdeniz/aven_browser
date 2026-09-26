enum SearchEngine {
  google,
  duckduckgo,
  bing,
  yandex;

  String get label => switch (this) {
    SearchEngine.google => 'Google',
    SearchEngine.duckduckgo => 'DuckDuckGo',
    SearchEngine.bing => 'Bing',
    SearchEngine.yandex => 'Yandex',
  };

  static SearchEngine fromName(String? name) {
    for (final engine in SearchEngine.values) {
      if (engine.name == name) return engine;
    }
    return SearchEngine.google;
  }
}

/// Turns the address-bar text into a URL.
///
/// Words become a search on [engine]. Hosts without a scheme get `https://`.
/// Bare IP addresses and `localhost` get `http://`.
String? normalizeInput(String raw, {SearchEngine engine = SearchEngine.google}) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final parsed = Uri.tryParse(text);
  if (parsed != null &&
      parsed.hasScheme &&
      (parsed.scheme == 'http' || parsed.scheme == 'https')) {
    return text;
  }

  if (_isLocalHost(text)) {
    return 'http://$text';
  }

  if (!text.contains(' ') && _domain.hasMatch(text)) {
    return 'https://$text';
  }

  final query = Uri.encodeQueryComponent(text);
  return switch (engine) {
    SearchEngine.google => 'https://www.google.com/search?q=$query',
    SearchEngine.duckduckgo => 'https://duckduckgo.com/?q=$query',
    SearchEngine.bing => 'https://www.bing.com/search?q=$query',
    SearchEngine.yandex => 'https://yandex.com/search/?text=$query',
  };
}

final RegExp _domain = RegExp(
  r'^(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}(?::\d+)?(?:[/?#].*)?$',
);

final RegExp _ip = RegExp(
  r'^(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?(?:[/?#].*)?$',
);

bool _isLocalHost(String text) {
  return text.startsWith('localhost') || _ip.hasMatch(text);
}
