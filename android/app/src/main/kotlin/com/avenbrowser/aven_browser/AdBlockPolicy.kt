package com.avenbrowser.aven_browser

import android.webkit.WebResourceResponse
import java.io.ByteArrayInputStream

internal val ublockSuffixes = listOf(
    "doubleclick.net",
    "googlesyndication.com",
    "googleadservices.com",
    "google-analytics.com",
    "googletagservices.com",
    "adservice.google.com",
    "adnxs.com",
    "adsrvr.org",
    "taboola.com",
    "outbrain.com",
    "criteo.com",
    "criteo.net",
    "moatads.com",
    "scorecardresearch.com",
    "amazon-adsystem.com",
    "pubmatic.com",
    "rubiconproject.com",
    "openx.net",
    "casalemedia.com",
    "smartadserver.com",
    "3lift.com",
    "media.net",
    "popads.net",
    "popcash.net",
    "propellerads.com",
    "propellerads.net",
    "propellerclick.com",
    "exoclick.com",
    "exosrv.com",
    "exrtbsrv.com",
    "juicyads.com",
    "adsterra.com",
    "hilltopads.com",
    "clickadu.com",
    "trafficjunky.net",
    "trafficjunky.com",
    "highperformanceformat.com",
    "onclicka.com",
    "adcash.com",
    "bidvertiser.com",
    "mgid.com",
    "revcontent.com",
    "adskeeper.com",
    "adskeeper.co.uk",
    "adform.net",
    "adformdsp.net",
    "serving-sys.com",
    "adsafeprotected.com",
    "2mdn.net",
    // Keep imasdk.googleapis.com — blocking it freezes many site players on preroll.
    "adcolony.com",
    "unityads.unity3d.com",
    "ads-twitter.com",
    "samsungads.com",
    "hotjar.com",
    "mouseflow.com",
    "luckyorange.com",
    "luckyorange.net",
    "ad.xiaomi.com",
    "ads.oppomobile.com",
    "appmetrica.yandex.ru",
    "2o7.net",
    "onesignal.com",
    "pushwoosh.com",
    "pushengage.com",
    "pushnami.com",
    "zeropark.com",
    // TR / regional ad networks (turk-adfilter + local publishers).
    "admatic.com.tr",
    "adnet.com.tr",
    "admax.com.tr",
    "adklik.com.tr",
    "admost.com",
    "reklamport.com",
    "rekmob.com",
    "reklam.xyz",
    "reklamnative.com",
    "reklm.com",
    "doganburda.com",
    // Do NOT block video-ad / stream CDNs here (viralize, teads, spotx,
    // cdnhipter, affiliate hop domains) — TR film players hang without them.
)

internal val blockedPathMarkers = listOf(
    "/pagead/",
    "/pagead2.",
    "/doubleclick/",
    "/googlesyndication/",
    "/adsbygoogle",
    "/js/widget/ads",
    "/js/pagead",
    // Avoid bare "/ads.js" — some embed players ship scripts with that name.
    "/popunder",
    "/pop.js",
)

internal fun networkHookScript(): String {
    val hosts = AdBlockLists.hosts.joinToString(",") { "\"$it\"" }
    val suffixes = ublockSuffixes.joinToString(",") { "\"$it\"" }
    return """
(function(){
  if (window.__avenNetHook) return;
  window.__avenNetHook = true;
  var hosts = new Set([$hosts]);
  var suffixes = [$suffixes];
  function blockedHost(host) {
    host = String(host || '').toLowerCase();
    if (!host) return false;
    if (hosts.has(host)) return true;
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
      this.__avenBlocked = !!(url && blockedUrl(url));
    } catch (e) { this.__avenBlocked = false; }
    return oOpen.apply(this, arguments);
  };
  var oSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function() {
    if (this.__avenBlocked) {
      try { this.abort(); } catch (e) {}
      return;
    }
    return oSend.apply(this, arguments);
  };
})();
""".trimIndent()
}

internal fun emptyBlockedResponse(): WebResourceResponse {
    return WebResourceResponse(
        "text/plain",
        "utf-8",
        403,
        "Blocked",
        emptyMap(),
        ByteArrayInputStream(ByteArray(0)),
    )
}

internal fun isBlockedAdScriptPath(path: String): Boolean {
    return path.endsWith("/ads.js") ||
        path.endsWith("/pagead.js") ||
        path.endsWith("/js/widget/ads.js") ||
        path.endsWith("/js/pagead.js") ||
        path.contains("/js/widget/ads") ||
        path.contains("/js/pagead") ||
        path.contains("/new-da-manager/") ||
        path.contains("da-helper")
}

internal fun isBlockedPath(path: String): Boolean {
    if (path.isEmpty()) return false
    if (isBlockedAdScriptPath(path)) return true
    return blockedPathMarkers.any { path.contains(it) }
}

internal fun isAllowedHost(host: String): Boolean {
    // Narrow allowlist — do NOT allow analytics / webfont CDNs (speed mode blocks those).
    return when {
        host == "www.gstatic.com" || host == "gstatic.com" || host.endsWith(".gstatic.com") -> true
        host == "www.google.com" || host == "google.com" || host == "accounts.google.com" -> true
        host.endsWith(".ytimg.com") || host.endsWith(".ggpht.com") -> true
        host.endsWith(".jsdelivr.net") || host.endsWith(".jquery.com") -> true
        // TR stream posters + ad/poster CDN (blocking any of these blanks players).
        host.endsWith(".cdnhipter.xyz") || host == "cdnhipter.xyz" -> true
        // JW Player + common HLS CDNs — blocking these blanks site players.
        host == "jwpcdn.com" || host.endsWith(".jwpcdn.com") -> true
        host == "jwplayer.com" || host.endsWith(".jwplayer.com") -> true
        host == "jwplatform.com" || host.endsWith(".jwplatform.com") -> true
        host == "jwpltx.com" || host.endsWith(".jwpltx.com") -> true
        host == "cdn77.org" || host.endsWith(".cdn77.org") -> true
        host.endsWith(".hdfilmcehennemi.mobi") || host == "hdfilmcehennemi.mobi" -> true
        host.endsWith(".hdfilmcehennemi.nl") || host == "hdfilmcehennemi.nl" -> true
        // Rapidrame / alternate embeds used by TR film sites.
        host.contains("dplayer") || host.contains("rapidrame") || host.contains("closeload") -> true
        else -> false
    }
}

internal fun matchesLocalList(host: String): Boolean {
    if (isAllowedHost(host)) return false
    if (AdBlockLists.hosts.contains(host)) return true
    for (suffix in ublockSuffixes) {
        if (host == suffix || host.endsWith(".$suffix")) return true
    }
    return false
}

internal fun isBlockedHost(host: String, mode: String): Boolean {
    val name = host.lowercase()
    if (name.isEmpty() || name == "dns.adguard-dns.com") return false
    if (mode == "off") return false
    return matchesLocalList(name)
}
