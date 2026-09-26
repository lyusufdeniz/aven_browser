package com.avenbrowser.aven_browser

import android.webkit.WebResourceResponse

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
    // Regional ad networks (in addition to global list above).
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
    // affiliate hop domains) — site players hang without them.
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
    // Mega host list stays native (AdBlockLists) + AvenAdblock.isBlocked bridge.
    // Embedding 100k+ domains into evaluateJavascript freezes TV WebView.
    // Include speed-trackers too so one hard-fail hook covers both when adblock is on.
    val suffixes = (ublockSuffixes + speedHostSuffixes).distinct().joinToString(",") { "\"$it\"" }
    return """
(function(){
  if (window.__avenAdNetHook) return;
  window.__avenAdNetHook = true;
  window.__avenSpeedHook = true;
  var suffixes = [$suffixes];
  function blockedHost(host) {
    host = String(host || '').toLowerCase();
    if (!host) return false;
    for (var i = 0; i < suffixes.length; i++) {
      var s = suffixes[i];
      if (host === s || host.endsWith('.' + s)) return true;
    }
    try {
      if (window.AvenAdblock && AvenAdblock.isBlocked(host)) return true;
    } catch (e) {}
    return false;
  }
  function blockedUrl(url) {
    try { return blockedHost(new URL(url, location.href).hostname); } catch (e) { return false; }
  }
  var ofetch = window.fetch;
  window.fetch = function(input, init) {
    var url = typeof input === 'string' ? input : (input && input.url);
    if (url && blockedUrl(url)) {
      return Promise.reject(new TypeError('Failed to fetch'));
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
    return emptyBlockedResponse("", "")
}

/** Instant local stub — no network round-trip for trackers/fonts/widgets. */
internal fun emptyBlockedResponse(url: String, path: String): WebResourceResponse {
    return WebViewEngine.stubResponse(url, path)
}

/**
 * True when a synthetic HTTP response would make the request look "Accessible"
 * on obfusgated-style tests (no-cors HEAD resolves on any completed response).
 * Image/script GET still use a failing native body so onerror fires.
 */
internal fun shouldDeferBlockToJs(request: android.webkit.WebResourceRequest): Boolean {
    val method = request.method?.uppercase() ?: "GET"
    if (method == "HEAD" || method == "OPTIONS") return true
    val dest = request.requestHeaders["Sec-Fetch-Dest"]?.lowercase()
    if (dest == "image" || dest == "script" || dest == "iframe" ||
        dest == "frame" || dest == "embed" || dest == "video" || dest == "audio"
    ) {
        return false
    }
    val mode = request.requestHeaders["Sec-Fetch-Mode"]?.lowercase()
    return mode == "cors" || mode == "no-cors"
}

/** JS bridge: full host list check without embedding 100k domains in evaluateJavascript. */
internal class AdBlockJsBridge(private val mode: () -> String) {
    @android.webkit.JavascriptInterface
    fun isBlocked(host: String?): Boolean {
        if (host.isNullOrBlank()) return false
        val current = mode()
        if (current == "off") return false
        return isBlockedHost(host.lowercase(), current)
    }
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
    // Keep player / CDN infra reachable even if a hosts list over-blocks.
    // No per-site domains — match global player products and static CDNs only.
    return when {
        host == "www.gstatic.com" || host == "gstatic.com" || host.endsWith(".gstatic.com") -> true
        host == "www.google.com" || host == "google.com" || host == "accounts.google.com" -> true
        host.endsWith(".ytimg.com") || host.endsWith(".ggpht.com") -> true
        host.endsWith(".jsdelivr.net") || host.endsWith(".jquery.com") || host.endsWith(".cloudflare.com") -> true
        host == "jwpcdn.com" || host.endsWith(".jwpcdn.com") -> true
        host == "jwplayer.com" || host.endsWith(".jwplayer.com") -> true
        host == "jwplatform.com" || host.endsWith(".jwplatform.com") -> true
        host == "jwpltx.com" || host.endsWith(".jwpltx.com") -> true
        host == "cdn77.org" || host.endsWith(".cdn77.org") -> true
        host.endsWith(".b-cdn.net") || host.contains("videodelivery") || host.contains("cloudflarestream") -> true
        // Common embed/player CDN host shapes (not site allowlists).
        host.contains("jwpcdn") || host.contains("jwplayer") -> true
        // AdGuard / Mullvad DNS endpoints must stay reachable while VPN is on.
        host == "dns.adguard.com" || host == "dns.adguard-dns.com" -> true
        host == "dns-family.adguard.com" || host == "dns-family.adguard-dns.com" -> true
        host.endsWith(".adguard-dns.com") || host.endsWith(".adguard.com") -> true
        host.endsWith(".mullvad.net") || host == "mullvad.net" -> true
        else -> false
    }
}

internal fun matchesLocalList(host: String): Boolean {
    if (isAllowedHost(host)) return false
    // Exact + parent labels (hosts files list registrable / leaf domains).
    var cursor = host
    while (true) {
        if (AdBlockLists.hosts.contains(cursor)) return true
        val dot = cursor.indexOf('.')
        if (dot <= 0 || dot >= cursor.length - 1) break
        cursor = cursor.substring(dot + 1)
    }
    for (suffix in ublockSuffixes) {
        if (host == suffix || host.endsWith(".$suffix")) return true
    }
    return false
}

internal fun isBlockedHost(host: String, mode: String): Boolean {
    val name = host.lowercase()
    if (name.isEmpty()) return false
    if (name == "dns.adguard-dns.com" ||
        name == "dns.adguard.com" ||
        name.endsWith(".adguard-dns.com") ||
        name.endsWith(".mullvad.net")
    ) {
        return false
    }
    if (mode == "off") return false
    return matchesLocalList(name)
}
