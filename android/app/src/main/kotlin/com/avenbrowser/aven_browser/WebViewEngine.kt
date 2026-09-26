package com.avenbrowser.aven_browser

import android.content.Context
import android.os.Build
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import java.io.ByteArrayInputStream
import java.net.InetAddress
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Engine-level WebView speedups (not site CSS): Chromium flags, disk cache,
 * instant tracker stubs, DNS warm, renderer priority while native player runs.
 */
internal object WebViewEngine {
    private val flagsInstalled = AtomicBoolean(false)
    private val dnsPool = Executors.newSingleThreadExecutor { r ->
        Thread(r, "aven-dns-warm").apply { isDaemon = true }
    }
    private val warmedHosts = LinkedHashSet<String>()

    /** Must run before the first WebView is constructed. */
    fun installEarly(context: Context) {
        if (!flagsInstalled.compareAndSet(false, true)) return
        // Grow Chromium HTTP disk cache + prefer GPU raster on TV SoCs.
        applyCommandLine(
            arrayOf(
                "chromium",
                "--disk-cache-size=268435456",
                "--enable-gpu-rasterization",
                "--enable-zero-copy",
                "--enable-native-gpu-memory-buffers",
                "--canvas-oop-rasterization",
                "--num-raster-threads=4",
                "--enable-checker-imaging",
                "--disable-low-end-device-mode",
                "--disable-features=TranslateUI,InterestFeedContentSuggestions," +
                    "HeavyAdIntervention,BackForwardCache,AutofillServerCommunication," +
                    "MediaRouter,OfflinePagesPrefetching",
                "--enable-features=CanvasOopRasterization,WebRTC-H264WithOpenH264FFmpeg",
            ),
        )
        // Touch cache dir so WebView creates it under our process early.
        try {
            context.cacheDir.mkdirs()
            context.getDir("webview_chromium", Context.MODE_PRIVATE).mkdirs()
        } catch (_: Exception) {
        }
    }

    private fun applyCommandLine(args: Array<String>) {
        val classNames = listOf(
            "org.chromium.base.CommandLine",
            "com.android.webview.chromium.CommandLine",
        )
        for (name in classNames) {
            try {
                val clazz = Class.forName(name)
                val initialized = try {
                    clazz.getMethod("isInitialized").invoke(null) as? Boolean ?: false
                } catch (_: Exception) {
                    false
                }
                if (!initialized) {
                    clazz.getMethod("init", Array<String>::class.java).invoke(null, args)
                } else {
                    val get = clazz.getMethod("getInstance").invoke(null)
                    val append = get.javaClass.getMethod("appendSwitchWithValue", String::class.java, String::class.java)
                    // disk-cache-size is a switch with value
                    append.invoke(get, "disk-cache-size", "268435456")
                }
                return
            } catch (_: Exception) {
            }
        }
        // Fallback: append via WebView factory init extras (best-effort).
        try {
            val clazz = Class.forName("android.webkit.WebViewFactory")
            // no-op if missing — flags still help when CommandLine works
            clazz.getDeclaredMethod("getProvider").also { it.isAccessible = true }
        } catch (_: Exception) {
        }
    }

    fun warmDns(host: String?) {
        val name = host?.lowercase()?.trim().orEmpty()
        if (name.isEmpty() || name == "localhost") return
        synchronized(warmedHosts) {
            if (!warmedHosts.add(name)) return
            if (warmedHosts.size > 64) {
                val first = warmedHosts.iterator().next()
                warmedHosts.remove(first)
            }
        }
        dnsPool.execute {
            try {
                InetAddress.getAllByName(name)
            } catch (_: Exception) {
            }
        }
    }

    fun tuneSettings(settings: WebSettings) {
        settings.cacheMode = WebSettings.LOAD_DEFAULT
        settings.domStorageEnabled = true
        @Suppress("DEPRECATION")
        try {
            settings.databaseEnabled = true
        } catch (_: Exception) {
        }
        settings.javaScriptCanOpenWindowsAutomatically = false
        settings.setSupportMultipleWindows(false)
        settings.mediaPlaybackRequiresUserGesture = false
        settings.loadsImagesAutomatically = true
        settings.blockNetworkImage = false
        settings.builtInZoomControls = false
        settings.displayZoomControls = false
        settings.setSupportZoom(false)
        settings.loadWithOverviewMode = true
        settings.useWideViewPort = true
        settings.allowFileAccess = false
        settings.allowContentAccess = false
        settings.setGeolocationEnabled(false)
        @Suppress("DEPRECATION")
        try {
            settings.saveFormData = false
        } catch (_: Exception) {
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            settings.safeBrowsingEnabled = false
        }
        // Deprecated but still honored on many TV WebView builds — bumps compositor.
        try {
            @Suppress("DEPRECATION")
            settings.setRenderPriority(WebSettings.RenderPriority.HIGH)
        } catch (_: Exception) {
        }
    }

    fun setActivePriority(webView: WebView, active: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            if (active) {
                webView.setRendererPriorityPolicy(WebView.RENDERER_PRIORITY_IMPORTANT, false)
            } else {
                // Waive renderer so ExoPlayer / Flutter get CPU+GPU while video plays.
                webView.setRendererPriorityPolicy(WebView.RENDERER_PRIORITY_WAIVED, true)
            }
        } catch (_: Exception) {
        }
    }

    /**
     * Instant local stub (AssetLoader-style) so blocked tracker/font requests
     * never hit the network and can be cached by Chromium.
     */
    fun stubResponse(url: String, path: String): WebResourceResponse {
        val lowerPath = path.lowercase()
        val lowerUrl = url.lowercase()
        val mime = when {
            lowerPath.endsWith(".js") || lowerUrl.contains(".js?") ||
                lowerPath.endsWith(".mjs") -> "application/javascript"
            lowerPath.endsWith(".css") || lowerUrl.contains(".css?") -> "text/css"
            lowerPath.endsWith(".woff2") -> "font/woff2"
            lowerPath.endsWith(".woff") -> "font/woff"
            lowerPath.endsWith(".ttf") || lowerPath.endsWith(".otf") -> "font/ttf"
            lowerPath.endsWith(".svg") -> "image/svg+xml"
            lowerPath.endsWith(".png") || lowerUrl.contains("format=png") -> "image/png"
            lowerPath.endsWith(".jpg") || lowerPath.endsWith(".jpeg") ||
                lowerPath.endsWith(".webp") || lowerPath.endsWith(".ico") ||
                lowerPath.endsWith(".gif") -> "image/gif"
            lowerPath.endsWith(".json") -> "application/json"
            lowerPath.endsWith(".xml") -> "application/xml"
            else -> "text/plain"
        }
        val body = when (mime) {
            "application/javascript" -> JS_STUB
            "text/css" -> CSS_STUB
            "application/json" -> JSON_STUB
            "image/svg+xml" -> SVG_1X1
            "image/gif", "image/png" -> GIF_1X1
            else -> EMPTY
        }
        val headers = mapOf(
            "Access-Control-Allow-Origin" to "*",
            "Cache-Control" to "public, max-age=31536000, immutable",
            "Cross-Origin-Resource-Policy" to "cross-origin",
        )
        return WebResourceResponse(
            mime,
            "utf-8",
            200,
            "OK",
            headers,
            ByteArrayInputStream(body),
        )
    }

    private val EMPTY = ByteArray(0)
    private val JS_STUB = ";\n".toByteArray(Charsets.UTF_8)
    private val CSS_STUB = ByteArray(0)
    private val JSON_STUB = "{}\n".toByteArray(Charsets.UTF_8)
    private val SVG_1X1 =
        """<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>"""
            .toByteArray(Charsets.UTF_8)

    /** Transparent 1×1 GIF — pages that expect an image onload keep going. */
    private val GIF_1X1 = byteArrayOf(
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00,
        0x80.toByte(), 0x00, 0x00, 0x00, 0x00, 0x00, 0xff.toByte(), 0xff.toByte(), 0xff.toByte(),
        0x21, 0xf9.toByte(), 0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x01, 0x44, 0x00, 0x3b,
    )
}
