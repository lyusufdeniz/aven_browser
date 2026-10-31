package dev.furina.avenbrowser

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.provider.Settings
import android.view.autofill.AutofillManager
import android.webkit.WebView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * Page tools for the WebView: find in page, tab previews, certificate info,
 * share, the long-press menu, autofill status and the Android permissions a
 * page needs. All calls run on the main thread.
 */
internal object WebPageTools {
    const val permissionCode = 4110

    private val main = Handler(Looper.getMainLooper())
    private var findQuery: String? = null
    private var pendingFind: MethodChannel.Result? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var pendingAsked: List<String> = emptyList()
    private var attached: WebView? = null

    /** Hooks the long-press menu and find results onto [webView] once. */
    fun attach(webView: WebView, channel: MethodChannel) {
        if (attached === webView) return
        attached = webView
        findQuery = null
        webView.setFindListener { active, total, done ->
            if (!done) return@setFindListener
            val result = pendingFind ?: return@setFindListener
            pendingFind = null
            result.success(mapOf("current" to if (total > 0) active + 1 else 0, "total" to total))
        }
        if (BuildConfig.FLAVOR == "tv") return
        webView.setOnLongClickListener {
            val hit = webView.hitTestResult
            when (hit.type) {
                WebView.HitTestResult.SRC_ANCHOR_TYPE -> {
                    sendMenu(channel, link = hit.extra.orEmpty(), src = "", title = "")
                    true
                }
                WebView.HitTestResult.IMAGE_TYPE -> {
                    sendMenu(channel, link = "", src = hit.extra.orEmpty(), title = "")
                    true
                }
                WebView.HitTestResult.SRC_IMAGE_ANCHOR_TYPE -> {
                    // The hit only carries the image; ask the page for the link around it.
                    val src = hit.extra.orEmpty()
                    val reply = Handler(Looper.getMainLooper()) { message ->
                        val data = message.data
                        sendMenu(
                            channel,
                            link = data.getString("url").orEmpty(),
                            src = data.getString("src") ?: src,
                            title = data.getString("title").orEmpty(),
                        )
                        true
                    }
                    webView.requestFocusNodeHref(Message.obtain(reply))
                    true
                }
                // Text and empty space keep the normal selection behaviour.
                else -> false
            }
        }
    }

    private fun sendMenu(channel: MethodChannel, link: String, src: String, title: String) {
        if (link.isEmpty() && src.isEmpty()) return
        channel.invokeMethod(
            "contextMenu",
            mapOf("link" to link, "src" to src, "title" to title, "alt" to ""),
        )
    }

    fun find(webView: WebView, query: String, forward: Boolean, result: MethodChannel.Result) {
        pendingFind?.success(mapOf("current" to 0, "total" to 0))
        pendingFind = null
        if (query.isEmpty()) {
            clearFind(webView)
            result.success(mapOf("current" to 0, "total" to 0))
            return
        }
        pendingFind = result
        if (query != findQuery) {
            findQuery = query
            webView.findAllAsync(query)
        } else {
            webView.findNext(forward)
        }
        // A page that never reports back must not leave Flutter waiting.
        main.postDelayed({
            if (pendingFind === result) {
                pendingFind = null
                result.success(mapOf("current" to 0, "total" to 0))
            }
        }, 1500)
    }

    fun clearFind(webView: WebView) {
        findQuery = null
        webView.clearMatches()
    }

    /** Small JPEG of what the page shows, for the tab grid. */
    fun preview(webView: WebView): ByteArray? {
        val width = webView.width
        val height = webView.height
        if (width <= 0 || height <= 0) return null
        val scale = 0.35f
        return try {
            val bitmap = Bitmap.createBitmap(
                (width * scale).toInt().coerceAtLeast(1),
                (height * scale).toInt().coerceAtLeast(1),
                Bitmap.Config.RGB_565,
            )
            val canvas = Canvas(bitmap)
            canvas.scale(scale, scale)
            canvas.translate(-webView.scrollX.toFloat(), -webView.scrollY.toFloat())
            webView.draw(canvas)
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 70, out)
            bitmap.recycle()
            out.toByteArray()
        } catch (_: Throwable) {
            null
        }
    }

    /** Same keys the security sheet already reads. */
    fun security(webView: WebView): Map<String, String> {
        val url = webView.url.orEmpty()
        val uri = Uri.parse(url)
        val cert = webView.certificate
        val mode = when {
            uri.scheme == "https" && cert != null -> "secure"
            uri.scheme == "https" -> "warning"
            uri.scheme == "http" -> "insecure"
            else -> "unknown"
        }
        val format = SimpleDateFormat("d MMM yyyy", Locale.getDefault())
        return mapOf(
            "mode" to mode,
            "host" to (uri.host?.lowercase() ?: ""),
            "origin" to (if (uri.host != null) "${uri.scheme}://${uri.host}" else ""),
            "subject" to (cert?.issuedTo?.dName ?: ""),
            "issuer" to (cert?.issuedBy?.dName ?: ""),
            "validFrom" to (cert?.validNotBeforeDate?.let { format.format(it) } ?: ""),
            "validTo" to (cert?.validNotAfterDate?.let { format.format(it) } ?: ""),
        )
    }

    fun share(activity: Activity, text: String) {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        try {
            activity.startActivity(Intent.createChooser(send, null))
        } catch (_: Throwable) {
        }
    }

    /** "on" when an autofill service is set, "off" when not, "unsupported" before Android 8. */
    fun autofillStatus(activity: Activity): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return "unsupported"
        val manager = activity.getSystemService(AutofillManager::class.java) ?: return "unsupported"
        if (!manager.isAutofillSupported) return "unsupported"
        return if (manager.hasEnabledAutofillServices()) "on" else "off"
    }

    fun openAutofillSettings(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val intent = Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE).apply {
            data = Uri.parse("package:${activity.packageName}")
        }
        try {
            activity.startActivity(intent)
        } catch (_: Throwable) {
        }
    }

    /**
     * Makes sure Aven itself holds the Android permissions behind a page request
     * ("camera", "microphone", "location"); answers true once all are granted.
     */
    fun ensurePermissions(activity: Activity, kinds: List<String>, result: MethodChannel.Result) {
        val wanted = kinds.flatMap {
            when (it) {
                "camera" -> listOf(Manifest.permission.CAMERA)
                "microphone" -> listOf(Manifest.permission.RECORD_AUDIO)
                "location" -> listOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                )
                else -> emptyList()
            }
        }.distinct()
        val missing = wanted.filter {
            ContextCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        pendingAsked = missing
        ActivityCompat.requestPermissions(activity, missing.toTypedArray(), permissionCode)
    }

    fun onPermissionResult(grantResults: IntArray) {
        val result = pendingPermission ?: return
        pendingPermission = null
        val granted = pendingAsked.filterIndexed { index, _ ->
            grantResults.getOrNull(index) == PackageManager.PERMISSION_GRANTED
        }.toSet()
        // Camera and microphone must be granted; for location coarse alone is enough.
        val ok = pendingAsked.all { permission ->
            when (permission) {
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION ->
                    Manifest.permission.ACCESS_FINE_LOCATION in granted ||
                        Manifest.permission.ACCESS_COARSE_LOCATION in granted
                else -> permission in granted
            }
        }
        result.success(ok)
    }
}
