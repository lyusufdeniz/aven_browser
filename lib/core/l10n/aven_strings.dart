import 'package:flutter/services.dart';

/// English copy lives in `res/values/strings.xml`. Android returns the
/// device language after Play Console adds translated resource folders.
class AvenStrings {
  static const _channel = MethodChannel('dev.furina.avenbrowser/input');
  static Map<String, String> values = const {};

  static Future<void> load() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('appStrings');
      values = {
        for (final entry in raw?.entries ?? const <MapEntry<Object?, Object?>>[])
          '${entry.key}': '${entry.value}',
      };
    } catch (_) {
      values = const {};
    }
  }
}

String avenText(String key, [List<Object>? args]) {
  var text = AvenStrings.values[key] ?? key;
  if (args == null) return text;
  for (var i = 0; i < args.length; i++) {
    final n = i + 1;
    text = text.replaceAll('%$n\$s', '${args[i]}').replaceAll('%$n\$d', '${args[i]}');
  }
  return text;
}

String downloadStatusText(String? code) {
  return switch (code) {
    'running' => avenText('aven_download_running'),
    'pending' => avenText('aven_download_pending'),
    'paused' => avenText('aven_download_paused'),
    'success' => avenText('aven_download_success'),
    'failed' => avenText('aven_download_failed'),
    _ => code ?? '',
  };
}

String downloadStatusLabel(String? code, String? progress) {
  final name = downloadStatusText(code);
  final raw = int.tryParse(progress ?? '') ?? -1;
  if (code == 'running' && raw >= 0) {
    return avenText('aven_download_progress', [name, raw]);
  }
  return name;
}

bool downloadIsActive(String? code) {
  return code == 'running' || code == 'pending' || code == 'paused';
}

String permissionLabel(String id) {
  return switch (id) {
    'location' => avenText('aven_perm_location'),
    'camera' => avenText('aven_perm_camera'),
    'microphone' => avenText('aven_perm_microphone'),
    'notifications' => avenText('aven_perm_notifications'),
    'storage' => avenText('aven_perm_storage'),
    'autoplay' => avenText('aven_perm_autoplay'),
    _ => avenText('aven_allow'),
  };
}
