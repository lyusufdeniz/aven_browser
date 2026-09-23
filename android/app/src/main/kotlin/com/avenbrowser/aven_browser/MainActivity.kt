package com.avenbrowser.aven_browser

import android.content.Context
import android.graphics.Bitmap
import android.net.http.SslError
import android.os.Build
import android.os.SystemClock
import java.io.ByteArrayInputStream
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.webkit.ClientCertRequest
import android.webkit.HttpAuthHandler
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var chromeOpen = true
    private var pageTyping = false
    private var adBlockMode = "off"
    private lateinit var channel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AdBlockLists.ensureLoaded(applicationContext)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "tap" -> {
                        tapWebView(floatArg(call, "x"), floatArg(call, "y"))
                        result.success(null)
                    }
                    "lockFocus" -> {
                        setWebViewFocusable(false)
                        result.success(null)
                    }
                    "prepareForInput" -> {
                        setWebViewFocusable(true, requestFocus = false)
                        result.success(null)
                    }
                    "focusForTyping" -> {
                        setWebViewFocusable(true, requestFocus = true)
                        result.success(null)
                    }
                    "webViewVersion" -> result.success(webViewVersion())
                    "refreshSurface" -> {
                        refreshSurface()
                        result.success(null)
                    }
                    "pauseWebView" -> {
                        pauseWebView()
                        result.success(null)
                    }
                    "resumeWebView" -> {
                        resumeWebView()
                        result.success(null)
                    }
                    "setChromeOpen" -> {
                        chromeOpen = call.argument<Boolean>("open") == true
                        result.success(null)
                    }
                    "showKeyboard" -> {
                        showKeyboard()
                        result.success(null)
                    }
                    "setPageTyping" -> {
                        pageTyping = call.argument<Boolean>("typing") == true
                        if (pageTyping) focusWebInput()
                        result.success(null)
                    }
                    "setAdBlock" -> {
                        adBlockMode = call.argument<String>("mode") ?: "off"
                        result.success(null)
                    }
                    "setLoadsImages" -> {
                        val enabled = call.argument<Boolean>("enabled") != false
                        findWebView(window.decorView)?.settings?.loadsImagesAutomatically = enabled
                        findWebView(window.decorView)?.settings?.blockNetworkImage = !enabled
                        result.success(null)
                    }
                    "watchMedia" -> {
                        val root = window.decorView
                        root.post { attachMediaWatch() }
                        root.postDelayed({ attachMediaWatch() }, 500)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (!pageTyping && isCursorKey(event.keyCode)) {
            val flutterView = findFlutterView(window.decorView)
            if (flutterView != null) {
                if (!flutterView.hasFocus()) flutterView.requestFocus()
                return flutterView.dispatchKeyEvent(event)
            }
        }
        if (!pageTyping) return super.dispatchKeyEvent(event)
        val webView = findWebView(window.decorView)
        if (event.keyCode == KeyEvent.KEYCODE_BACK) {
            if (event.action == KeyEvent.ACTION_UP) {
                pageTyping = false
                webView?.clearFocus()
            }
            return true
        }
        if (webView == null) return super.dispatchKeyEvent(event)
        if (!webView.hasFocus()) webView.requestFocus()
        return webView.dispatchKeyEvent(event)
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (!chromeOpen && ev.actionMasked == MotionEvent.ACTION_DOWN) {
            val webView = findWebView(window.decorView)
            if (webView != null && containsScreenPoint(webView, ev.rawX, ev.rawY)) {
                setWebViewFocusable(true, requestFocus = true)
            }
        }
        return super.dispatchTouchEvent(ev)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_SCROLL &&
            event.isFromSource(InputDevice.SOURCE_CLASS_POINTER)
        ) {
            val webView = findWebView(window.decorView)
            if (webView != null && containsScreenPoint(webView, event.rawX, event.rawY)) {
                val location = IntArray(2)
                webView.getLocationOnScreen(location)
                val copy = MotionEvent.obtain(event)
                copy.setLocation(event.rawX - location[0], event.rawY - location[1])
                val handled = webView.onGenericMotionEvent(copy)
                copy.recycle()
                if (handled) return true
            }
        }
        return super.dispatchGenericMotionEvent(event)
    }

    private fun attachMediaWatch() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val webView = findWebView(window.decorView) ?: return
        try {
            webView.setLayerType(View.LAYER_TYPE_HARDWARE, null)
            webView.settings.mediaPlaybackRequiresUserGesture = false
        } catch (_: Exception) {
        }
        val current = webView.webViewClient
        if (current is MediaWatchClient) return
        webView.webViewClient = MediaWatchClient(current, { adBlockMode }) { url ->
            channel.invokeMethod("media", url)
        }
    }

    private fun isCursorKey(code: Int): Boolean {
        return code == KeyEvent.KEYCODE_DPAD_UP ||
            code == KeyEvent.KEYCODE_DPAD_DOWN ||
            code == KeyEvent.KEYCODE_DPAD_LEFT ||
            code == KeyEvent.KEYCODE_DPAD_RIGHT ||
            code == KeyEvent.KEYCODE_DPAD_CENTER ||
            code == KeyEvent.KEYCODE_ENTER ||
            code == KeyEvent.KEYCODE_NUMPAD_ENTER
    }

    private fun focusWebInput() {
        val webView = findWebView(window.decorView) ?: return
        webView.post {
            setWebViewFocusable(true, requestFocus = true)
            val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
            imm.showSoftInput(webView, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    private fun showKeyboard() {
        val flutterView = findFlutterView(window.decorView) ?: return
        flutterView.post {
            flutterView.requestFocus()
            val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
            imm.showSoftInput(flutterView, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    private fun findFlutterView(root: View): View? {
        if (root.javaClass.name.endsWith("FlutterView")) return root
        if (root is ViewGroup) {
            for (index in 0 until root.childCount) {
                val found = findFlutterView(root.getChildAt(index))
                if (found != null) return found
            }
        }
        return null
    }

    private fun refreshSurface() {
        val webView = findWebView(window.decorView) ?: return
        webView.post {
            webView.onResume()
            webView.invalidate()
            webView.requestLayout()
            (webView.parent as? View)?.invalidate()
        }
    }

    private fun pauseWebView() {
        val webView = findWebView(window.decorView) ?: return
        webView.post {
            try {
                webView.onPause()
            } catch (_: Exception) {
            }
        }
    }

    private fun resumeWebView() {
        val webView = findWebView(window.decorView) ?: return
        webView.post {
            try {
                webView.onResume()
            } catch (_: Exception) {
            }
        }
    }

    private fun tapWebView(x: Float, y: Float) {
        val webView = findWebView(window.decorView) ?: return
        val downTime = SystemClock.uptimeMillis()
        val down = MotionEvent.obtain(downTime, downTime, MotionEvent.ACTION_DOWN, x, y, 0)
        val up = MotionEvent.obtain(downTime, downTime + 50, MotionEvent.ACTION_UP, x, y, 0)
        webView.dispatchTouchEvent(down)
        webView.dispatchTouchEvent(up)
        down.recycle()
        up.recycle()
    }

    private fun setWebViewFocusable(focusable: Boolean, requestFocus: Boolean = focusable) {
        val webView = findWebView(window.decorView) ?: return
        webView.isFocusable = focusable
        webView.isFocusableInTouchMode = focusable
        webView.descendantFocusability = if (focusable) {
            ViewGroup.FOCUS_AFTER_DESCENDANTS
        } else {
            ViewGroup.FOCUS_BLOCK_DESCENDANTS
        }
        if (requestFocus) {
            webView.requestFocus()
        }
    }

    private fun containsScreenPoint(view: View, rawX: Float, rawY: Float): Boolean {
        val location = IntArray(2)
        view.getLocationOnScreen(location)
        return rawX >= location[0] &&
            rawY >= location[1] &&
            rawX < location[0] + view.width &&
            rawY < location[1] + view.height
    }

    private fun findWebView(view: View): WebView? {
        if (view is WebView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                val found = findWebView(view.getChildAt(index))
                if (found != null) return found
            }
        }
        return null
    }

    private fun webViewVersion(): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return WebView.getCurrentWebViewPackage()?.versionName
        }
        val names = listOf(
            "com.google.android.webview",
            "com.android.webview",
            "com.android.chrome",
        )
        for (name in names) {
            try {
                @Suppress("DEPRECATION")
                return packageManager.getPackageInfo(name, 0).versionName
            } catch (_: Exception) {
            }
        }
        return null
    }

    private fun floatArg(call: MethodCall, name: String): Float {
        return when (val value = call.argument<Any>(name)) {
            is Double -> value.toFloat()
            is Float -> value
            is Int -> value.toFloat()
            is Long -> value.toFloat()
            else -> 0f
        }
    }

    companion object {
        private const val channelName = "com.avenbrowser/input"
    }
}

private class MediaWatchClient(
    private val inner: WebViewClient,
    private val mode: () -> String,
    private val onMedia: (String) -> Unit,
) : WebViewClient() {
    private val seen = HashSet<String>()
    @Volatile private var pageHost: String? = null

    override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
        seen.clear()
        pageHost = try {
            android.net.Uri.parse(url).host?.lowercase()
        } catch (_: Exception) {
            null
        }
        if (mode() != "off") injectCosmetic(view)
        inner.onPageStarted(view, url, favicon)
    }

    override fun onPageFinished(view: WebView, url: String) {
        if (mode() != "off") injectCosmetic(view)
        inner.onPageFinished(view, url)
    }

    override fun onLoadResource(view: WebView, url: String) {
        inner.onLoadResource(view, url)
        if (seen.add(url) && isPlayableMedia(url)) onMedia(url)
    }

    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
        val delegated = inner.shouldInterceptRequest(view, request)
        val requestUrl = request.url?.toString().orEmpty()
        if (requestUrl.isNotEmpty() && isPlayableMedia(requestUrl) && seen.add(requestUrl)) {
            view.post { onMedia(requestUrl) }
        }
        if (delegated != null || request.isForMainFrame) return delegated
        val current = mode()
        if (current == "off") return null
        val host = request.url.host?.lowercase() ?: return null
        val path = (request.url.path ?: "").lowercase()
        if (isPlayableMedia(requestUrl) ||
            path.endsWith(".m3u8") ||
            path.endsWith(".mp4") ||
            path.endsWith(".webm") ||
            path.endsWith(".mpd") ||
            path.endsWith(".ts")
        ) {
            return null
        }
        val origin = pageHost
        val firstParty = origin != null && (host == origin || host.endsWith(".$origin"))
        if (firstParty) {
            // Only known same-origin ad scripts (e.g. turtlecute ads.js / pagead.js).
            if (!isBlockedAdScriptPath(path)) return null
            return emptyBlockedResponse()
        }
        // Never stall the network thread (HEAD sleep broke page load/scroll).
        // Host probes are failed via JS fetch hook instead.
        if (isBlockedPath(path) || isBlockedHost(host, current)) {
            return emptyBlockedResponse()
        }
        return null
    }

    private fun injectCosmetic(view: WebView) {
        view.post {
            try {
                view.evaluateJavascript(cosmeticScript, null)
                view.evaluateJavascript(networkHookScript(), null)
            } catch (_: Exception) {
            }
        }
    }

    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
        return inner.shouldOverrideUrlLoading(view, request)
    }

    override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) {
        inner.doUpdateVisitedHistory(view, url, isReload)
    }

    override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
        inner.onReceivedError(view, request, error)
    }

    override fun onReceivedHttpError(
        view: WebView,
        request: WebResourceRequest,
        errorResponse: WebResourceResponse,
    ) {
        inner.onReceivedHttpError(view, request, errorResponse)
    }

    override fun onReceivedHttpAuthRequest(
        view: WebView,
        handler: HttpAuthHandler,
        host: String,
        realm: String,
    ) {
        inner.onReceivedHttpAuthRequest(view, handler, host, realm)
    }

    override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
        inner.onReceivedSslError(view, handler, error)
    }

    override fun onReceivedClientCertRequest(view: WebView, request: ClientCertRequest) {
        inner.onReceivedClientCertRequest(view, request)
    }

    override fun onPageCommitVisible(view: WebView, url: String) {
        inner.onPageCommitVisible(view, url)
    }

    override fun onScaleChanged(view: WebView, oldScale: Float, newScale: Float) {
        inner.onScaleChanged(view, oldScale, newScale)
    }
}

private object AdBlockLists {
    @Volatile
    var hosts: Set<String> = emptySet()
        private set

    fun ensureLoaded(context: Context) {
        if (hosts.isNotEmpty()) return
        synchronized(this) {
            if (hosts.isNotEmpty()) return
            hosts = try {
                context.assets.open("adblock_hosts.txt").bufferedReader().useLines { lines ->
                    lines.map { it.trim().lowercase() }
                        .filter { it.isNotEmpty() && !it.startsWith("#") && !isAllowedHost(it) }
                        .toSet()
                }
            } catch (_: Exception) {
                emptySet()
            }
        }
    }
}

private val ublockSuffixes = listOf(
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
    "exoclick.com",
    "adform.net",
    "serving-sys.com",
    "adsafeprotected.com",
    "2mdn.net",
    "imasdk.googleapis.com",
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
)

private val blockedPathMarkers = listOf(
    "/pagead/",
    "/pagead2.",
    "/doubleclick/",
    "/googlesyndication/",
    "/adsbygoogle",
    "/js/widget/ads",
    "/js/pagead",
)

// CSS only — no MutationObserver (that froze scroll).
private val cosmeticScript = """
(function(){
  if (document.getElementById('aven-adblock-style')) return;
  var s = document.createElement('style');
  s.id = 'aven-adblock-style';
  s.textContent = '#cts_test,#ad_ctd,.adsbox,.textads,.banner_ads,.banner-ads,.adbox,.ADBox,.AdBox,.adbox-wrapper,.adSocial,.ad-unit,.afs_ads,.ad-zone,.ad-space,[id^="google_ads_"],[id^="div-gpt-ad"],[class*="adsbygoogle"],iframe[id^="google_ads_iframe"],iframe[src*="doubleclick.net"],iframe[src*="googlesyndication.com"]{display:none!important;visibility:hidden!important;height:0!important;max-height:0!important;overflow:hidden!important;opacity:0!important;pointer-events:none!important}';
  (document.head || document.documentElement).appendChild(s);
})();
""".trimIndent()

private fun networkHookScript(): String {
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

private fun emptyBlockedResponse(): WebResourceResponse {
    return WebResourceResponse(
        "text/plain",
        "utf-8",
        403,
        "Blocked",
        emptyMap(),
        ByteArrayInputStream(ByteArray(0)),
    )
}

private fun isBlockedAdScriptPath(path: String): Boolean {
    return path.endsWith("/ads.js") ||
        path.endsWith("/pagead.js") ||
        path.endsWith("/js/widget/ads.js") ||
        path.endsWith("/js/pagead.js") ||
        path.contains("/js/widget/ads") ||
        path.contains("/js/pagead")
}

private fun isBlockedPath(path: String): Boolean {
    if (path.isEmpty()) return false
    if (isBlockedAdScriptPath(path)) return true
    return blockedPathMarkers.any { path.contains(it) }
}

private fun isAllowedHost(host: String): Boolean {
    // Narrow allowlist — do NOT blanket-allow *.google.com (drops analytics.google.com etc.).
    return when {
        host == "googletagmanager.com" || host.endsWith(".googletagmanager.com") -> true
        host == "www.gstatic.com" || host == "gstatic.com" || host.endsWith(".gstatic.com") -> true
        host == "fonts.googleapis.com" || host == "fonts.gstatic.com" -> true
        host == "www.google.com" || host == "google.com" || host == "accounts.google.com" -> true
        host.endsWith(".ytimg.com") || host.endsWith(".ggpht.com") -> true
        host.endsWith(".jsdelivr.net") || host.endsWith(".jquery.com") -> true
        else -> false
    }
}

private fun matchesLocalList(host: String): Boolean {
    if (isAllowedHost(host)) return false
    if (AdBlockLists.hosts.contains(host)) return true
    for (suffix in ublockSuffixes) {
        if (host == suffix || host.endsWith(".$suffix")) return true
    }
    return false
}

private fun isBlockedHost(host: String, mode: String): Boolean {
    val name = host.lowercase()
    if (name.isEmpty() || name == "dns.adguard-dns.com") return false
    if (mode == "off") return false
    return matchesLocalList(name)
}

private fun isPlayableMedia(url: String): Boolean {
    val lower = url.lowercase()
    if (!lower.startsWith("http://") && !lower.startsWith("https://")) return false
    if (lower.contains("doubleclick") ||
        lower.contains("googlesyndication") ||
        lower.contains("googleads") ||
        lower.contains("imasdk") ||
        lower.contains("/ads/") ||
        lower.contains("adserver") ||
        lower.contains("preroll") ||
        lower.contains("vast") && lower.contains("ad")
    ) {
        return false
    }
    if (lower.contains(".m3u8") || lower.contains(".mpd")) return true
    if (lower.contains("/hls/") || lower.contains("playlist.m3u8") || lower.contains("master.m3u8")) return true
    if (Regex("[?&](type|format|ext)=(m3u8|mpd|mp4|hls)").containsMatchIn(lower)) return true
    if (lower.contains("googlevideo.com") && lower.contains("mime=video")) return true
    val path = lower.substringBefore('?').substringBefore('#')
    return path.endsWith(".mp4") ||
        path.endsWith(".webm") ||
        path.endsWith(".mkv") ||
        path.endsWith(".mov")
}
