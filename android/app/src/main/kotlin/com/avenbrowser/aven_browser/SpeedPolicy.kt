package com.avenbrowser.aven_browser


internal val speedHostSuffixes = listOf(
    "google-analytics.com",
    "googletagmanager.com",
    "googletagservices.com",
    "analytics.google.com",
    "region1.google-analytics.com",
    "stats.g.doubleclick.net",
    "scorecardresearch.com",
    "quantserve.com",
    "hotjar.com",
    "fullstory.com",
    "mouseflow.com",
    "clarity.ms",
    "mixpanel.com",
    "amplitude.com",
    "segment.io",
    "segment.com",
    "sentry.io",
    "bugsnag.com",
    "newrelic.com",
    "nr-data.net",
    "fpjs.io",
    "fingerprintjs.com",
    "intercom.io",
    "intercomcdn.com",
    "crisp.chat",
    "tawk.to",
    "zendesk.com",
    "zdassets.com",
    "drift.com",
    "driftt.com",
    "fonts.googleapis.com",
    "fonts.gstatic.com",
    "use.typekit.net",
    "use.fontawesome.com",
    "kit.fontawesome.com",
    "fontawesome.com",
    "connect.facebook.net",
    "staticxx.facebook.com",
    // Stream chat / emote CDNs (TV doesn't need live chat chrome).
    "betterttv.net",
    "frankerfacez.com",
    "7tv.app",
    "7tv.io",
    "cdn.betterttv.net",
    "cdn.frankerfacez.com",
    "giphy.com",
    "tenor.com",
    "gfycat.com",
    "emoji.slack-edge.com",
    "twemoji.maxcdn.com",
)

internal val speedPathMarkers = listOf(
    "/analytics.js",
    "/gtag/js",
    "/gtm.js",
    "/fbevents.js",
    "/hotjar-",
    "/clarity.js",
    "/fpjs",
    "/fingerprint",
    "/emotes/",
    "/emote/",
    "/chat-emotes",
    "/twemoji/",
)

internal val speedStyleScript = """
(function(){
  if (document.getElementById('aven-speed-style')) return;
  var s = document.createElement('style');
  s.id = 'aven-speed-style';
  s.textContent = [
    'html{font-family:sans-serif!important}',
    '@font-face{font-display:optional!important}',
    'link[rel="preload"][as="font"]{display:none!important}'
  ].join('');
  (document.head || document.documentElement).appendChild(s);
})();
""".trimIndent()

internal fun speedNetworkHookScript(): String {
    val suffixes = speedHostSuffixes.joinToString(",") { "\"$it\"" }
    return """
(function(){
  if (window.__avenSpeedHook) return;
  window.__avenSpeedHook = true;
  var suffixes = [$suffixes];
  function blockedHost(host) {
    host = String(host || '').toLowerCase();
    if (!host) return false;
    for (var i = 0; i < suffixes.length; i++) {
      var s = suffixes[i];
      if (host === s || host.endsWith('.' + s)) return true;
    }
    return false;
  }
  function blockedUrl(url) {
    try { return blockedHost(new URL(url, location.href).hostname); } catch (e) { return false; }
  }
  var ofetch = window.fetch;
  window.fetch = function(input, init) {
    var url = typeof input === 'string' ? input : (input && input.url);
    if (url && blockedUrl(url)) {
      // Soft-fail: players that await preroll continue instead of hanging.
      return Promise.resolve(new Response('', {status: 204, statusText: 'No Content'}));
    }
    return ofetch.apply(this, arguments);
  };
  var oOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function() {
    try {
      var url = arguments.length > 1 ? arguments[1] : '';
      this.__avenSpeedBlocked = !!(url && blockedUrl(url));
    } catch (e) { this.__avenSpeedBlocked = false; }
    return oOpen.apply(this, arguments);
  };
  var oSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function() {
    if (this.__avenSpeedBlocked) {
      try { this.abort(); } catch (e) {}
      return;
    }
    return oSend.apply(this, arguments);
  };
})();
""".trimIndent()
}

internal fun isSpeedBlocked(host: String, path: String, url: String): Boolean {
    val name = host.lowercase()
    if (name.isEmpty()) return false
    // Never block media / player CDNs.
    if (isAllowedHost(name) ||
        name.contains("live-video.net") ||
        name.contains("googlevideo.com") ||
        name.contains("ytimg.com") ||
        name.contains("ggpht.com") ||
        name.contains("jtvnw.net") ||
        name.contains("twitch.tv") ||
        name.contains("ttvnw.net") ||
        name.contains("vimeocdn.com") ||
        name.contains("akamaihd.net") ||
        name.contains("hls.ttvnw") ||
        name.contains("jwpcdn") ||
        name.contains("jwplayer") ||
        name.contains("cdn77") ||
        name.contains("dplayer") ||
        name.contains("rapidrame") ||
        path.endsWith(".m3u8") ||
        path.endsWith(".mpd") ||
        path.endsWith(".mp4") ||
        path.endsWith(".webm") ||
        path.endsWith(".ts")
    ) {
        return false
    }
    // Keep core Google static/CDN assets that pages need for UI (not fonts.gstatic).
    if (name == "www.gstatic.com" || name == "gstatic.com" || name.endsWith(".gstatic.com")) {
        if (path.contains("/fonts/") || path.endsWith(".woff") || path.endsWith(".woff2") || path.endsWith(".ttf")) {
            return true
        }
        return false
    }
    for (suffix in speedHostSuffixes) {
        if (name == suffix || name.endsWith(".$suffix")) return true
    }
    if (speedPathMarkers.any { path.contains(it) || url.contains(it) }) return true
    if (path.endsWith(".woff") || path.endsWith(".woff2") || path.endsWith(".ttf") || path.endsWith(".otf")) {
        // Third-party webfont files — system fonts are enough on TV.
        return true
    }
    return false
}
