import 'dart:convert';

class VideoSource {
  const VideoSource({
    required this.url,
    required this.label,
    this.headers = const {},
  });

  final String url;
  final String label;
  final Map<String, String> headers;
}

class MediaTrack {
  const MediaTrack({
    required this.url,
    required this.kind,
    required this.label,
  });

  final String url;
  final String kind;
  final String label;
}

class PageVideo {
  const PageVideo({required this.sources, required this.tracks});

  final List<VideoSource> sources;
  final List<MediaTrack> tracks;
}

// Probe script and parser live together so the payload shape stays in one place.

PageVideo? parsePlayedVideo(Object? raw) {
  final decoded = _decode(raw);
  final videos = decoded is Map ? parsePageVideos([decoded]) : parsePageVideos(decoded);
  if (videos.isEmpty) return null;
  return videos.first;
}

List<PageVideo> parsePageVideos(Object? raw) {
  final decoded = _decode(raw);
  if (decoded is! List) return const [];
  final videos = <PageVideo>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final sources = <VideoSource>[];
    final sourceRaw = item['sources'];
    if (sourceRaw is List) {
      for (final source in sourceRaw) {
        if (source is! Map) continue;
        final url = source['url'];
        if (url is! String || !_playable(url)) continue;
        final label = source['label'];
        sources.add(
          VideoSource(
            url: url,
            label: label is String && label.isNotEmpty ? label : 'Kaynak',
          ),
        );
      }
    }
    final tracks = <MediaTrack>[];
    final trackRaw = item['tracks'];
    if (trackRaw is List) {
      for (final track in trackRaw) {
        if (track is! Map) continue;
        final url = track['url'];
        if (url is! String || url.isEmpty) continue;
        final kind = track['kind'];
        final label = track['label'];
        tracks.add(
          MediaTrack(
            url: url,
            kind: kind is String ? kind : 'subtitles',
            label: label is String && label.isNotEmpty ? label : 'ParÃ§a',
          ),
        );
      }
    }
    if (sources.isNotEmpty) {
      videos.add(PageVideo(sources: _uniqueSources(sources), tracks: tracks));
    }
  }
  return videos;
}

const _probeScript = r'''
(function() {
  function abs(url) {
    try { return new URL(url, document.baseURI).href; } catch (e) { return url || ''; }
  }
  function looksMedia(url) {
    if (!url) return false;
    var u = String(url).toLowerCase();
    if (u.indexOf('blob:') === 0) return false;
    if (/\.(m3u8|mpd|mp4|webm|mkv|mov)(\?|#|$)/i.test(u)) return true;
    if (u.indexOf('.m3u8') !== -1 || u.indexOf('.mpd') !== -1) return true;
    if (/[?&](type|format|ext)=(m3u8|mpd|mp4|hls)/i.test(u)) return true;
    if (/\/(hls|playlist|master|index)[^/]*\.m3u8/i.test(u)) return true;
    if (u.indexOf('googlevideo.com') !== -1 && u.indexOf('mime=video') !== -1) return true;
    return false;
  }
  function pushSource(list, url, label) {
    url = abs(url);
    if (!url || !looksMedia(url)) {
      if (!url || url.indexOf('http') !== 0) return;
      if (!/\.(m3u8|mpd|mp4|webm|mkv|mov)(\?|#|$)/i.test(url) && url.indexOf('.m3u8') === -1) return;
    }
    if (url.indexOf('blob:') === 0) return;
    for (var i = 0; i < list.length; i++) if (list[i].url === url) return;
    list.push({url: url, label: label || 'Kaynak'});
  }
  function scrapeText(text, list, label) {
    if (!text) return;
    var re = /https?:\/\/[^"'\\\s<>]+/gi;
    var m;
    while ((m = re.exec(text))) {
      var raw = m[0].replace(/[),;]+$/, '');
      if (looksMedia(raw)) pushSource(list, raw, label || 'Sayfa');
    }
    var fileRe = /(?:file|source|src|url|link|stream|video|hls|playlist)\s*[:=]\s*["']([^"']+)["']/gi;
    while ((m = fileRe.exec(text))) {
      if (looksMedia(m[1]) || /\.(m3u8|mp4|webm|mpd)/i.test(m[1])) pushSource(list, m[1], label || 'Oyuncu');
    }
  }
  var videos = [];
  var nodes = document.querySelectorAll('video');
  for (var n = 0; n < nodes.length; n++) {
    var video = nodes[n];
    var sources = [];
    pushSource(sources, video.currentSrc, 'OynatÄ±lan');
    pushSource(sources, video.src, 'Video');
    var sourceNodes = video.querySelectorAll('source');
    for (var s = 0; s < sourceNodes.length; s++) {
      var node = sourceNodes[s];
      pushSource(sources, node.src, node.getAttribute('label') || node.getAttribute('res') || node.getAttribute('type') || ('Kaynak ' + (s + 1)));
    }
    var tracks = [];
    var trackNodes = video.querySelectorAll('track');
    for (var t = 0; t < trackNodes.length; t++) {
      var track = trackNodes[t];
      var trackUrl = abs(track.src);
      if (!trackUrl) continue;
      tracks.push({
        url: trackUrl,
        kind: track.kind || 'subtitles',
        label: track.label || track.srclang || track.kind || 'ParÃ§a'
      });
    }
    if (sources.length) videos.push({sources: sources, tracks: tracks});
  }
  var pageSources = [];
  var attrs = document.querySelectorAll('[data-src],[data-file],[data-video],[data-url],[data-link],[data-hls],[data-stream]');
  for (var a = 0; a < attrs.length; a++) {
    var el = attrs[a];
    ['data-src','data-file','data-video','data-url','data-link','data-hls','data-stream'].forEach(function(key) {
      pushSource(pageSources, el.getAttribute(key), 'GÃ¶mÃ¼lÃ¼');
    });
  }
  var scripts = document.querySelectorAll('script');
  for (var i = 0; i < scripts.length; i++) scrapeText(scripts[i].textContent || '', pageSources, 'Script');
  scrapeText(document.documentElement ? document.documentElement.innerHTML : '', pageSources, 'Sayfa');
  if (window.performance && performance.getEntriesByType) {
    var entries = performance.getEntriesByType('resource');
    for (var e = 0; e < entries.length; e++) pushSource(pageSources, entries[e].name || '', 'Net');
  }
  var metas = document.querySelectorAll('meta[property="og:video"], meta[property="og:video:url"]');
  for (var m = 0; m < metas.length; m++) pushSource(pageSources, metas[m].content, 'Sayfa videosu');
  if (pageSources.length) videos.push({sources: pageSources, tracks: []});
  return JSON.stringify(videos);
})()
''';

String get videoProbeScript => _probeScript;

const _watchScript = r'''
(function() {
  function install() {
    if (!window.AvenVideo) {
      setTimeout(install, 400);
      return;
    }
    if (window.__avenVideoWatch) return;
    window.__avenVideoWatch = true;
    start();
  }
  function abs(url) {
    try { return new URL(url, document.baseURI).href; } catch (e) { return url || ''; }
  }
  function looksMedia(url) {
    if (!url) return false;
    var u = String(url).toLowerCase();
    if (u.indexOf('blob:') === 0) return false;
    if (u.indexOf('doubleclick') !== -1 || u.indexOf('googlesyndication') !== -1 || u.indexOf('imasdk') !== -1) return false;
    var path = u.split('?')[0].split('#')[0];
    if (path.length > 3 && path.slice(-3) === '.ts') return false;
    if (/\.(m3u8|mpd|mp4|webm|mkv|mov)(\?|#|$)/i.test(u)) return true;
    if (u.indexOf('.m3u8') !== -1 || u.indexOf('.mpd') !== -1) return true;
    if (/[?&](type|format|ext)=(m3u8|mpd|mp4|hls)/i.test(u)) return true;
    if (u.indexOf('/hls/') !== -1 && u.indexOf('http') === 0) return true;
    if (u.indexOf('googlevideo.com') !== -1 && u.indexOf('mime=video') !== -1) return true;
    return false;
  }
  function pushSource(list, url, label) {
    url = abs(url);
    if (!url || url.indexOf('blob:') === 0) return;
    if (url.indexOf('http:') !== 0 && url.indexOf('https:') !== 0) return;
    if (!looksMedia(url)) return;
    for (var i = 0; i < list.length; i++) if (list[i].url === url) return;
    list.push({url: url, label: label || 'Kaynak'});
  }
  function scrapeText(text, list, label) {
    if (!text || text.length > 2500000) return;
    var re = /https?:\/\/[^"'\\\s<>]+/gi;
    var m;
    while ((m = re.exec(text))) {
      var raw = m[0].replace(/[),;]+$/, '');
      if (looksMedia(raw)) pushSource(list, raw, label || 'Sayfa');
    }
    var fileRe = /(?:file|source|src|url|link|stream|video|hls|playlist|fileUrl|videoUrl)\s*[:=]\s*["']([^"']+)["']/gi;
    while ((m = fileRe.exec(text))) {
      if (looksMedia(m[1]) || /\.(m3u8|mp4|webm|mpd)/i.test(m[1])) pushSource(list, m[1], label || 'Oyuncu');
    }
  }
  function describe(video) {
    var sources = [];
    pushSource(sources, video.currentSrc, 'OynatÄ±lan');
    pushSource(sources, video.src, 'Video');
    var sourceNodes = video.querySelectorAll('source');
    for (var s = 0; s < sourceNodes.length; s++) {
      var node = sourceNodes[s];
      pushSource(sources, node.src, node.getAttribute('label') || node.getAttribute('res') || node.getAttribute('type') || ('Kaynak ' + (s + 1)));
    }
    var tracks = [];
    var trackNodes = video.querySelectorAll('track');
    for (var t = 0; t < trackNodes.length; t++) {
      var track = trackNodes[t];
      var trackUrl = abs(track.src);
      if (!trackUrl) continue;
      tracks.push({
        url: trackUrl,
        kind: track.kind || 'subtitles',
        label: track.label || track.srclang || track.kind || 'ParÃ§a'
      });
    }
    harvestPage(sources);
    if (!sources.length) return '';
    var seconds = videoSeconds(video);
    return JSON.stringify({sources: sources, tracks: tracks, duration: seconds});
  }
  function harvestPage(list) {
    var attrs = document.querySelectorAll('[data-src],[data-file],[data-video],[data-url],[data-link],[data-hls],[data-stream]');
    for (var a = 0; a < attrs.length; a++) {
      var el = attrs[a];
      ['data-src','data-file','data-video','data-url','data-link','data-hls','data-stream'].forEach(function(key) {
        pushSource(list, el.getAttribute(key), 'GÃ¶mÃ¼lÃ¼');
      });
    }
    var iframes = document.querySelectorAll('iframe[src]');
    for (var f = 0; f < iframes.length; f++) {
      var src = iframes[f].getAttribute('src') || '';
      if (looksMedia(src)) pushSource(list, src, 'Iframe');
    }
    if (window.performance && performance.getEntriesByType) {
      var entries = performance.getEntriesByType('resource');
      for (var e = 0; e < entries.length; e++) pushSource(list, entries[e].name || '', 'Net');
    }
    var scripts = document.querySelectorAll('script:not([src])');
    for (var i = 0; i < Math.min(scripts.length, 40); i++) {
      scrapeText(scripts[i].textContent || '', list, 'Script');
    }
  }
  function videoSeconds(video) {
    var duration = video.duration;
    if (duration === Infinity) return -1;
    if (!isFinite(duration) || duration <= 0) return 0;
    return duration;
  }
  function placeBadge(anchor, payload) {
    if (!anchor || !payload) return;
    var rect = anchor.getBoundingClientRect();
    if (rect.width < 80 || rect.height < 48) return;
    var btn = anchor.__avenBadge;
    if (!btn || !btn.isConnected) {
      btn = document.createElement('button');
      btn.type = 'button';
      btn.style.cssText = 'position:fixed;z-index:2147483646;display:inline-flex;align-items:center;gap:10px;padding:12px 16px;border:1px solid #0B1838;border-radius:14px;background:#080A0B;color:#F3F5F7;font:600 17px sans-serif;box-shadow:0 10px 28px rgba(8,10,11,.65);cursor:pointer;';
      var icon = document.createElement('span');
      icon.style.cssText = 'display:inline-flex;align-items:center;justify-content:center;width:22px;height:22px;border-radius:50%;background:#0B1838;flex:0 0 auto';
      icon.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="#F3F5F7"><path d="M8 5v14l11-7z"/></svg>';
      var label = document.createElement('span');
      label.textContent = 'Aven oynat\u0131c\u0131 ile oynat';
      btn.appendChild(icon);
      btn.appendChild(label);
      btn.onmouseenter = function() { btn.style.borderColor = '#0B1838'; btn.style.background = '#0B1838'; };
      btn.onmouseleave = function() { btn.style.borderColor = '#0B1838'; btn.style.background = '#080A0B'; };
      btn.addEventListener('click', function(event) {
        event.preventDefault();
        event.stopPropagation();
        if (!btn.__avenPayload || !window.AvenVideo) return;
        try { AvenVideo.postMessage(btn.__avenPayload); } catch (e) {}
      }, true);
      document.documentElement.appendChild(btn);
      anchor.__avenBadge = btn;
    }
    btn.__avenPayload = payload;
    var hidden = rect.bottom < 0 || rect.top > window.innerHeight || rect.right < 0 || rect.left > window.innerWidth;
    btn.style.display = hidden ? 'none' : 'inline-flex';
    btn.style.top = Math.max(8, rect.top + 8) + 'px';
    btn.style.right = Math.max(8, (window.innerWidth - rect.right) + 8) + 'px';
    btn.style.left = 'auto';
  }
  function largestPlayer() {
    var nodes = document.querySelectorAll('video, iframe, [data-player], .video-js, .jwplayer, #player, .player, .film-player, .watch-player');
    var target = null;
    var best = 0;
    for (var i = 0; i < nodes.length; i++) {
      var rect = nodes[i].getBoundingClientRect();
      var area = rect.width * rect.height;
      if (area > best && rect.width > 120 && rect.height > 70) {
        best = area;
        target = nodes[i];
      }
    }
    return target;
  }
  function report(video) {
    var payload = describe(video);
    if (!payload) return;
    placeBadge(video, payload);
  }
  function offerUrl(url, label) {
    if (!looksMedia(url)) return;
    url = abs(url);
    var target = largestPlayer();
    if (!target) return;
    var payload = target.__avenBadge && target.__avenBadge.__avenPayload;
    var data = {sources: [], tracks: []};
    try { if (payload) data = JSON.parse(payload); } catch (e) {}
    if (!data.sources) data.sources = [];
    for (var s = 0; s < data.sources.length; s++) if (data.sources[s].url === url) {
      placeBadge(target, JSON.stringify(data));
      return;
    }
    data.sources.push({url: url, label: label || 'Video'});
    placeBadge(target, JSON.stringify(data));
  }
  window.__avenOffer = function(url) {
    if (!url) return;
    offerUrl(url, 'Video');
  };
  function hook(video) {
    if (!video || video.__avenHook) return;
    video.__avenHook = true;
    video.addEventListener('play', function() { report(video); });
    video.addEventListener('playing', function() { report(video); });
    video.addEventListener('loadeddata', function() { if (!video.paused) report(video); });
    if (!video.paused) report(video);
  }
  function collect(root, out) {
    if (!root || !root.querySelectorAll) return;
    var nodes = root.querySelectorAll('video');
    for (var i = 0; i < nodes.length; i++) out.push(nodes[i]);
    var all = root.querySelectorAll('*');
    for (var j = 0; j < all.length; j++) {
      if (all[j].shadowRoot) collect(all[j].shadowRoot, out);
    }
  }
  function scanPageMedia() {
    var sources = [];
    harvestPage(sources);
    if (!sources.length) return;
    var target = largestPlayer();
    if (!target) return;
    var payload = target.__avenBadge && target.__avenBadge.__avenPayload;
    var data = {sources: [], tracks: []};
    try { if (payload) data = JSON.parse(payload); } catch (e) {}
    if (!data.sources) data.sources = [];
    for (var i = 0; i < sources.length; i++) {
      var found = false;
      for (var s = 0; s < data.sources.length; s++) if (data.sources[s].url === sources[i].url) { found = true; break; }
      if (!found) data.sources.push(sources[i]);
    }
    if (data.sources.length) placeBadge(target, JSON.stringify(data));
  }
  function anyPlaying() {
    var vs = document.querySelectorAll('video');
    for (var i = 0; i < vs.length; i++) {
      if (!vs[i].paused && !vs[i].ended && vs[i].readyState > 1) return true;
    }
    return false;
  }
  function lightScan() {
    var nodes = document.querySelectorAll('video, iframe, [data-player], .jwplayer, .video-js, #player');
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].__avenBadge) placeBadge(nodes[i], nodes[i].__avenBadge.__avenPayload);
    }
  }
  function scan() {
    if (anyPlaying()) {
      lightScan();
      return;
    }
    var videos = [];
    collect(document, videos);
    for (var i = 0; i < videos.length; i++) {
      hook(videos[i]);
      if (!videos[i].paused || videos[i].currentSrc || videos[i].src) report(videos[i]);
      if (videos[i].__avenBadge) placeBadge(videos[i], videos[i].__avenBadge.__avenPayload);
    }
    var frames = document.querySelectorAll('iframe, [data-player], .jwplayer, .video-js, #player');
    for (var f = 0; f < frames.length; f++) {
      if (frames[f].__avenBadge) placeBadge(frames[f], frames[f].__avenBadge.__avenPayload);
    }
    scanPageMedia();
  }
  function hookNetwork() {
    if (window.__avenNetHook) return;
    window.__avenNetHook = true;
    try {
      var ofetch = window.fetch;
      if (typeof ofetch === 'function') {
        window.fetch = function() {
          var args = arguments;
          var input = args[0];
          var reqUrl = '';
          try {
            if (typeof input === 'string') reqUrl = input;
            else if (input && input.url) reqUrl = input.url;
          } catch (e) {}
          if (looksMedia(reqUrl)) offerUrl(reqUrl, 'Net');
          return ofetch.apply(this, args).then(function(res) {
            try {
              if (res && res.url && looksMedia(res.url)) offerUrl(res.url, 'Net');
            } catch (e) {}
            return res;
          });
        };
      }
    } catch (e) {}
    try {
      var XO = window.XMLHttpRequest;
      if (XO && XO.prototype) {
        var open = XO.prototype.open;
        XO.prototype.open = function(method, url) {
          try { this.__avenUrl = url; } catch (e) {}
          return open.apply(this, arguments);
        };
        var send = XO.prototype.send;
        XO.prototype.send = function() {
          var xhr = this;
          try {
            if (looksMedia(xhr.__avenUrl)) offerUrl(xhr.__avenUrl, 'Net');
          } catch (e) {}
          xhr.addEventListener('load', function() {
            try {
              if (anyPlaying()) return;
              var text = xhr.responseText || '';
              if (text && text.length < 400000) {
                var found = [];
                scrapeText(text, found, 'XHR');
                for (var i = 0; i < found.length; i++) offerUrl(found[i].url, 'XHR');
              }
            } catch (e) {}
          });
          return send.apply(this, arguments);
        };
      }
    } catch (e) {}
  }
  function start() {
    var root = document.documentElement;
    if (!root) {
      document.addEventListener('DOMContentLoaded', start);
      return;
    }
    hookNetwork();
    var observer = null;
    var debounce = null;
    function scheduleScan() {
      if (anyPlaying()) {
        lightScan();
        return;
      }
      if (debounce) return;
      debounce = setTimeout(function() {
        debounce = null;
        scan();
      }, 400);
    }
    function ensureObserver(on) {
      if (on) {
        if (observer) return;
        observer = new MutationObserver(scheduleScan);
        observer.observe(root, {childList: true, subtree: true});
      } else if (observer) {
        observer.disconnect();
        observer = null;
      }
    }
    scan();
    ensureObserver(true);
    window.addEventListener('scroll', function() {
      if (anyPlaying()) lightScan();
      else scheduleScan();
    }, true);
    document.addEventListener('play', function(event) {
      var target = event.target;
      if (target && target.tagName === 'VIDEO') {
        ensureObserver(false);
        report(target);
      }
    }, true);
    document.addEventListener('pause', function() {
      if (!anyPlaying()) ensureObserver(true);
    }, true);
    document.addEventListener('click', function() {
      if (!anyPlaying()) setTimeout(scan, 700);
    }, true);
    setInterval(function() {
      if (anyPlaying()) {
        ensureObserver(false);
        lightScan();
      } else {
        ensureObserver(true);
        scan();
      }
    }, 2000);
  }
  install();
})();
''';

String get videoWatchScript => _watchScript;

bool _playable(String url) {
  if (!url.startsWith('http://') && !url.startsWith('https://')) return false;
  final lower = url.toLowerCase();
  final path = lower.split('?').first.split('#').first;
  if (path.endsWith('.ts')) return false;
  return true;
}

List<VideoSource> _uniqueSources(List<VideoSource> sources) {
  final seen = <String>{};
  final unique = <VideoSource>[];
  for (final source in sources) {
    if (seen.add(source.url)) unique.add(source);
  }
  return unique;
}

Object? _decode(Object? raw) {
  if (raw is List || raw is Map) return raw;
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return null;
  try {
    final once = jsonDecode(text);
    if (once is String) return jsonDecode(once);
    return once;
  } catch (_) {
    return null;
  }
}
