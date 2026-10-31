import 'settings_store.dart';

/// Netscape bookmark HTML: the file Chrome, Firefox, Edge and Safari export
/// and import, so Aven bookmarks and history move both ways.
abstract final class BookmarkFile {
  static final _link = RegExp(
    r'<a\s[^>]*href\s*=\s*"([^"]+)"[^>]*>(.*?)</a>',
    caseSensitive: false,
    dotAll: true,
  );
  static final _addDate = RegExp(r'add_date\s*=\s*"(\d+)"', caseSensitive: false);
  static final _tags = RegExp(r'<[^>]+>');

  /// Web links found in [html], in file order, without duplicates.
  static List<WebLink> parse(String html) {
    final seen = <String>{};
    final out = <WebLink>[];
    for (final match in _link.allMatches(html)) {
      final url = _unescape(match.group(1)!.trim());
      final scheme = Uri.tryParse(url)?.scheme;
      if (scheme != 'http' && scheme != 'https') continue;
      if (!seen.add(url)) continue;
      final title = _unescape(match.group(2)!.replaceAll(_tags, '')).trim();
      final added = int.tryParse(_addDate.firstMatch(match.group(0)!)?.group(1) ?? '');
      out.add(WebLink(
        title: title.isEmpty ? url : title,
        url: url,
        savedAt: added == null ? null : added * 1000,
      ));
    }
    return out;
  }

  static String build(String folder, List<WebLink> links) {
    final out = StringBuffer()
      ..writeln('<!DOCTYPE NETSCAPE-Bookmark-file-1>')
      ..writeln('<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">')
      ..writeln('<TITLE>Bookmarks</TITLE>')
      ..writeln('<H1>Bookmarks</H1>')
      ..writeln('<DL><p>')
      ..writeln('    <DT><H3>${_escape(folder)}</H3>')
      ..writeln('    <DL><p>');
    for (final link in links) {
      final added = link.savedAt == null ? '' : ' ADD_DATE="${link.savedAt! ~/ 1000}"';
      out.writeln('        <DT><A HREF="${_escape(link.url)}"$added>${_escape(link.title)}</A>');
    }
    out
      ..writeln('    </DL><p>')
      ..writeln('</DL><p>');
    return out.toString();
  }

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _unescape(String text) => text
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');
}
