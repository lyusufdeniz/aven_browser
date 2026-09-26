package com.avenbrowser.aven_browser

import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var chromeOpen = true
    private var pageTyping = false
    private var adBlockMode = "off"
    @Volatile private var speedMode = true
    private lateinit var channel: MethodChannel
    private var pendingAdBlockMode: String? = null
    private var pendingAdBlockResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AdBlockLists.ensureLoaded(applicationContext)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "tap" -> {
                        val screen = call.argument<Boolean>("screen") == true
                        if (screen) {
                            tapFlutterView(floatArg(call, "x"), floatArg(call, "y"))
                        } else {
                            tapWebView(floatArg(call, "x"), floatArg(call, "y"))
                        }
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
                        val connectDns = call.argument<Boolean>("connectDns") == true
                        applyAdBlockDns(adBlockMode, connectDns, result)
                    }
                    "setSpeedMode" -> {
                        speedMode = call.argument<Boolean>("enabled") != false
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
        tuneWebViewForTv(webView)
        try {
            AdBlockLists.ensureLoaded(applicationContext)
            webView.removeJavascriptInterface("AvenAdblock")
            webView.addJavascriptInterface(AdBlockJsBridge { adBlockMode }, "AvenAdblock")
        } catch (_: Exception) {
        }
        val current = webView.webViewClient
        if (current is MediaWatchClient) return
        webView.webViewClient = MediaWatchClient(
            current,
            { adBlockMode },
            { speedMode },
        ) { url ->
            channel.invokeMethod("media", url)
        }
    }

    /**
     * Engine-level TV tuning (Puffin / BrowserHere style) — not site CSS.
     * Faster paint, less background work, disk cache, no force-dark double pass.
     */
    private fun tuneWebViewForTv(webView: WebView) {
        WebViewEngine.installEarly(applicationContext)
        try {
            webView.setLayerType(View.LAYER_TYPE_HARDWARE, null)
            try {
                WebView::class.java
                    .getMethod("setOffscreenPreRaster", Boolean::class.javaPrimitiveType)
                    .invoke(webView, true)
            } catch (_: Exception) {
            }
            webView.overScrollMode = View.OVER_SCROLL_NEVER
            webView.isVerticalScrollBarEnabled = false
            webView.isHorizontalScrollBarEnabled = false
            WebViewEngine.setActivePriority(webView, active = true)
        } catch (_: Exception) {
        }
        try {
            val s = webView.settings
            WebViewEngine.tuneSettings(s)
            // Avoid algorithmic darkening re-tint cost on leanback.
            if (WebViewFeature.isFeatureSupported(WebViewFeature.ALGORITHMIC_DARKENING)) {
                WebSettingsCompat.setAlgorithmicDarkeningAllowed(s, false)
            } else if (WebViewFeature.isFeatureSupported(WebViewFeature.FORCE_DARK)) {
                @Suppress("DEPRECATION")
                WebSettingsCompat.setForceDark(s, WebSettingsCompat.FORCE_DARK_OFF)
            }
        } catch (_: Exception) {
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
                webView.evaluateJavascript(
                    """
                    (function(){
                      window.__avenWantPlay = false;
                      function kill(v){
                        try {
                          v.pause();
                          v.muted = true;
                          v.preload = 'none';
                          try { v.removeAttribute('src'); v.load(); } catch(e) {}
                        } catch(e) {}
                      }
                      try { document.querySelectorAll('video,audio').forEach(kill); } catch(e) {}
                      try {
                        document.querySelectorAll('iframe').forEach(function(f){
                          try {
                            var d = f.contentDocument || (f.contentWindow && f.contentWindow.document);
                            if (d) d.querySelectorAll('video,audio').forEach(kill);
                          } catch(e) {}
                        });
                      } catch(e) {}
                    })();
                    """.trimIndent(),
                    null,
                )
            } catch (_: Exception) {
            }
            try {
                WebViewEngine.setActivePriority(webView, active = false)
            } catch (_: Exception) {
            }
            try {
                // Drop GPU layer while ExoPlayer owns the screen.
                webView.setLayerType(View.LAYER_TYPE_NONE, null)
            } catch (_: Exception) {
            }
            try {
                webView.onPause()
            } catch (_: Exception) {
            }
            try {
                webView.pauseTimers()
            } catch (_: Exception) {
            }
            try {
                webView.visibility = View.INVISIBLE
            } catch (_: Exception) {
            }
        }
    }

    private fun resumeWebView() {
        val webView = findWebView(window.decorView) ?: return
        webView.post {
            try {
                webView.visibility = View.VISIBLE
            } catch (_: Exception) {
            }
            try {
                webView.setLayerType(View.LAYER_TYPE_HARDWARE, null)
            } catch (_: Exception) {
            }
            try {
                WebViewEngine.setActivePriority(webView, active = true)
            } catch (_: Exception) {
            }
            try {
                webView.resumeTimers()
            } catch (_: Exception) {
            }
            try {
                webView.onResume()
            } catch (_: Exception) {
            }
        }
    }

    private fun tapWebView(x: Float, y: Float) {
        val webView = findWebView(window.decorView) ?: return
        dispatchTap(webView, x, y)
    }

    private fun tapFlutterView(x: Float, y: Float) {
        val flutterView = findFlutterView(window.decorView) ?: window.decorView
        // Hybrid-composition custom views sit under FlutterView; prefer the
        // deepest visible child under the point so fullscreen controls get the tap.
        val target = findViewUnder(flutterView, x, y) ?: flutterView
        val location = IntArray(2)
        target.getLocationInWindow(location)
        val flutterLoc = IntArray(2)
        flutterView.getLocationInWindow(flutterLoc)
        val localX = x + flutterLoc[0] - location[0]
        val localY = y + flutterLoc[1] - location[1]
        dispatchTap(target, localX, localY)
    }

    private fun findViewUnder(root: View, x: Float, y: Float): View? {
        if (root !is ViewGroup) return null
        val rootLoc = IntArray(2)
        root.getLocationInWindow(rootLoc)
        val screenX = x + rootLoc[0]
        val screenY = y + rootLoc[1]
        var best: View? = null
        var bestArea = Long.MAX_VALUE
        fun walk(view: View) {
            if (view.visibility != View.VISIBLE) return
            val loc = IntArray(2)
            view.getLocationInWindow(loc)
            val left = loc[0].toFloat()
            val top = loc[1].toFloat()
            val right = left + view.width
            val bottom = top + view.height
            if (screenX < left || screenX >= right || screenY < top || screenY >= bottom) {
                return
            }
            val name = view.javaClass.name
            val isWeb = name.endsWith("WebView") || name.contains("WebView")
            val isFlutter = name.endsWith("FlutterView") || name.endsWith("FlutterSurfaceView") ||
                name.endsWith("FlutterTextureView")
            if (!isWeb && !isFlutter && view.width > 0 && view.height > 0) {
                val area = view.width.toLong() * view.height.toLong()
                if (area < bestArea) {
                    bestArea = area
                    best = view
                }
            }
            if (view is ViewGroup) {
                for (i in 0 until view.childCount) walk(view.getChildAt(i))
            }
        }
        walk(root)
        return best
    }

    private fun dispatchTap(target: View, x: Float, y: Float) {
        val downTime = SystemClock.uptimeMillis()
        val down = MotionEvent.obtain(downTime, downTime, MotionEvent.ACTION_DOWN, x, y, 0)
        val up = MotionEvent.obtain(downTime, downTime + 50, MotionEvent.ACTION_UP, x, y, 0)
        target.dispatchTouchEvent(down)
        target.dispatchTouchEvent(up)
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

    private fun applyAdBlockDns(mode: String, connectDns: Boolean, result: MethodChannel.Result) {
        if (mode == "off") {
            try {
                AdBlockDnsVpnService.stop(this)
            } catch (_: Exception) {
            }
            result.success(mapOf("dns" to false, "mode" to mode))
            return
        }
        // Boot / sync: apply local host intercept only — do not prompt for VPN.
        if (!connectDns) {
            result.success(mapOf("dns" to false, "mode" to mode))
            return
        }
        val prepare = AdBlockDnsVpnService.prepareIntent(this)
        if (prepare != null) {
            pendingAdBlockMode = mode
            pendingAdBlockResult = result
            @Suppress("DEPRECATION")
            startActivityForResult(prepare, REQ_VPN)
            return
        }
        AdBlockDnsVpnService.start(this, mode)
        result.success(mapOf("dns" to true, "mode" to mode))
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_VPN) return
        val mode = pendingAdBlockMode
        val pending = pendingAdBlockResult
        pendingAdBlockMode = null
        pendingAdBlockResult = null
        if (mode == null || pending == null) return
        if (resultCode == RESULT_OK) {
            AdBlockDnsVpnService.start(this, mode)
            pending.success(mapOf("dns" to true, "mode" to mode))
        } else {
            // Permission denied: local host list + cosmetics still work.
            pending.success(mapOf("dns" to false, "mode" to mode, "vpnDenied" to true))
        }
    }

    companion object {
        private const val channelName = "com.avenbrowser/input"
        private const val REQ_VPN = 7711
    }
}

