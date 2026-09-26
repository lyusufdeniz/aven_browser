package com.avenbrowser.aven_browser


internal fun isAdMediaUrl(url: String): Boolean {
    val lower = url.lowercase()
    val marks = listOf(
        "doubleclick", "googlesyndication", "googleads", "imasdk", "pagead", "adsbygoogle",
        "adservice", "adserver", "adnxs", "adsrvr", "advertising.com", "adsystem",
        "spotx", "teads.", "teads.tv", "exoclick", "exosrv", "popads", "popcash",
        "propellerads", "propellerclick", "juicyads", "hilltopads", "adsterra",
        "trafficjunky", "serving-sys", "adsafeprotected", "moatads", "amazon-adsystem",
        "preroll", "midroll", "postroll", "vmap", "pubmatic", "rubiconproject",
        "openx.net", "casalemedia", "taboola", "outbrain", "criteo",
    )
    if (marks.any { lower.contains(it) }) return true
    if (lower.contains("/ads/") || lower.contains("/ad/")) return true
    if (lower.contains("vast") && (lower.contains("ad") || lower.contains(".xml"))) return true
    return false
}

internal fun isPlayableMedia(url: String): Boolean {
    val lower = url.lowercase()
    if (!lower.startsWith("http://") && !lower.startsWith("https://")) return false
    if (isAdMediaUrl(lower)) return false
    if (lower.contains(".m3u8") || lower.contains(".mpd")) return true
    if (lower.contains("/hls/") || lower.contains("/dash/") ||
        lower.contains("playlist.m3u8") ||
        lower.contains("master.m3u8")
    ) {
        return true
    }
    if (lower.contains("live-video.net") &&
        (lower.contains(".m3u8") ||
            lower.contains("/hls") ||
            lower.contains("playlist") ||
            lower.contains("master"))
    ) {
        return true
    }
    if (lower.contains("/stream/") && lower.contains(".m3u8")) return true
    if (Regex("[?&](type|format|ext|video_format|media)=(m3u8|mpd|mp4|hls|dash|video)").containsMatchIn(lower)) {
        return true
    }
    if (lower.contains("manifest") &&
        (lower.contains("video") || lower.contains("hls") || lower.contains("dash"))
    ) {
        return true
    }
    if (lower.contains("googlevideo.com") && lower.contains("mime=video")) return true
    if (lower.contains("videoplayback") && lower.contains("http")) return true
    if (lower.contains("videodelivery.net") || lower.contains("cloudflarestream.com")) return true
    if (lower.contains("vz-") && lower.contains(".b-cdn.net")) return true
    if ((lower.contains("okcdn") || lower.contains("vkvd") || lower.contains("mycdn.me")) &&
        (lower.contains("video") || lower.contains(".mp4") || lower.contains("hls"))
    ) {
        return true
    }
    if (Regex("[?&](file|source|src|media|mp4|hls|stream)=https?%3a").containsMatchIn(lower)) {
        return true
    }
    val path = lower.substringBefore('?').substringBefore('#')
    return path.endsWith(".mp4") ||
        path.endsWith(".webm") ||
        path.endsWith(".mkv") ||
        path.endsWith(".mov") ||
        path.endsWith(".m4v")
}
