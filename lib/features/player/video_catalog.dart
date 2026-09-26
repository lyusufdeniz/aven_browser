import 'dart:convert';

class VideoSource {
  const VideoSource({
    required this.url,
    required this.label,
    this.headers = const {},
    this.durationSeconds,
  });

  final String url;
  final String label;
  final Map<String, String> headers;

  /// Seconds when known; `null`/0 unknown; negative means live/unbounded.
  final double? durationSeconds;
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
        final durationRaw = source['duration'] ?? item['duration'];
        final duration = switch (durationRaw) {
          num n => n.toDouble(),
          String s => double.tryParse(s),
          _ => null,
        };
        sources.add(
          VideoSource(
            url: url,
            label: label is String && label.isNotEmpty
                ? label
                : qualityLabelForUrl(url),
            durationSeconds: duration,
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
      pushSource(pageSources, el.getAttribute(key), 'Gömülü');
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
    if (u.indexOf('blob:') === 0 || u.indexOf('mediastream:') === 0 || u.indexOf('data:') === 0) return false;
    if (isAdMedia(u)) return false;
    var path = u.split('?')[0].split('#')[0];
    if (path.length > 3 && path.slice(-3) === '.ts') return false;
    if (path.slice(-4) === '.m4s' || path.slice(-4) === '.aac') return false;
    if (/\.(m3u8|mpd|mp4|webm|mkv|mov|m4v)(\?|#|$)/i.test(u)) return true;
    if (u.indexOf('.m3u8') !== -1 || u.indexOf('.mpd') !== -1) return true;
    if (/[?&](type|format|ext|video_format|media)=(m3u8|mpd|mp4|hls|dash|video)/i.test(u)) return true;
    if (u.indexOf('/hls/') !== -1 || u.indexOf('/dash/') !== -1 || u.indexOf('/hds/') !== -1) return true;
    if (u.indexOf('live-video.net') !== -1 &&
        (u.indexOf('.m3u8') !== -1 || u.indexOf('/hls') !== -1 || u.indexOf('playlist') !== -1 || u.indexOf('master') !== -1)) {
      return true;
    }
    if (u.indexOf('/stream/') !== -1 && u.indexOf('.m3u8') !== -1) return true;
    if (u.indexOf('playlist') !== -1 && (u.indexOf('m3u8') !== -1 || u.indexOf('hls') !== -1)) return true;
    if (u.indexOf('manifest') !== -1 && (u.indexOf('video') !== -1 || u.indexOf('dash') !== -1 || u.indexOf('hls') !== -1)) return true;
    if (u.indexOf('googlevideo.com') !== -1 && u.indexOf('mime=video') !== -1) return true;
    if (u.indexOf('videoplayback') !== -1 && u.indexOf('http') === 0) return true;
    if (/[?&](file|source|src|media|mp4|hls|stream)=https?%3a/i.test(u)) return true;
    if (u.indexOf('videodelivery.net') !== -1 || u.indexOf('cloudflarestream.com') !== -1) return true;
    if (u.indexOf('vz-') !== -1 && u.indexOf('.b-cdn.net') !== -1) return true;
    if ((u.indexOf('okcdn') !== -1 || u.indexOf('vkvd') !== -1 || u.indexOf('mycdn.me') !== -1) &&
        (u.indexOf('video') !== -1 || u.indexOf('.mp4') !== -1 || u.indexOf('hls') !== -1)) return true;
    return false;
  }
  function isAdMedia(u) {
    if (!u) return true;
    var marks = [
      'doubleclick', 'googlesyndication', 'googleads', 'imasdk', 'pagead', 'adsbygoogle',
      'adservice', 'adserver', 'adnxs', 'adsrvr', 'advertising.com', 'adsystem',
      'spotx', 'teads.', 'teads.tv', 'exoclick', 'exosrv', 'popads', 'popcash',
      'propellerads', 'propellerclick', 'juicyads', 'hilltopads', 'adsterra',
      'trafficjunky', 'serving-sys', 'adsafeprotected', 'moatads', 'amazon-adsystem',
      'preroll', 'midroll', 'postroll', 'vmap', 'pubmatic', 'rubiconproject',
      'openx.net', 'casalemedia', 'taboola', 'outbrain', 'criteo'
    ];
    for (var i = 0; i < marks.length; i++) if (u.indexOf(marks[i]) !== -1) return true;
    if (u.indexOf('/ads/') !== -1 || u.indexOf('/ad/') !== -1) return true;
    if (u.indexOf('vast') !== -1 && (u.indexOf('ad') !== -1 || u.indexOf('.xml') !== -1)) return true;
    return false;
  }
  function notePlayerFrame() {
    try {
      var iframes = document.querySelectorAll('iframe[src],iframe[data-src]');
      var best = '', area = 0;
      for (var i = 0; i < iframes.length; i++) {
        var src = iframes[i].getAttribute('src') || iframes[i].getAttribute('data-src') || '';
        if (!src || src.indexOf('http') !== 0) continue;
        if (!/dplayer|rapidrame|closeload|embed|player|vidmo|ok\.ru|sibnet|filemoon|voe\.|streamtape|iframe\.php/i.test(src)) continue;
        var r = iframes[i].getBoundingClientRect();
        var a = r.width * r.height;
        if (a > area && r.width > 120 && r.height > 70) { area = a; best = abs(src); }
      }
      if (best) window.__avenPlayerFrame = best;
    } catch (e) {}
  }
  window.__avenPool = window.__avenPool || [];
  function remember(url, label, duration) {
    url = abs(url);
    if (!looksMedia(url)) return;
    for (var i = 0; i < window.__avenPool.length; i++) {
      if (window.__avenPool[i].url === url) {
        if (duration && (!window.__avenPool[i].duration || Math.abs(duration) > Math.abs(window.__avenPool[i].duration || 0))) {
          window.__avenPool[i].duration = duration;
        }
        return;
      }
    }
    window.__avenPool.push({url: url, label: label || 'Net', duration: duration || 0});
    if (window.__avenPool.length > 64) window.__avenPool.shift();
  }
  function pushSource(list, url, label, duration) {
    url = abs(url);
    if (!url || url.indexOf('blob:') === 0 || url.indexOf('mediastream:') === 0) return;
    if (url.indexOf('http:') !== 0 && url.indexOf('https:') !== 0) return;
    if (!looksMedia(url)) return;
    remember(url, label, duration);
    for (var i = 0; i < list.length; i++) {
      if (list[i].url === url) {
        if (duration && (!list[i].duration || Math.abs(duration) > Math.abs(list[i].duration || 0))) {
          list[i].duration = duration;
        }
        return;
      }
    }
    list.push({url: url, label: label || 'Kaynak', duration: duration || 0});
  }
  function scrapeText(text, list, label) {
    if (!text || text.length > 2500000) return;
    try {
      if (text.indexOf('\\u') !== -1 || text.indexOf('\\/') !== -1) {
        text = text.replace(/\\u([0-9a-fA-F]{4})/g, function(_, h) {
          return String.fromCharCode(parseInt(h, 16));
        }).replace(/\\\//g, '/');
      }
    } catch (e) {}
    var re = /https?:\/\/[^"'\\\s<>]+/gi;
    var m;
    while ((m = re.exec(text))) {
      var raw = m[0].replace(/[),;]+$/, '');
      if (looksMedia(raw)) pushSource(list, raw, label || 'Sayfa');
    }
    var fileRe = /(?:file|source|src|url|link|stream|video|hls|playlist|fileUrl|videoUrl|file_url|mediaUrl|playbackUrl|contentUrl|srcUrl)\s*[:=]\s*["']([^"']+)["']/gi;
    while ((m = fileRe.exec(text))) {
      if (looksMedia(m[1]) || /\.(m3u8|mp4|webm|mpd|mkv)/i.test(m[1])) pushSource(list, m[1], label || 'Oyuncu');
    }
    var encRe = /(?:file|source|src|url)=((?:https?|HTTPS?)(?::|%3A|%3a)(?:\/\/|%2F%2F|%2f%2f)[^"'&\s]+)/g;
    while ((m = encRe.exec(text))) {
      var decoded = m[1];
      try { decoded = decodeURIComponent(decoded); } catch (e) {}
      if (looksMedia(decoded)) pushSource(list, decoded, label || 'Param');
    }
  }
  function describe(video) {
    var sources = collectPlayable(video);
    if (!sources.length) return '';
    var tracks = [];
    if (video) {
      var trackNodes = video.querySelectorAll('track');
      for (var t = 0; t < trackNodes.length; t++) {
        var track = trackNodes[t];
        var trackUrl = abs(track.src);
        if (!trackUrl) continue;
        tracks.push({
          url: trackUrl,
          kind: track.kind || 'subtitles',
          label: track.label || track.srclang || track.kind || 'Parca'
        });
      }
    }
    var seconds = video ? videoSeconds(video) : 0;
    if (seconds) {
      for (var i = 0; i < sources.length; i++) {
        if (!sources[i].duration) sources[i].duration = seconds;
      }
    }
    return JSON.stringify({sources: sources, tracks: tracks, duration: seconds});
  }
  function collectPlayable(video) {
    var sources = [];
    if (video) {
      var cur = video.currentSrc || video.src || '';
      var seconds = videoSeconds(video);
      if (cur && cur.indexOf('blob:') !== 0 && cur.indexOf('mediastream:') !== 0) {
        pushSource(sources, cur, 'Oynatilan', seconds);
      }
      var sourceNodes = video.querySelectorAll('source');
      for (var s = 0; s < sourceNodes.length; s++) {
        var node = sourceNodes[s];
        var nodeSrc = node.src || node.getAttribute('src') || '';
        if (nodeSrc.indexOf('blob:') === 0) continue;
        pushSource(sources, nodeSrc, node.getAttribute('label') || node.getAttribute('res') || node.getAttribute('type') || ('Kaynak ' + (s + 1)), seconds);
      }
    }
    for (var i = window.__avenPool.length - 1; i >= 0; i--) {
      pushSource(sources, window.__avenPool[i].url, window.__avenPool[i].label, window.__avenPool[i].duration);
    }
    harvestPage(sources);
    harvestPlayers(sources);
    return sources;
  }
  function harvestPage(list) {
    var attrs = document.querySelectorAll('[data-src],[data-file],[data-video],[data-url],[data-link],[data-hls],[data-stream],[data-source],[data-mp4],[data-playlist],[data-setup]');
    for (var a = 0; a < attrs.length; a++) {
      var el = attrs[a];
      ['data-src','data-file','data-video','data-url','data-link','data-hls','data-stream','data-source','data-mp4','data-playlist'].forEach(function(key) {
        pushSource(list, el.getAttribute(key), 'Gömülü');
      });
      var setup = el.getAttribute('data-setup');
      if (setup) scrapeText(setup, list, 'Setup');
    }
    var iframes = document.querySelectorAll('iframe[src],iframe[data-src]');
    for (var f = 0; f < iframes.length; f++) {
      var src = iframes[f].getAttribute('src') || iframes[f].getAttribute('data-src') || '';
      if (looksMedia(src)) pushSource(list, src, 'Iframe');
      else if (src) scrapeText(src, list, 'Iframe');
    }
    if (window.performance && performance.getEntriesByType) {
      var entries = performance.getEntriesByType('resource');
      for (var e = 0; e < entries.length; e++) pushSource(list, entries[e].name || '', 'Net');
    }
    if (window.__avenPool && window.__avenPool.length >= 4) return;
    var scripts = document.querySelectorAll('script:not([src])');
    var limit = window.__avenLite ? 20 : 40;
    for (var i = 0; i < Math.min(scripts.length, limit); i++) {
      scrapeText(scripts[i].textContent || '', list, 'Script');
    }
  }
  function harvestPlayers(list) {
    try {
      if (typeof window.jwplayer === 'function') {
        var nodes = document.querySelectorAll('.jwplayer, [id]');
        for (var i = 0; i < nodes.length && i < 12; i++) {
          try {
            var id = nodes[i].id;
            if (!id) continue;
            var p = window.jwplayer(id);
            if (!p || typeof p.getPlaylist !== 'function') continue;
            var pl = p.getPlaylist() || [];
            for (var j = 0; j < pl.length; j++) {
              var item = pl[j] || {};
              var dur = item.duration || 0;
              var sources = item.sources || [];
              for (var k = 0; k < sources.length; k++) {
                var s = sources[k] || {};
                pushSource(list, s.file || s.src || '', s.label || 'JW', dur);
              }
              if (item.file) pushSource(list, item.file, 'JW', dur);
            }
            if (typeof p.getConfig === 'function') {
              var cfg = p.getConfig() || {};
              if (cfg.file) pushSource(list, cfg.file, 'JW', cfg.duration || 0);
              scrapeText(JSON.stringify(cfg), list, 'JW');
            }
          } catch (e) {}
        }
      }
    } catch (e) {}
    try {
      if (window.videojs) {
        var vjs = document.querySelectorAll('.video-js, video');
        for (var v = 0; v < vjs.length && v < 8; v++) {
          try {
            var player = window.videojs.getPlayer ? window.videojs.getPlayer(vjs[v]) : null;
            if (!player) continue;
            var cache = player.cache_ || {};
            if (cache.src) pushSource(list, cache.src, 'VideoJS', player.duration && player.duration());
            if (typeof player.currentSrc === 'function') pushSource(list, player.currentSrc(), 'VideoJS', player.duration && player.duration());
          } catch (e) {}
        }
      }
    } catch (e) {}
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
        openFocused(anchor, btn.__avenPayload);
      }, true);
      document.documentElement.appendChild(btn);
      anchor.__avenBadge = btn;
    }
    btn.__avenPayload = payload;
    hideOtherBadges(anchor);
    var hidden = rect.bottom < 0 || rect.top > window.innerHeight || rect.right < 0 || rect.left > window.innerWidth;
    btn.style.display = hidden ? 'none' : 'inline-flex';
    btn.style.top = Math.max(8, rect.top + 8) + 'px';
    btn.style.right = Math.max(8, (window.innerWidth - rect.right) + 8) + 'px';
    btn.style.left = 'auto';
  }
  function hideOtherBadges(keep) {
    var nodes = document.querySelectorAll('video, iframe, [data-player], .jwplayer, .video-js, #player');
    for (var i = 0; i < nodes.length; i++) {
      var badge = nodes[i].__avenBadge;
      if (!badge || nodes[i] === keep) continue;
      badge.style.display = 'none';
    }
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
  function focusedPlayer(preferred) {
    if (preferred && preferred.getBoundingClientRect) {
      var pref = preferred.getBoundingClientRect();
      if (pref.width > 80 && pref.height > 48) return preferred;
    }
    var playing = null;
    var best = 0;
    var videos = document.querySelectorAll('video');
    for (var i = 0; i < videos.length; i++) {
      var v = videos[i];
      if (v.paused || v.ended) continue;
      var rect = v.getBoundingClientRect();
      var area = rect.width * rect.height;
      if (area > best && rect.width > 80 && rect.height > 48) {
        best = area;
        playing = v;
      }
    }
    return playing || largestPlayer();
  }
  function silence(video) {
    if (!video) return;
    try {
      video.pause();
      video.removeAttribute('autoplay');
      video.autoplay = false;
      video.preload = 'metadata';
    } catch (e) {}
  }
  function sendPayload(payload) {
    if (!payload || !window.AvenVideo) return false;
    var now = Date.now();
    if (window.__avenLastPayload === payload && now - (window.__avenLastAt || 0) < 2800) return false;
    window.__avenLastPayload = payload;
    window.__avenLastAt = now;
    try { AvenVideo.postMessage(payload); return true; } catch (e) { return false; }
  }
  // Prepare sources + badge only. Never auto-open the external player.
  function prepare(video) {
    if (!video) return;
    var target = focusedPlayer(video);
    if (!target) return;
    var tries = 0;
    function attempt() {
      var payload = null;
      if (target.tagName === 'VIDEO') payload = describe(target);
      if (!payload) {
        var sources = collectPlayable(target.tagName === 'VIDEO' ? target : null);
        if (sources.length) {
          payload = JSON.stringify({
            sources: sources,
            tracks: [],
            duration: target.tagName === 'VIDEO' ? videoSeconds(target) : 0
          });
        }
      }
      if (payload) {
        placeBadge(target, payload);
        return;
      }
      tries += 1;
      if (tries < 10) setTimeout(attempt, 400);
    }
    attempt();
  }
  function openFocused(anchor, existingPayload) {
    var target = focusedPlayer(anchor);
    if (target && target.tagName === 'VIDEO') silence(target);
    window.__avenWantPlay = true;
    var payload = existingPayload;
    if (!payload && target && target.tagName === 'VIDEO') payload = describe(target);
    if (!payload) {
      var sources = collectPlayable(target && target.tagName === 'VIDEO' ? target : null);
      if (sources.length) {
        payload = JSON.stringify({sources: sources, tracks: [], duration: 0});
      }
    }
    if (!payload) return;
    if (target) placeBadge(target, payload);
    sendPayload(payload);
  }
  window.__avenPrepare = prepare;
  window.__avenOpenFocused = function() { openFocused(focusedPlayer(), null); };
  function report(video) {
    prepare(video);
  }
  function offerUrl(url, label, duration) {
    if (!looksMedia(url)) return;
    url = abs(url);
    remember(url, label || 'Video', duration);
    var target = focusedPlayer() || largestPlayer();
    if (!target || target === document.body) return;
    var payload = target.__avenBadge && target.__avenBadge.__avenPayload;
    var data = {sources: [], tracks: [], duration: 0};
    try { if (payload) data = JSON.parse(payload); } catch (e) {}
    if (!data.sources) data.sources = [];
    for (var s = 0; s < data.sources.length; s++) if (data.sources[s].url === url) {
      if (duration && !data.sources[s].duration) data.sources[s].duration = duration;
      placeBadge(target, JSON.stringify(data));
      return;
    }
    data.sources.push({url: url, label: label || 'Video', duration: duration || 0});
    placeBadge(target, JSON.stringify(data));
  }
  window.__avenOffer = function(url) {
    if (!url) return;
    offerUrl(url, 'Video');
  };
  function hook(video) {
    if (!video || video.__avenHook) return;
    video.__avenHook = true;
    // Do not strip autoplay/preload â€” site players (HLS/preroll) need them.
    video.addEventListener('play', function() { prepare(video); }, true);
    video.addEventListener('playing', function() { prepare(video); }, true);
    video.addEventListener('loadeddata', function() { prepare(video); });
    if (video.currentSrc || video.src || !video.paused) prepare(video);
  }
  function collect(root, out) {
    if (!root || !root.querySelectorAll) return;
    var nodes = root.querySelectorAll('video');
    for (var i = 0; i < nodes.length; i++) out.push(nodes[i]);
    // Only probe known player hosts for shadow roots — walking every element freezes TV WebView.
    var hosts = root.querySelectorAll('.jwplayer, .video-js, [data-player], .plyr, plyr, media-controller');
    for (var j = 0; j < Math.min(hosts.length, 12); j++) {
      if (hosts[j].shadowRoot) collect(hosts[j].shadowRoot, out);
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
    var focus = focusedPlayer();
    if (focus && focus.__avenBadge) {
      placeBadge(focus, focus.__avenBadge.__avenPayload);
      return;
    }
    var nodes = document.querySelectorAll('video, iframe, [data-player], .jwplayer, .video-js, #player');
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].__avenBadge) placeBadge(nodes[i], nodes[i].__avenBadge.__avenPayload);
    }
  }
  function scan() {
    notePlayerFrame();
    if (anyPlaying()) {
      var focus = focusedPlayer();
      if (focus) prepare(focus);
      lightScan();
      return;
    }
    var videos = [];
    collect(document, videos);
    for (var i = 0; i < videos.length; i++) {
      hook(videos[i]);
    }
    var focusIdle = largestPlayer();
    if (focusIdle && focusIdle.__avenBadge) {
      placeBadge(focusIdle, focusIdle.__avenBadge.__avenPayload);
    }
    scanPageMedia();
  }
  function hookNetwork() {
    // Separate flag from adblock (__avenAdNetHook) so both wrappers can chain.
    if (window.__avenMediaNetHook) return;
    window.__avenMediaNetHook = true;
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
              var ct = '';
              try { ct = (res.headers && res.headers.get && res.headers.get('content-type')) || ''; } catch (e) {}
              if (ct && (ct.indexOf('mpegurl') !== -1 || ct.indexOf('dash+xml') !== -1 || ct.indexOf('application/vnd.apple.mpegurl') !== -1)) {
                if (res.url) offerUrl(res.url, 'Net');
              }
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
              var url = String(xhr.__avenUrl || '');
              var ct = '';
              try { ct = (xhr.getResponseHeader && xhr.getResponseHeader('content-type')) || ''; } catch (e) {}
              var worth = looksMedia(url) ||
                /mpegurl|dash\+xml|json|javascript|text\/plain|text\/html/i.test(ct) ||
                /\.m3u8|\.mpd|playlist|manifest/i.test(url);
              if (!worth) return;
              var text = xhr.responseText || '';
              if (text && text.length < 400000) {
                var found = [];
                scrapeText(text, found, 'XHR');
                for (var i = 0; i < found.length; i++) offerUrl(found[i].url, 'XHR', found[i].duration);
                if (text.indexOf('#EXTM3U') === 0 && url) offerUrl(url, 'HLS');
              }
            } catch (e) {}
          });
          return send.apply(this, arguments);
        };
      }
    } catch (e) {}
    try {
      if (!window.__avenLite && window.PerformanceObserver) {
        var po = new PerformanceObserver(function(list) {
          var entries = list.getEntries();
          for (var i = 0; i < entries.length; i++) {
            if (looksMedia(entries[i].name)) offerUrl(entries[i].name, 'Net');
          }
        });
        po.observe({type: 'resource', buffered: true});
      }
    } catch (e) {}
  }
  function hookMediaPlay() {
    if (window.__avenPlayHook || !window.HTMLMediaElement) return;
    window.__avenPlayHook = true;
    try {
      var orig = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function() {
        var media = this;
        var result = orig.apply(this, arguments);
        if (media && media.tagName === 'VIDEO') {
          try {
            Promise.resolve(result).then(function() { prepare(media); }, function() { prepare(media); });
          } catch (e) { prepare(media); }
        }
        return result;
      };
    } catch (e) {}
  }
  function start() {
    var root = document.documentElement;
    if (!root) {
      document.addEventListener('DOMContentLoaded', start);
      return;
    }
    hookNetwork();
    hookMediaPlay();
    var observer = null;
    var debounce = null;
    var scrollQuiet = null;
    var scrolling = false;
    function scheduleScan() {
      if (scrolling) return;
      if (anyPlaying()) {
        lightScan();
        return;
      }
      if (debounce) return;
      // Heavier debounce while lite browsing — fewer full DOM walks on TV.
      var wait = window.__avenLite ? 2200 : 1200;
      debounce = setTimeout(function() {
        debounce = null;
        if (scrolling) return;
        scan();
      }, wait);
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
      scrolling = true;
      if (scrollQuiet) clearTimeout(scrollQuiet);
      scrollQuiet = setTimeout(function() {
        scrolling = false;
        scrollQuiet = null;
        if (anyPlaying()) lightScan();
        else scheduleScan();
      }, window.__avenLite ? 1100 : 500);
      if (anyPlaying()) lightScan();
    }, {passive: true, capture: true});
    document.addEventListener('play', function(event) {
      var target = event.target;
      if (target && target.tagName === 'VIDEO') {
        ensureObserver(false);
        prepare(target);
      }
    }, true);
    document.addEventListener('pause', function() {
      if (!anyPlaying()) ensureObserver(true);
    }, true);
    document.addEventListener('click', function() {
      if (!anyPlaying()) setTimeout(scan, 700);
    }, true);
    setInterval(function() {
      if (scrolling) return;
      if (anyPlaying()) {
        ensureObserver(false);
        var focus = focusedPlayer();
        if (focus) prepare(focus);
        lightScan();
      } else {
        ensureObserver(true);
        scan();
      }
    }, window.__avenLite ? 10000 : 6000);
  }
  install();
})();
''';

String get videoWatchScript => _watchScript;

String qualityLabelForUrl(String url) {
  final lower = url.toLowerCase();
  if (lower.contains('2160') || lower.contains('4k') || lower.contains('uhd')) {
    return '2160p';
  }
  if (lower.contains('1440') || lower.contains('qhd')) return '1440p';
  if (lower.contains('1080') || lower.contains('fhd') || lower.contains('/fullhd')) {
    return '1080p';
  }
  if (lower.contains('720') || RegExp(r'[/_\-.]hd([/_\-.]|$)').hasMatch(lower)) {
    return '720p';
  }
  if (lower.contains('540')) return '540p';
  if (lower.contains('480') || RegExp(r'[/_\-.]sd([/_\-.]|$)').hasMatch(lower)) {
    return '480p';
  }
  if (lower.contains('360')) return '360p';
  if (lower.contains('240')) return '240p';
  if (lower.contains('.m3u8') || lower.contains('mpegurl') || lower.contains('/hls/')) {
    return 'HLS';
  }
  if (lower.contains('.mpd') || lower.contains('dash')) return 'DASH';
  if (lower.contains('.mp4')) return 'MP4';
  return 'Ak\u0131\u015f';
}

/// Human-readable duration for source rows (`1:42:05`, `12:03`, or `Canl\u0131`).
String formatSourceDuration(double? seconds) {
  if (seconds == null || seconds == 0) return '';
  if (seconds < 0 || !seconds.isFinite) return 'Canl\u0131';
  final total = seconds.round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}


/// Preroll / VAST / ad-network media that should not open in Aven player.
bool isAdMediaUrl(String url) {
  final u = url.toLowerCase();
  const marks = <String>[
    'doubleclick',
    'googlesyndication',
    'googleads',
    'imasdk',
    'pagead',
    'adsbygoogle',
    'adservice',
    'adserver',
    'adnxs',
    'adsrvr',
    'advertising.com',
    'adsystem',
    'spotx',
    'teads.',
    'teads.tv',
    'exoclick',
    'exosrv',
    'popads',
    'popcash',
    'propellerads',
    'propellerclick',
    'juicyads',
    'hilltopads',
    'adsterra',
    'trafficjunky',
    'serving-sys',
    'adsafeprotected',
    'moatads',
    'amazon-adsystem',
    'preroll',
    'midroll',
    'postroll',
    'vmap',
    'pubmatic',
    'rubiconproject',
    'openx.net',
    'casalemedia',
    'taboola',
    'outbrain',
    'criteo',
  ];
  for (final m in marks) {
    if (u.contains(m)) return true;
  }
  if (u.contains('/ads/') || u.contains('/ad/')) return true;
  if (u.contains('vast') && (u.contains('ad') || u.contains('.xml'))) return true;
  return false;
}

/// Lower is better. Prefer TR embed CDNs and real playlists over ad MP4s.
int contentHostScore(String url) {
  final u = url.toLowerCase();
  if (u.contains('dplayer') || u.contains('rapidrame') || u.contains('closeload')) return 0;
  if (u.contains('b-cdn.net') || u.contains('bunny') || u.contains('videodelivery')) return 1;
  if (u.contains('cloudflarestream') || u.contains('cdn77') || u.contains('jwpcdn')) return 2;
  if (u.contains('.m3u8') && u.contains('master')) return 3;
  if (u.contains('.m3u8')) return 4;
  if (u.contains('.mpd')) return 5;
  if (u.contains('.mp4')) return 6;
  return 8;
}
bool _playable(String url) {
  if (!url.startsWith('http://') && !url.startsWith('https://')) return false;
  if (isAdMediaUrl(url)) return false;
  final lower = url.toLowerCase();
  final path = lower.split('?').first.split('#').first;
  if (path.endsWith('.ts')) return false;
  return true;
}

List<VideoSource> _uniqueSources(List<VideoSource> sources) {
  final seen = <String, VideoSource>{};
  for (final source in sources) {
    final prev = seen[source.url];
    if (prev == null) {
      seen[source.url] = source;
      continue;
    }
    final prevDur = prev.durationSeconds ?? 0;
    final nextDur = source.durationSeconds ?? 0;
    if (nextDur.abs() > prevDur.abs()) {
      seen[source.url] = source;
    }
  }
  return seen.values.toList();
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
