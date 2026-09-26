/// Helpers for deciding when a URL is a normal web page or a media/stream site.
bool isAvenWebUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  return url.startsWith('http://') || url.startsWith('https://');
}

bool isAvenMediaSite(String? url) {
  final raw = url ?? '';
  final host = Uri.tryParse(raw)?.host.toLowerCase() ?? '';
  final path = Uri.tryParse(raw)?.path.toLowerCase() ?? '';
  if (host.isEmpty) return false;
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
  // TR / pirate stream hosts — slug pages like /movie-name-2026/ embed players.
  const hostHints = [
    'film',
    'dizi',
    'izle',
    'movie',
    'stream',
    'anime',
    'dailymotion',
    'player',
    'sever',
    'pal',
  ];
  for (final h in hostHints) {
    if (host.contains(h)) return true;
  }
  const watchPaths = [
    '/bolum/',
    '/izle',
    '/watch',
    '/embed',
    '/episode',
    '/video/',
    '/play/',
    '/player',
    '/film',
    '/movie',
    '/dizi',
    '/sezon',
  ];
  for (final p in watchPaths) {
    if (path.contains(p)) return true;
  }
  // /slug-title-2024/ style watch pages (single path segment with a year).
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
