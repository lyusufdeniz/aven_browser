/// Helpers for deciding when a URL is a normal web page or a media/stream site.
bool isAvenWebUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  return url.startsWith('http://') || url.startsWith('https://');
}

bool isAvenMediaSite(String? url) {
  final raw = url ?? '';
  final uri = Uri.tryParse(raw);
  final host = uri?.host.toLowerCase() ?? '';
  final path = uri?.path.toLowerCase() ?? '';
  if (host.isEmpty) return false;

  // Well-known global media / social platforms.
  const markers = [
    'youtube.com',
    'youtu.be',
    'youtube-nocookie.com',
    'kick.com',
    'twitch.tv',
    'vimeo.com',
    'dailymotion.com',
    'rumble.com',
    'netflix.com',
    'disneyplus.com',
    'primevideo.com',
    'hulu.com',
    'crunchyroll.com',
    'spotify.com',
    'soundcloud.com',
    'tiktok.com',
    'facebook.com',
    'fb.watch',
    'instagram.com',
    'x.com',
    'twitter.com',
  ];
  for (final m in markers) {
    if (host == m || host.endsWith('.$m')) return true;
  }

  // Universal watch/stream path shapes (any language / region).
  const watchPaths = [
    '/watch',
    '/embed',
    '/episode',
    '/video/',
    '/videos/',
    '/play/',
    '/player',
    '/stream',
    '/live',
    '/channel',
    '/clip',
    '/movie',
    '/film',
    '/series',
    '/season',
    '/trailer',
  ];
  for (final p in watchPaths) {
    if (path.contains(p)) return true;
  }

  // /slug-title-2024/ style single-segment watch pages.
  final seg = path.replaceAll(RegExp(r'^/+|/$'), '');
  if (seg.isNotEmpty &&
      !seg.contains('/') &&
      RegExp(r'-\d{4}$').hasMatch(seg) &&
      seg.length > 8) {
    return true;
  }
  return false;
}

bool isAvenStreamUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('.m3u8') ||
      lower.contains('.mpd') ||
      lower.contains('/hls/') ||
      lower.contains('playlist.m3u8') ||
      lower.contains('master.m3u8');
}
