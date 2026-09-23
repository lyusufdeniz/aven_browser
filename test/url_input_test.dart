import 'package:aven_browser/url_input.dart';
import 'package:aven_browser/web_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty address stays on the home page', () {
    expect(normalizeInput('   '), isNull);
  });

  test('a host without a scheme gets https', () {
    expect(normalizeInput('example.com'), 'https://example.com');
    expect(normalizeInput('example.com/docs'), 'https://example.com/docs');
  });

  test('http and https are left alone', () {
    expect(normalizeInput('http://example.com'), 'http://example.com');
    expect(normalizeInput('https://example.com/a'), 'https://example.com/a');
  });

  test('words become a search', () {
    expect(
      normalizeInput('hava durumu'),
      'https://www.google.com/search?q=hava+durumu',
    );
  });

  test('local addresses stay on http', () {
    expect(normalizeInput('192.168.1.1'), 'http://192.168.1.1');
    expect(normalizeInput('localhost:8080'), 'http://localhost:8080');
  });

  test('webview major version is the first number', () {
    expect(webViewMajor('109.0.5414.117'), 109);
    expect(webViewMajor(null), isNull);
    expect(webViewMajor(''), isNull);
  });
}
