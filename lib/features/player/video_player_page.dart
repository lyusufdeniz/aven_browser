import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/aven_theme.dart';
import 'video_catalog.dart';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.video, required this.initialSource});

  final PageVideo video;
  final VideoSource initialSource;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  VideoSource? _source;
  late List<VideoSource> _sources;
  List<_Cue> _cues = const [];
  String? _subtitleLabel;
  String? _displayedCue;
  bool _displayedPlaying = false;
  DateTime _lastProgressUi = DateTime.fromMillisecondsSinceEpoch(0);
  double _speed = 1;
  String? _error;
  bool _loading = true;
  bool _controls = true;
  bool _exiting = false;
  bool _pickerOpen = false;
  Timer? _hideControls;
  final _rootFocus = FocusNode();
  late final List<FocusNode> _barFocus = List.generate(8, (_) => FocusNode());
  // 0 progress, 1 play, 2 -10, 3 +10, 4 speed, 5 quality, 6 subtitle, 7 close

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  static const _progressIndex = 0;
  static const _playIndex = 1;
  static const _qualityIndex = 5;
  static const _closeIndex = 7;

  @override
  void initState() {
    super.initState();
    _sources = _uniqueSources(widget.video.sources);
    _open(widget.initialSource);
    _scheduleHide();
  }

  List<VideoSource> _uniqueSources(List<VideoSource> sources) {
    final seen = <String>{};
    final out = <VideoSource>[];
    for (final source in sources) {
      if (seen.add(source.url)) {
        out.add(
          VideoSource(
            url: source.url,
            label: _displayLabel(source),
            headers: source.headers,
          ),
        );
      }
    }
    return out;
  }

  String _displayLabel(VideoSource source) {
    final hint = qualityLabelForUrl(source.url);
    final label = source.label.trim();
    if (label.isEmpty ||
        label == 'Kaynak' ||
        label == 'Net' ||
        label == 'Video' ||
        label == 'Oynatilan' ||
        label == 'Script' ||
        label == 'XHR' ||
        label == 'Sayfa' ||
        label == 'Gömülü' ||
        label == 'Iframe') {
      return hint;
    }
    if (hint != 'Akış' && !label.contains(hint)) return '$hint · $label';
    return label;
  }

  Future<void> _open(VideoSource source) async {
    final previous = _controller;
    final resumeAt = previous?.value.isInitialized == true
        ? previous!.value.position
        : Duration.zero;

    // Detach the old player from the tree before disposing it.
    setState(() {
      _loading = true;
      _error = null;
      _source = source;
      _controller = null;
      _displayedCue = null;
      _displayedPlaying = false;
    });
    previous?.removeListener(_onVideoTick);
    try {
      await previous?.pause();
    } catch (_) {}
    try {
      await previous?.dispose();
    } catch (_) {}
    if (!mounted) return;

    final attempts = _headerAttempts(source);

    Object? lastError;
    for (final headers in attempts) {
      final next = VideoPlayerController.networkUrl(
        Uri.parse(source.url),
        httpHeaders: headers,
        formatHint: _formatHint(source.url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      );
      try {
        await next.initialize();
        await next.setPlaybackSpeed(_speed);
        if (resumeAt > const Duration(milliseconds: 400)) {
          final duration = next.value.duration;
          final target = duration > Duration.zero && resumeAt > duration
              ? duration
              : resumeAt;
          await next.seekTo(target);
        }
        next.addListener(_onVideoTick);
        await next.setVolume(1);
        await next.play();
        if (!mounted) {
          await next.dispose();
          return;
        }
        setState(() {
          _controller = next;
          _loading = false;
          _displayedPlaying = next.value.isPlaying;
          _displayedCue = null;
        });
        _revealControls();
        unawaited(_expandHlsQualities(source));
        return;
      } catch (error) {
        lastError = error;
        try {
          await next.dispose();
        } catch (_) {}
      }
    }

    if (!mounted) return;
    final fallback = _sources.where((item) => item.url != source.url);
    for (final other in fallback) {
      for (final headers in _headerAttempts(other)) {
        final next = VideoPlayerController.networkUrl(
          Uri.parse(other.url),
          httpHeaders: headers,
          formatHint: _formatHint(other.url),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
        );
        try {
          await next.initialize();
          await next.setPlaybackSpeed(_speed);
          if (resumeAt > const Duration(milliseconds: 400)) {
            final duration = next.value.duration;
            final target = duration > Duration.zero && resumeAt > duration
                ? duration
                : resumeAt;
            await next.seekTo(target);
          }
          next.addListener(_onVideoTick);
          await next.setVolume(1);
          await next.play();
          if (!mounted) {
            await next.dispose();
            return;
          }
          setState(() {
            _controller = next;
            _source = other;
            _loading = false;
            _displayedPlaying = next.value.isPlaying;
            _displayedCue = null;
            _error = null;
          });
          _revealControls();
          unawaited(_expandHlsQualities(other));
          return;
        } catch (error) {
          lastError = error;
          try {
            await next.dispose();
          } catch (_) {}
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = 'Bu kaynak açılamadı.';
    });
    assert(() {
      debugPrint('Aven player open failed: $lastError');
      return true;
    }());
  }

  Future<void> _expandHlsQualities(VideoSource source) async {
    final variants = await _parseHlsVariants(source);
    if (!mounted || variants.length <= 1) return;
    final merged = _uniqueSources([...variants, ..._sources]);
    if (merged.length <= _sources.length) return;
    // Prefer higher resolutions first.
    merged.sort((a, b) => _qualityRank(b.url).compareTo(_qualityRank(a.url)));
    setState(() => _sources = merged);
  }

  int _qualityRank(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('2160') || lower.contains('4k')) return 2160;
    if (lower.contains('1440')) return 1440;
    if (lower.contains('1080') || lower.contains('fhd')) return 1080;
    if (lower.contains('720') || lower.contains('/hd')) return 720;
    if (lower.contains('540')) return 540;
    if (lower.contains('480') || lower.contains('/sd')) return 480;
    if (lower.contains('360')) return 360;
    if (lower.contains('240')) return 240;
    return 0;
  }

  Future<List<VideoSource>> _parseHlsVariants(VideoSource source) async {
    final lower = source.url.toLowerCase();
    if (!lower.contains('.m3u8') && !lower.contains('mpegurl')) {
      return [source];
    }
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(Uri.parse(source.url));
      source.headers.forEach(request.headers.set);
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return [source];
      }
      final body = await response.transform(utf8.decoder).join();
      if (!body.contains('#EXT-X-STREAM-INF')) return [source];
      final lines = const LineSplitter().convert(body);
      final out = <VideoSource>[];
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
        var uriLine = '';
        for (var j = i + 1; j < lines.length; j++) {
          final next = lines[j].trim();
          if (next.isEmpty) continue;
          if (next.startsWith('#')) break;
          uriLine = next;
          break;
        }
        if (uriLine.isEmpty) continue;
        final abs = Uri.parse(source.url).resolve(uriLine).toString();
        final label = _labelFromStreamInf(line) ?? qualityLabelForUrl(abs);
        out.add(VideoSource(url: abs, label: label, headers: source.headers));
      }
      return out.isEmpty ? [source] : out;
    } catch (_) {
      return [source];
    } finally {
      client?.close(force: true);
    }
  }

  String? _labelFromStreamInf(String line) {
    final res = RegExp(r'RESOLUTION=(\d+)x(\d+)', caseSensitive: false).firstMatch(line);
    if (res != null) {
      final height = int.tryParse(res.group(2)!);
      if (height != null && height > 0) return '${height}p';
    }
    final name = RegExp(r'NAME="([^"]+)"', caseSensitive: false).firstMatch(line);
    if (name != null && name.group(1)!.trim().isNotEmpty) return name.group(1)!.trim();
    final bw = RegExp(r'BANDWIDTH=(\d+)', caseSensitive: false).firstMatch(line);
    if (bw != null) {
      final rate = int.tryParse(bw.group(1)!);
      if (rate != null) {
        if (rate >= 5000000) return '1080p';
        if (rate >= 2500000) return '720p';
        if (rate >= 1200000) return '480p';
        if (rate >= 600000) return '360p';
      }
    }
    return null;
  }

  VideoFormat? _formatHint(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8') ||
        lower.contains('mpegurl') ||
        lower.contains('/hls/') ||
        lower.contains('live-video.net') ||
        lower.contains('/ivs/') ||
        (lower.contains('playlist') && lower.contains('hls'))) {
      return VideoFormat.hls;
    }
    if (lower.contains('.mpd') || (lower.contains('dash') && !lower.contains('dashboard'))) {
      return VideoFormat.dash;
    }
    return null;
  }

  bool _keepPageReferer(VideoSource source) {
    final referer = source.headers['Referer']?.toLowerCase() ?? '';
    final media = Uri.tryParse(source.url);
    final host = media?.host.toLowerCase() ?? '';
    if (referer.isEmpty || host.isEmpty) return false;
    if (referer.contains(host)) return false;
    // Kick / IVS CDN rejects requests that spoof the CDN as Referer.
    if (host.contains('live-video.net') ||
        host.contains('cloudfront.net') ||
        host.contains('akamaized.net') ||
        host.contains('kick.com') ||
        source.url.toLowerCase().contains('/ivs/')) {
      return true;
    }
    // Any page Referer that is not the media host is safer to keep first.
    return referer.startsWith('http');
  }

  List<Map<String, String>> _headerAttempts(VideoSource source) {
    if (_keepPageReferer(source)) {
      return [
        source.headers,
        _headersVariant(source, preferMediaReferer: false),
        _headersVariant(source, preferMediaReferer: false, dropOrigin: true),
        _headersVariant(source, preferMediaReferer: true, dropOrigin: true),
      ];
    }
    return [
      source.headers,
      _headersVariant(source, preferMediaReferer: true),
      _headersVariant(source, preferMediaReferer: true, dropOrigin: true),
      _headersVariant(source, preferMediaReferer: false, dropOrigin: true),
    ];
  }

  Map<String, String> _headersVariant(
    VideoSource source, {
    required bool preferMediaReferer,
    bool dropOrigin = false,
  }) {
    final headers = Map<String, String>.from(source.headers);
    final media = Uri.tryParse(source.url);
    if (preferMediaReferer && media != null && media.host.isNotEmpty) {
      headers['Referer'] = '${media.scheme}://${media.host}/';
    }
    if (dropOrigin) {
      headers.remove('Origin');
    }
    headers.putIfAbsent(
      'User-Agent',
      () =>
          'Mozilla/5.0 (Linux; Android 12; SHIELD Android TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    );
    headers.putIfAbsent('Accept', () => '*/*');
    return headers;
  }

  void _onVideoTick() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;

    final playing = controller.value.isPlaying;
    final cue = _currentCue(controller);
    final cueChanged = cue != _displayedCue;
    final playChanged = playing != _displayedPlaying;
    final now = DateTime.now();
    final needProgress = _controls &&
        now.difference(_lastProgressUi) >= const Duration(milliseconds: 250);

    if (!cueChanged && !playChanged && !needProgress) return;

    _displayedCue = cue;
    _displayedPlaying = playing;
    if (needProgress) _lastProgressUi = now;
    setState(() {});
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    _revealControls();
  }

  Future<void> _seekBy(Duration delta) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final next = controller.value.position + delta;
    final end = controller.value.duration;
    final clamped = next < Duration.zero
        ? Duration.zero
        : (next > end ? end : next);
    await controller.seekTo(clamped);
    if (!_controls) _revealControls();
    else _scheduleHide();
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    await _controller?.setPlaybackSpeed(speed);
    _revealControls();
  }

  Future<void> _setSubtitle(MediaTrack? track) async {
    if (track == null) {
      setState(() {
        _cues = const [];
        _subtitleLabel = null;
      });
      return;
    }
    final cues = await _loadCues(track.url);
    if (!mounted) return;
    setState(() {
      _cues = cues;
      _subtitleLabel = track.label;
      if (cues.isEmpty) _error = 'Altyazı dosyası okunamadı.';
    });
    _revealControls();
  }

  void _scheduleHide() {
    _hideControls?.cancel();
    if (_exiting || _pickerOpen) return;
    _hideControls = Timer(const Duration(seconds: 4), () {
      if (!mounted || _exiting || _pickerOpen) return;
      setState(() => _controls = false);
      _rootFocus.requestFocus();
    });
  }

  void _revealControls({bool grabPlay = true}) {
    if (_pickerOpen) return;
    setState(() => _controls = true);
    _scheduleHide();
    if (!grabPlay) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controls && !_pickerOpen) {
        _barFocus[_playIndex].requestFocus();
      }
    });
  }

  void _setBarFocusEnabled(bool enabled) {
    for (final node in _barFocus) {
      node.canRequestFocus = enabled;
    }
    _rootFocus.canRequestFocus = enabled;
  }

  Future<T?> _showTvPicker<T>({
    required String title,
    required List<_PickerOption<T>> options,
    required int returnFocusIndex,
  }) async {
    if (_pickerOpen || !mounted || options.isEmpty) return null;
    _pickerOpen = true;
    _hideControls?.cancel();
    _setBarFocusEnabled(false);
    if (_rootFocus.hasFocus) _rootFocus.unfocus();
    for (final node in _barFocus) {
      if (node.hasFocus) node.unfocus();
    }
    try {
      return await showGeneralDialog<T>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Kapat',
        barrierColor: AvenColors.scrim,
        transitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return SafeArea(
            child: Center(
              child: FocusScope(
                autofocus: true,
                child: Material(
                  color: AvenColors.ink,
                  elevation: 12,
                  borderRadius: BorderRadius.circular(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 22,
                                  color: AvenColors.mist,
                                ),
                              ),
                            ),
                          ),
                          Flexible(
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                for (final option in options)
                                  ListTile(
                                    autofocus: option.autofocus,
                                    enabled: option.enabled,
                                    title: Text(
                                      option.title,
                                      style: TextStyle(
                                        color: option.enabled
                                            ? AvenColors.text
                                            : AvenColors.textMuted,
                                      ),
                                    ),
                                    subtitle: option.subtitle == null
                                        ? null
                                        : Text(
                                            option.subtitle!,
                                            style: const TextStyle(
                                              color: AvenColors.textMuted,
                                              fontSize: 13,
                                            ),
                                          ),
                                    trailing: option.selected
                                        ? const Icon(Icons.check, color: AvenColors.mist)
                                        : null,
                                    onTap: option.enabled
                                        ? () => Navigator.pop(dialogContext, option.value)
                                        : null,
                                  ),
                              ],
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
      );
    } finally {
      _pickerOpen = false;
      if (mounted) {
        _setBarFocusEnabled(true);
        setState(() => _controls = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _barFocus[returnFocusIndex].requestFocus();
          _scheduleHide();
        });
      }
    }
  }

  void _moveBar(int index, LogicalKeyboardKey key) {
    if (_pickerOpen) return;
    const last = _closeIndex;
    if (key == LogicalKeyboardKey.arrowRight && index < last) {
      _barFocus[index + 1].requestFocus();
    } else if (key == LogicalKeyboardKey.arrowLeft && index > 0) {
      _barFocus[index - 1].requestFocus();
    } else if (key == LogicalKeyboardKey.arrowUp && index > _progressIndex) {
      _barFocus[_progressIndex].requestFocus();
    } else if (key == LogicalKeyboardKey.arrowDown && index == _progressIndex) {
      _barFocus[_playIndex].requestFocus();
    }
    _scheduleHide();
  }

  KeyEventResult _onBarKey(int index, KeyEvent event, VoidCallback activate) {
    if (_pickerOpen) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (index == _progressIndex) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _seekBy(const Duration(seconds: -10));
        _scheduleHide();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _seekBy(const Duration(seconds: 10));
        _scheduleHide();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _barFocus[_playIndex].requestFocus();
        _scheduleHide();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      _moveBar(index, key);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space) {
      activate();
      // Speed / quality / subtitle manage their own focus lifecycle.
      if (index != _closeIndex &&
          index != _qualityIndex &&
          index != 4 &&
          index != 6) {
        _scheduleHide();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _requestExit() {
    if (_exiting || _pickerOpen) return;
    _exiting = true;
    _hideControls?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickSpeed() async {
    final picked = await _showTvPicker<double>(
      title: 'Hız',
      returnFocusIndex: 4,
      options: [
        for (final value in _speeds)
          _PickerOption(
            value: value,
            title: value == 1 ? 'Normal' : '${value}x',
            selected: value == _speed,
            autofocus: value == _speed,
          ),
      ],
    );
    if (picked != null) await _setSpeed(picked);
  }

  Future<void> _pickSource() async {
    final sources = _sources;
    if (sources.isEmpty) return;
    final picked = await _showTvPicker<VideoSource>(
      title: 'Kalite',
      returnFocusIndex: _qualityIndex,
      options: [
        for (var i = 0; i < sources.length; i++)
          _PickerOption(
            value: sources[i],
            title: sources[i].label.isEmpty
                ? qualityLabelForUrl(sources[i].url)
                : sources[i].label,
            subtitle: qualityLabelForUrl(sources[i].url),
            selected: sources[i].url == _source?.url,
            autofocus: sources[i].url == _source?.url || (i == 0 && _source == null),
          ),
      ],
    );
    if (picked != null && picked.url != _source?.url) await _open(picked);
  }

  Future<void> _pickSubtitle() async {
    final tracks = widget.video.tracks.where((track) {
      final kind = track.kind.toLowerCase();
      return kind == 'subtitles' || kind == 'captions';
    }).toList();
    final picked = await _showTvPicker<Object?>(
      title: 'Altyazı',
      returnFocusIndex: 6,
      options: [
        _PickerOption(
          value: 'off',
          title: 'Kapalı',
          selected: _subtitleLabel == null,
          autofocus: _subtitleLabel == null,
        ),
        if (tracks.isEmpty)
          const _PickerOption<Object?>(
            value: null,
            title: 'Bu kaynakta altyazı yok',
            selected: false,
            autofocus: false,
            enabled: false,
          )
        else
          for (final track in tracks)
            _PickerOption(
              value: track,
              title: track.label,
              selected: _subtitleLabel == track.label,
              autofocus: _subtitleLabel == track.label,
            ),
      ],
    );
    if (picked == 'off') {
      await _setSubtitle(null);
    } else if (picked is MediaTrack) {
      await _setSubtitle(picked);
    }
  }

  @override
  void dispose() {
    _hideControls?.cancel();
    _rootFocus.dispose();
    for (final node in _barFocus) {
      node.dispose();
    }
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final playing = controller?.value.isPlaying ?? false;
    final position = controller?.value.position ?? Duration.zero;
    final duration = controller?.value.duration ?? Duration.zero;
    final cue = _displayedCue;

    return Scaffold(
      backgroundColor: AvenColors.background,
      body: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (_pickerOpen || _exiting) return KeyEventResult.ignored;
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
            if (!_controls) {
              _revealControls();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _barFocus[_closeIndex].requestFocus();
              });
              return KeyEventResult.handled;
            }
            _requestExit();
            return KeyEventResult.handled;
          }
          // While the bar is open, arrows are handled by focused controls.
          if (_controls) {
            if (key == LogicalKeyboardKey.arrowLeft ||
                key == LogicalKeyboardKey.arrowRight ||
                key == LogicalKeyboardKey.arrowUp ||
                key == LogicalKeyboardKey.arrowDown) {
              return KeyEventResult.ignored;
            }
            if (key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.numpadEnter ||
                key == LogicalKeyboardKey.space ||
                key == LogicalKeyboardKey.mediaPlayPause) {
              if (_barFocus[_playIndex].hasFocus || _rootFocus.hasPrimaryFocus) {
                _togglePlay();
                return KeyEventResult.handled;
              }
              _scheduleHide();
              return KeyEventResult.ignored;
            }
            _scheduleHide();
            return KeyEventResult.ignored;
          }
          if (key == LogicalKeyboardKey.arrowLeft) {
            _seekBy(const Duration(seconds: -10));
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            _seekBy(const Duration(seconds: 10));
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.mediaPlayPause ||
              key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space) {
            _revealControls();
            return KeyEventResult.handled;
          }
          _revealControls();
          return KeyEventResult.handled;
        },
        child: Stack(
          children: [
            Center(
              child: !_loading &&
                      controller != null &&
                      controller.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: controller.value.aspectRatio == 0
                          ? 16 / 9
                          : controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    )
                  : const SizedBox.shrink(),
            ),
            if (cue != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: _controls ? 180 : 48),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AvenColors.scrim,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Text(cue, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                ),
              ),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80))),
                ),
              ),
            if (_controls)
              Align(
                alignment: Alignment.bottomCenter,
                child: Material(
                  color: Colors.transparent,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AvenColors.background.withValues(alpha: 0),
                          AvenColors.background.withValues(alpha: 0.92),
                          AvenColors.ink,
                        ],
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
                        child: ListenableBuilder(
                          listenable: Listenable.merge(_barFocus),
                          builder: (context, _) {
                            final progressFocused = _barFocus[_progressIndex].hasFocus;
                            final qualityLabel = _source == null
                                ? 'Kalite'
                                : (_source!.label.isNotEmpty
                                    ? _source!.label
                                    : qualityLabelForUrl(_source!.url));
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Focus(
                                  focusNode: _barFocus[_progressIndex],
                                  onKeyEvent: (node, event) =>
                                      _onBarKey(_progressIndex, event, () {}),
                                  child: AvenFocusZoom(
                                    focused: progressFocused,
                                    scale: 1.04,
                                    child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 120),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: progressFocused
                                          ? AvenColors.hover.withValues(alpha: 0.35)
                                          : AvenColors.row.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: progressFocused
                                            ? AvenColors.focus
                                            : AvenColors.row,
                                        width: progressFocused ? 2 : 1,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        if (controller != null &&
                                            controller.value.isInitialized)
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(6),
                                            child: VideoProgressIndicator(
                                              controller,
                                              allowScrubbing: true,
                                              padding: EdgeInsets.zero,
                                              colors: VideoProgressColors(
                                                playedColor: progressFocused
                                                    ? AvenColors.mist
                                                    : AvenColors.accent,
                                                bufferedColor: AvenColors.accentBlue,
                                                backgroundColor: AvenColors.background,
                                              ),
                                            ),
                                          )
                                        else
                                          const SizedBox(height: 8),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Text(
                                              _format(position),
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: progressFocused
                                                    ? AvenColors.mist
                                                    : AvenColors.textMuted,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              progressFocused
                                                  ? '◀︎ 10sn  ·  10sn ▶︎'
                                                  : _format(duration),
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: progressFocused
                                                    ? AvenColors.mist
                                                    : AvenColors.textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      _MenuChip(
                                        focusNode: _barFocus[_playIndex],
                                        focused: _barFocus[_playIndex].hasFocus,
                                        icon: playing ? Icons.pause : Icons.play_arrow,
                                        label: playing ? 'Duraklat' : 'Oynat',
                                        onPressed: _togglePlay,
                                        onKey: (e) =>
                                            _onBarKey(_playIndex, e, _togglePlay),
                                      ),
                                      const SizedBox(width: 10),
                                      _MenuChip(
                                        focusNode: _barFocus[2],
                                        focused: _barFocus[2].hasFocus,
                                        icon: Icons.replay_10,
                                        label: '-10',
                                        onPressed: () =>
                                            _seekBy(const Duration(seconds: -10)),
                                        onKey: (e) => _onBarKey(
                                          2,
                                          e,
                                          () => _seekBy(const Duration(seconds: -10)),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      _MenuChip(
                                        focusNode: _barFocus[3],
                                        focused: _barFocus[3].hasFocus,
                                        icon: Icons.forward_10,
                                        label: '+10',
                                        onPressed: () =>
                                            _seekBy(const Duration(seconds: 10)),
                                        onKey: (e) => _onBarKey(
                                          3,
                                          e,
                                          () => _seekBy(const Duration(seconds: 10)),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      _MenuChip(
                                        focusNode: _barFocus[4],
                                        focused: _barFocus[4].hasFocus,
                                        icon: Icons.speed,
                                        label: _speed == 1 ? 'Hız' : '${_speed}x',
                                        onPressed: _pickSpeed,
                                        onKey: (e) =>
                                            _onBarKey(4, e, _pickSpeed),
                                      ),
                                      const SizedBox(width: 10),
                                      _MenuChip(
                                        focusNode: _barFocus[_qualityIndex],
                                        focused: _barFocus[_qualityIndex].hasFocus,
                                        icon: Icons.high_quality_outlined,
                                        label: qualityLabel,
                                        onPressed: _pickSource,
                                        onKey: (e) => _onBarKey(
                                          _qualityIndex,
                                          e,
                                          _pickSource,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      _MenuChip(
                                        focusNode: _barFocus[6],
                                        focused: _barFocus[6].hasFocus,
                                        icon: Icons.closed_caption_outlined,
                                        label: _subtitleLabel ?? 'Altyazı',
                                        onPressed: _pickSubtitle,
                                        onKey: (e) =>
                                            _onBarKey(6, e, _pickSubtitle),
                                      ),
                                      const SizedBox(width: 10),
                                      _MenuChip(
                                        focusNode: _barFocus[_closeIndex],
                                        focused: _barFocus[_closeIndex].hasFocus,
                                        icon: Icons.close,
                                        label: 'Çık',
                                        onPressed: _requestExit,
                                        onKey: (e) => _onBarKey(
                                          _closeIndex,
                                          e,
                                          _requestExit,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _format(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  String? _currentCue(VideoPlayerController? controller) {
    if (controller == null || _cues.isEmpty) return null;
    final position = controller.value.position;
    for (final cue in _cues) {
      if (!position.isNegative && position >= cue.start && position <= cue.end) {
        return cue.text;
      }
    }
    return null;
  }
}

class _MenuChip extends StatelessWidget {
  const _MenuChip({
    required this.focusNode,
    required this.focused,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.onKey,
  });

  final FocusNode focusNode;
  final bool focused;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final KeyEventResult Function(KeyEvent event) onKey;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) => onKey(event),
      child: ExcludeFocus(
        child: AvenFocusZoom(
          focused: focused,
          scale: 1.1,
          child: Material(
          color: focused ? AvenColors.hover : AvenColors.row,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: focused ? AvenColors.focus : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 22, color: AvenColors.mist),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AvenColors.mist,
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
  }
}

class _Cue {
  const _Cue(this.start, this.end, this.text);

  final Duration start;
  final Duration end;
  final String text;
}

class _PickerOption<T> {
  const _PickerOption({
    required this.value,
    required this.title,
    required this.selected,
    required this.autofocus,
    this.subtitle,
    this.enabled = true,
  });

  final T value;
  final String title;
  final String? subtitle;
  final bool selected;
  final bool autofocus;
  final bool enabled;
}

Future<List<_Cue>> _loadCues(String url) async {
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    client.close();
    return _parseVtt(body);
  } catch (_) {
    return const [];
  }
}

List<_Cue> _parseVtt(String body) {
  final cues = <_Cue>[];
  final blocks = body.replaceAll('\r\n', '\n').split('\n\n');
  for (final block in blocks) {
    final lines = block.split('\n').where((line) => line.trim().isNotEmpty).toList();
    final timingIndex = lines.indexWhere((line) => line.contains('-->'));
    if (timingIndex < 0) continue;
    final parts = lines[timingIndex].split('-->');
    if (parts.length < 2) continue;
    final start = _timestamp(parts[0]);
    final end = _timestamp(parts[1]);
    if (start == null || end == null) continue;
    final text = lines.skip(timingIndex + 1).join('\n').trim();
    if (text.isEmpty) continue;
    cues.add(_Cue(start, end, text));
  }
  return cues;
}

Duration? _timestamp(String raw) {
  final match = RegExp(r'(\d+):(\d+):(\d+)[.,](\d+)').firstMatch(raw.trim());
  final short = RegExp(r'(\d+):(\d+)[.,](\d+)').firstMatch(raw.trim());
  if (match != null) {
    return Duration(
      hours: int.parse(match.group(1)!),
      minutes: int.parse(match.group(2)!),
      seconds: int.parse(match.group(3)!),
      milliseconds: int.parse(match.group(4)!.padRight(3, '0').substring(0, 3)),
    );
  }
  if (short != null) {
    return Duration(
      minutes: int.parse(short.group(1)!),
      seconds: int.parse(short.group(2)!),
      milliseconds: int.parse(short.group(3)!.padRight(3, '0').substring(0, 3)),
    );
  }
  return null;
}
