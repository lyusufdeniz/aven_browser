import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/aven_app_info.dart';
import '../core/platform/aven_flavor.dart';
import '../platform/web_input.dart';

/// Errors kept on the device (files/aven_reports) so the user can share them.
/// Android crashes land in the same folder from AvenApplication.
abstract final class ErrorReports {
  static const _limit = 40;
  static Directory? _dir;
  static final Set<String> _seen = {};

  static Future<void> init() async {
    try {
      final base = await WebInput.filesDir();
      if (base == null) return;
      _dir = Directory('$base/aven_reports');
    } catch (_) {
      return;
    }
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      record(details.exception, details.stack, where: details.library);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, where: 'async');
      return true;
    };
  }

  static void record(Object error, StackTrace? stack, {String? where}) {
    final dir = _dir;
    if (dir == null) return;
    final text = '$error';
    // The same error repeating every frame would flood the folder.
    if (!_seen.add(text) || _seen.length > 200) return;
    final body = StringBuffer()
      ..writeln('Aven error (${where ?? 'flutter'})')
      ..writeln('Build: ${AvenFlavor.isMobile ? 'mobile' : 'tv'} ${AvenAppInfo.version} (${AvenAppInfo.versionCode})')
      ..writeln('Time: ${DateTime.now().toIso8601String()}')
      ..writeln()
      ..writeln(text)
      ..writeln()
      ..writeln(stack ?? '');
    try {
      dir.createSync(recursive: true);
      File('${dir.path}/error-${DateTime.now().millisecondsSinceEpoch}.txt')
          .writeAsStringSync(body.toString());
      _trim(dir);
    } catch (_) {}
  }

  static void _trim(Directory dir) {
    final files = _files(dir);
    for (final file in files.skip(_limit)) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }

  /// Newest first.
  static List<File> _files(Directory dir) {
    if (!dir.existsSync()) return const [];
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.txt')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  static List<({DateTime at, String title, String text})> load() {
    final dir = _dir;
    if (dir == null) return const [];
    final out = <({DateTime at, String title, String text})>[];
    for (final file in _files(dir)) {
      try {
        final text = file.readAsStringSync();
        final stamp = RegExp(r'(\d{10,})').firstMatch(file.path)?.group(1);
        final at = DateTime.fromMillisecondsSinceEpoch(int.tryParse(stamp ?? '') ?? 0);
        const header = ['Aven ', 'Build:', 'Time:', 'Device:', 'Thread:'];
        final title = text.split('\n').firstWhere(
              (line) => line.trim().isNotEmpty && !header.any(line.startsWith),
              orElse: () => '',
            );
        out.add((at: at, title: title.trim(), text: text));
      } catch (_) {}
    }
    return out;
  }

  static void clear() {
    final dir = _dir;
    if (dir == null) return;
    for (final file in _files(dir)) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }
}
