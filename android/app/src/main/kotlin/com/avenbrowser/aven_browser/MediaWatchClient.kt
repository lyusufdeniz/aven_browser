package com.avenbrowser.aven_browser

import android.graphics.Bitmap
import android.net.http.SslError
import android.webkit.ClientCertRequest
import android.webkit.HttpAuthHandler
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient

internal class MediaWatchClient(
    private val inner: WebViewClient,
    private val mode: () -> String,
    private val speed: () -> Boolean,
    private val onMedia: (String) -> Unit,
) : WebViewClient() {
    private val seen = HashSet<String>()
    private val seenLimit = 500
    @Volatile private var pageHost: String? = null

    override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
        seen.clear()
        pageHost = try {
            android.net.Uri.parse(url).host?.lowercase()
        } catch (_: Exception) {
            null
        }
        injectSpeed(view)
        if (mode() != "off") injectCosmetic(view)
        inner.onPageStarted(view, url, favicon)
    }

    override fun onPageFinished(view: WebView, url: String) {
        injectSpeed(view)
        if (mode() != "off") injectCosmetic(view)
        inner.onPageFinished(view, url)
    }

    override fun onLoadResource(view: WebView, url: String) {
        inner.onLoadResource(view, url)
        if (remember(url) && isPlayableMedia(url)) onMedia(url)
    }

    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
        val delegated = inner.shouldInterceptRequest(view, request)
        val requestUrl = request.url?.toString().orEmpty()
        if (requestUrl.isNotEmpty() && isPlayableMedia(requestUrl) && remember(requestUrl)) {
            view.post { onMedia(requestUrl) }
        }
        if (delegated != null || request.isForMainFrame) return delegated
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
        val deferToJs = shouldDeferBlockToJs(request)
        // Puffin-style speed path: always cut trackers/fonts/widgets (even if adblock off).
        if (!firstParty && speed() && isSpeedBlocked(host, path, requestUrl)) {
            // HEAD / no-cors: any synthetic HTTP response = "Accessible" on ad-block tests.
            // JS hook rejects those; native still blocks img/script GET bodies.
            if (deferToJs) return null
            return emptyBlockedResponse()
        }
        val current = mode()
        if (current == "off") return null
        if (firstParty) {
            // Only known same-origin ad scripts (e.g. turtlecute ads.js / pagead.js).
            if (!isBlockedAdScriptPath(path)) return null
            if (deferToJs) return null
            return emptyBlockedResponse()
        }
        // Never stall the network thread (HEAD sleep broke page load/scroll).
        // Host probes are failed via JS fetch hook + AvenAdblock bridge.
        if (isBlockedPath(path) || isBlockedHost(host, current)) {
            if (deferToJs) return null
            return emptyBlockedResponse()
        }
        return null
    }

    private fun remember(url: String): Boolean {
        if (seen.size >= seenLimit && !seen.contains(url)) {
            seen.clear()
        }
        return seen.add(url)
    }

    private fun injectSpeed(view: WebView) {
        if (!speed()) return
        val adblockOn = mode() != "off"
        view.post {
            try {
                view.evaluateJavascript(speedStyleScript, null)
                view.evaluateJavascript(bannerCosmeticScript, null)
                // When adblock is on, networkHookScript already hard-fails both lists.
                if (!adblockOn) {
                    view.evaluateJavascript(speedNetworkHookScript(), null)
                }
            } catch (_: Exception) {
            }
        }
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
        // Emulator / leanback WebView often rejects player CDN certs (jwpcdn, cdn77,
        // dplayer mirrors). Cancel keeps "jwplayer is not defined" and blank video.
        try {
            handler.proceed()
        } catch (_: Exception) {
            try {
                inner.onReceivedSslError(view, handler, error)
            } catch (_: Exception) {
            }
        }
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
