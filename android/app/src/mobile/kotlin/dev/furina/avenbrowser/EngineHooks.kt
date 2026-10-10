package dev.furina.avenbrowser

import android.app.Activity
import android.app.Application
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.MotionEvent
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.view.autofill.AutofillManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONArray
import org.json.JSONObject
import org.mozilla.geckoview.AllowOrDeny
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoRuntime
import org.mozilla.geckoview.GeckoRuntimeSettings
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoSession.PermissionDelegate
import org.mozilla.geckoview.GeckoSessionSettings
import org.mozilla.geckoview.GeckoView
import org.mozilla.geckoview.WebExtension
import org.mozilla.geckoview.WebRequestError
import org.mozilla.geckoview.WebResponse
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.concurrent.atomic.AtomicInteger

internal object EngineHooks {
    fun installEarly(app: Application) {
        GeckoBrowser.installEarly(app)
    }

    fun install(engine: FlutterEngine, activity: Activity) {
        GeckoBrowser.install(engine, activity)
    }

    fun engineVersion(): String = "Gecko/152.0"

    fun pausePage(): Boolean {
        GeckoBrowser.setActive(false)
        return true
    }

    fun resumePage(): Boolean {
        GeckoBrowser.setActive(true)
        return true
    }

    fun tapPage(x: Float, y: Float): Boolean {
        GeckoBrowser.tap(x, y)
        return true
    }

    fun scrollPage(x: Float, y: Float, dx: Float, dy: Float): Boolean {
        GeckoBrowser.scroll(x, y, dx, dy)
        return true
    }

    fun onRuntimePermissionResult(grantResults: IntArray) {
        GeckoBrowser.onRuntimePermissionResult(grantResults)
    }
}

/**
 * One Gecko session for the phone flavor. The Flutter shell talks to it
 * through a method channel; page scripts go through a built-in extension
 * because current GeckoView has no evaluateJS.
 */
internal object GeckoBrowser {
    private const val tag = "AvenGecko"
    private const val permissionRequestCode = 4101
    private const val channelName = "dev.furina.avenbrowser/gecko"
    private const val viewType = "aven/gecko"
    private const val extensionUri = "resource://android/assets/aven_ext/"
    private const val extensionId = "aven@furina.dev"
    private const val nativeApp = "aven"

    private val main = Handler(Looper.getMainLooper())
    private val ids = AtomicInteger()
    private val pendingEval = HashMap<Int, MethodChannel.Result>()
    private val evalQueue = ArrayList<JSONObject>()

    private var app: Application? = null
    private var hostActivity: Activity? = null
    private var pendingAndroidPerm: PermissionDelegate.Callback? = null
    private var security = HashMap<String, String>()
    private var runtime: GeckoRuntime? = null
    private var session: GeckoSession? = null
    private var privateSession: GeckoSession? = null
    private var privateMode = false
    private var wantPrivate = false
    private var port: WebExtension.Port? = null
    private var channel: MethodChannel? = null
    private var view: GeckoView? = null
    private var extensionReady = false
    private var requireMediaGesture = false
    private var canGoBack = false
    private var canGoForward = false
    private var title: String? = null
    private var url: String? = null
    private var userAgent: String? = null
    private var textZoom = 100
    private var downloadWatch: Runnable? = null
    private var starting = false
    private var pendingView: GeckoView? = null

    fun installEarly(app: Application) {
        this.app = app
    }

    /** Gecko stays down until a page is opened. Starting it in Application.onCreate
     *  spawns GPU and content processes beside Flutter and the system kills the app.
     *  Runtime creation is main-thread only, so it is posted and the channel call
     *  returns immediately; the URL waits in [pendingLoads]. */
    private fun ensureStarted() {
        if (session != null || starting) return
        val application = app ?: return
        starting = true
        main.post {
            try {
                startRuntime(application)
            } catch (error: Throwable) {
                Log.e(tag, "gecko start failed", error)
                starting = false
            }
        }
    }

    private fun startRuntime(application: Application) {
        if (session != null) {
            starting = false
            return
        }
        val created = GeckoRuntime.create(
            application,
            GeckoRuntimeSettings.Builder()
                .javaScriptEnabled(true)
                .fissionEnabled(false)
                .extensionsProcessEnabled(false)
                .build(),
        )
        runtime = created
        val settings = GeckoSessionSettings.Builder()
            .userAgentMode(GeckoSessionSettings.USER_AGENT_MODE_MOBILE)
            .viewportMode(GeckoSessionSettings.VIEWPORT_MODE_MOBILE)
            .suspendMediaWhenInactive(true)
            .allowJavascript(true)
            .build()
        val opened = GeckoSession(settings)
        wire(opened)
        opened.open(created)
        session = opened
        starting = false
        applyAgent(opened)
        if (textZoom != 100) postZoom()
        applyPrivateMode()
        pendingView?.let { waiting ->
            pendingView = null
            bindView(waiting)
        }
        val thread = HandlerThread("aven-gecko-ext")
        thread.start()
        Handler(thread.looper).post {
            created.webExtensionController
                .ensureBuiltIn(extensionUri, extensionId)
                .accept({ extension ->
                    if (extension == null) return@accept
                    main.post { onExtension(opened, extension) }
                }, { error ->
                    Log.e(tag, "extension install failed", error)
                    main.post {
                        extensionReady = true
                        flushLoads()
                    }
                })
        }
    }

    fun install(engine: FlutterEngine, activity: Activity) {
        hostActivity = activity
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result -> onCall(call.method, call.arguments, result) }
        engine.platformViewsController.registry.registerViewFactory(
            viewType,
            GeckoViewFactory(activity),
        )
    }

    fun attach(geckoView: GeckoView) {
        val current = session
        if (current == null) {
            pendingView = geckoView
            ensureStarted()
            return
        }
        bindView(geckoView)
    }

    private fun bindView(geckoView: GeckoView) {
        val current = session ?: return
        geckoView.setBackgroundColor(Color.BLACK)
        geckoView.setViewBackend(GeckoView.BACKEND_TEXTURE_VIEW)
        if (view != null && view !== geckoView) {
            try {
                view?.releaseSession()
            } catch (_: Throwable) {
            }
        }
        if (geckoView.session == null) {
            geckoView.setSession(current)
        }
        geckoView.importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_YES
        geckoView.isFocusable = true
        geckoView.isFocusableInTouchMode = true
        view = geckoView
    }

    fun detach(geckoView: GeckoView) {
        if (view !== geckoView) return
        try {
            geckoView.releaseSession()
        } catch (_: Throwable) {
        }
        view = null
    }

    fun setActive(active: Boolean) {
        main.post {
            session?.setActive(active)
            if (!active) evalNow(pauseMediaJs)
        }
    }

    fun tap(x: Float, y: Float) {
        val target = view ?: return
        main.post {
            val downTime = SystemClock.uptimeMillis()
            val down = MotionEvent.obtain(downTime, downTime, MotionEvent.ACTION_DOWN, x, y, 0)
            val up = MotionEvent.obtain(downTime, downTime + 50, MotionEvent.ACTION_UP, x, y, 0)
            target.dispatchTouchEvent(down)
            target.dispatchTouchEvent(up)
            down.recycle()
            up.recycle()
        }
    }

    fun scroll(x: Float, y: Float, dx: Float, dy: Float) {
        val target = view ?: return
        main.post {
            val downTime = SystemClock.uptimeMillis()
            val props = arrayOf(
                MotionEvent.PointerProperties().apply {
                    id = 0
                    toolType = MotionEvent.TOOL_TYPE_MOUSE
                },
            )
            val coords = arrayOf(
                MotionEvent.PointerCoords().apply {
                    this.x = x
                    this.y = y
                    setAxisValue(MotionEvent.AXIS_HSCROLL, -dx / 48f)
                    setAxisValue(MotionEvent.AXIS_VSCROLL, -dy / 48f)
                },
            )
            val event = MotionEvent.obtain(
                downTime,
                downTime,
                MotionEvent.ACTION_SCROLL,
                1,
                props,
                coords,
                0,
                0,
                1f,
                1f,
                0,
                0,
                0,
                0,
            )
            try {
                target.onGenericMotionEvent(event)
            } finally {
                event.recycle()
            }
        }
    }

    private val pendingLoads = ArrayList<String>()

    private fun onExtension(opened: GeckoSession, extension: WebExtension) {
        extension.setMessageDelegate(messageDelegate, nativeApp)
        opened.webExtensionController.setMessageDelegate(extension, messageDelegate, nativeApp)
        extensionReady = true
        flushLoads()
    }

    private fun showing(): GeckoSession? = if (privateMode) privateSession else session

    private fun applyPrivateMode() {
        val rt = runtime ?: return
        if (!wantPrivate) {
            privateMode = false
            rebind(session)
            return
        }
        val existing = privateSession
        if (existing == null) {
            val settings = GeckoSessionSettings.Builder()
                .usePrivateMode(true)
                .userAgentMode(GeckoSessionSettings.USER_AGENT_MODE_MOBILE)
                .viewportMode(GeckoSessionSettings.VIEWPORT_MODE_MOBILE)
                .suspendMediaWhenInactive(true)
                .allowJavascript(true)
                .build()
            val opened = GeckoSession(settings)
            wire(opened)
            opened.open(rt)
            applyAgent(opened)
            privateSession = opened
            privateMode = true
            rebind(opened)
        } else {
            privateMode = true
            rebind(existing)
        }
    }

    private fun rebind(target: GeckoSession?) {
        val geckoView = view ?: return
        val next = target ?: return
        session?.setActive(next === session)
        privateSession?.setActive(next === privateSession)
        if (geckoView.session === next) return
        try {
            geckoView.releaseSession()
        } catch (_: Throwable) {
        }
        geckoView.setSession(next)
    }

    private fun flushLoads() {
        val queued = pendingLoads.toList()
        pendingLoads.clear()
        queued.forEach { showing()?.loadUri(it) }
    }

    private val messageDelegate = object : WebExtension.MessageDelegate {
        override fun onConnect(port: WebExtension.Port) {
            port.setDelegate(object : WebExtension.PortDelegate {
                override fun onPortMessage(message: Any, port: WebExtension.Port) {
                    handleExtMessage(message)
                }

                override fun onDisconnect(port: WebExtension.Port) {
                    if (this@GeckoBrowser.port === port) this@GeckoBrowser.port = null
                }
            })
            this@GeckoBrowser.port = port
            val queued = evalQueue.toList()
            evalQueue.clear()
            queued.forEach { port.postMessage(it) }
        }
    }

    private fun wire(opened: GeckoSession) {
        opened.progressDelegate = object : GeckoSession.ProgressDelegate {
            override fun onPageStart(session: GeckoSession, url: String) {
                this@GeckoBrowser.url = url
                val mode = when {
                    url.startsWith("https://") -> "secure"
                    url.startsWith("http://") -> "insecure"
                    else -> "unknown"
                }
                security = hashMapOf("mode" to mode, "host" to siteHost(url))
                emit("pageStarted", url)
                emit("security", security)
            }

            override fun onSecurityChange(
                session: GeckoSession,
                securityInfo: GeckoSession.ProgressDelegate.SecurityInformation,
            ) {
                if (session !== showing()) return
                rememberSecurity(securityInfo)
            }

            override fun onPageStop(session: GeckoSession, success: Boolean) {
                emit("pageFinished", this@GeckoBrowser.url ?: "")
                if (textZoom != 100) postZoom()
            }

            override fun onProgressChange(session: GeckoSession, progress: Int) {
                emit("progress", progress)
            }
        }
        opened.navigationDelegate = object : GeckoSession.NavigationDelegate {
            override fun onCanGoBack(session: GeckoSession, canGoBack: Boolean) {
                this@GeckoBrowser.canGoBack = canGoBack
            }

            override fun onCanGoForward(session: GeckoSession, canGoForward: Boolean) {
                this@GeckoBrowser.canGoForward = canGoForward
            }

            override fun onLoadRequest(
                session: GeckoSession,
                request: GeckoSession.NavigationDelegate.LoadRequest,
            ): GeckoResult<AllowOrDeny> {
                if (!isEmbeddable(request.uri)) {
                    if (request.target == GeckoSession.NavigationDelegate.TARGET_WINDOW_CURRENT &&
                        !request.isRedirect
                    ) {
                        emit("external", request.uri)
                    }
                    return GeckoResult.fromValue(AllowOrDeny.DENY)
                }
                if (request.target == GeckoSession.NavigationDelegate.TARGET_WINDOW_NEW) {
                    emit("newTab", request.uri)
                    return GeckoResult.fromValue(AllowOrDeny.DENY)
                }
                return GeckoResult.fromValue(AllowOrDeny.ALLOW)
            }

            override fun onLoadError(
                session: GeckoSession,
                uri: String?,
                error: WebRequestError,
            ): GeckoResult<String>? {
                emit(
                    "error",
                    mapOf(
                        "url" to (uri ?: ""),
                        "description" to "category ${error.category} code ${error.code}",
                        "code" to error.code,
                    ),
                )
                return null
            }
        }
        opened.contentDelegate = object : GeckoSession.ContentDelegate {
            override fun onTitleChange(session: GeckoSession, title: String?) {
                if (session === showing()) this@GeckoBrowser.title = title
            }

            override fun onExternalResponse(session: GeckoSession, response: WebResponse) {
                download(response)
            }

            override fun onContextMenu(
                session: GeckoSession,
                screenX: Int,
                screenY: Int,
                element: GeckoSession.ContentDelegate.ContextElement,
            ) {
                if (session !== showing()) return
                val link = element.linkUri ?: ""
                val src = element.srcUri ?: ""
                if (link.isEmpty() && src.isEmpty()) return
                emit(
                    "contextMenu",
                    mapOf(
                        "link" to link,
                        "src" to src,
                        "title" to (element.title ?: ""),
                        "alt" to (element.altText ?: ""),
                    ),
                )
            }
        }
        opened.permissionDelegate = object : PermissionDelegate {
            override fun onContentPermissionRequest(
                session: GeckoSession,
                perm: PermissionDelegate.ContentPermission,
            ): GeckoResult<Int> {
                val id = contentPermissionId(perm.permission) ?: return GeckoResult.fromValue(
                    PermissionDelegate.ContentPermission.VALUE_DENY,
                )
                if (id == "autoplay" && requireMediaGesture) {
                    return GeckoResult.fromValue(PermissionDelegate.ContentPermission.VALUE_DENY)
                }
                return decide(siteHost(perm.uri), id)
            }

            override fun onMediaPermissionRequest(
                session: GeckoSession,
                uri: String,
                video: Array<out PermissionDelegate.MediaSource>?,
                audio: Array<out PermissionDelegate.MediaSource>?,
                callback: PermissionDelegate.MediaCallback,
            ) {
                val host = siteHost(uri)
                val wantsVideo = !video.isNullOrEmpty()
                val wantsAudio = !audio.isNullOrEmpty()
                if (!wantsVideo && !wantsAudio) {
                    callback.reject()
                    return
                }
                fun finish(videoOk: Boolean, audioOk: Boolean) {
                    val allow = (!wantsVideo || videoOk) && (!wantsAudio || audioOk)
                    if (!allow) {
                        callback.reject()
                        return
                    }
                    callback.grant(video?.firstOrNull(), audio?.firstOrNull())
                }
                if (!wantsVideo) {
                    resolveChoice(host, "microphone") { finish(videoOk = false, audioOk = it) }
                } else if (!wantsAudio) {
                    resolveChoice(host, "camera") { finish(videoOk = it, audioOk = false) }
                } else {
                    resolveChoice(host, "camera") { videoOk ->
                        resolveChoice(host, "microphone") { audioOk ->
                            finish(videoOk, audioOk)
                        }
                    }
                }
            }

            override fun onAndroidPermissionsRequest(
                session: GeckoSession,
                permissions: Array<out String>?,
                callback: PermissionDelegate.Callback,
            ) {
                val activity = hostActivity
                if (activity == null || permissions.isNullOrEmpty()) {
                    callback.grant()
                    return
                }
                val missing = permissions.filter {
                    ContextCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED
                }
                if (missing.isEmpty()) {
                    callback.grant()
                    return
                }
                pendingAndroidPerm = callback
                ActivityCompat.requestPermissions(activity, missing.toTypedArray(), permissionRequestCode)
            }
        }
    }

    private fun applyAgent(current: GeckoSession) {
        val agent = userAgent
        val settings = current.settings
        if (agent.isNullOrBlank()) {
            settings.setUserAgentOverride(null)
            settings.setUserAgentMode(GeckoSessionSettings.USER_AGENT_MODE_MOBILE)
            settings.setViewportMode(GeckoSessionSettings.VIEWPORT_MODE_MOBILE)
        } else {
            settings.setUserAgentOverride(agent)
            val desktop = !agent.contains("Mobile") && !agent.contains("Android")
            settings.setUserAgentMode(
                if (desktop) GeckoSessionSettings.USER_AGENT_MODE_DESKTOP
                else GeckoSessionSettings.USER_AGENT_MODE_MOBILE,
            )
            settings.setViewportMode(
                if (desktop) GeckoSessionSettings.VIEWPORT_MODE_DESKTOP
                else GeckoSessionSettings.VIEWPORT_MODE_MOBILE,
            )
        }
    }

    fun onRuntimePermissionResult(grantResults: IntArray) {
        val callback = pendingAndroidPerm
        pendingAndroidPerm = null
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        if (granted) callback?.grant() else callback?.reject()
    }

    private fun rememberSecurity(info: GeckoSession.ProgressDelegate.SecurityInformation) {
        val mixedLoaded = info.mixedModeActive ==
            GeckoSession.ProgressDelegate.SecurityInformation.CONTENT_LOADED
        val mode = when {
            !info.isSecure -> "insecure"
            info.isException || mixedLoaded -> "warning"
            else -> "secure"
        }
        val cert = info.certificate
        val format = SimpleDateFormat("d MMM yyyy", Locale.getDefault())
        security = hashMapOf(
            "mode" to mode,
            "host" to (info.host ?: siteHost(url ?: "")),
            "origin" to (info.origin ?: ""),
            "subject" to (cert?.subjectX500Principal?.name ?: ""),
            "issuer" to (cert?.issuerX500Principal?.name ?: ""),
            "validFrom" to (cert?.notBefore?.let { format.format(it) } ?: ""),
            "validTo" to (cert?.notAfter?.let { format.format(it) } ?: ""),
        )
        emit("security", HashMap(security))
    }

    private fun siteHost(raw: String): String {
        if (raw.isBlank()) return ""
        return try {
            Uri.parse(raw).host?.lowercase() ?: ""
        } catch (_: Throwable) {
            ""
        }
    }

    private val sitePerms = listOf(
        "location" to "Konum",
        "camera" to "Kamera",
        "microphone" to "Mikrofon",
        "notifications" to "Bildirimler",
        "storage" to "Depolama",
        "autoplay" to "Otomatik oynatma",
    )

    private fun contentPermissionId(permission: Int): String? = when (permission) {
        PermissionDelegate.PERMISSION_GEOLOCATION -> "location"
        PermissionDelegate.PERMISSION_DESKTOP_NOTIFICATION -> "notifications"
        PermissionDelegate.PERMISSION_PERSISTENT_STORAGE -> "storage"
        PermissionDelegate.PERMISSION_AUTOPLAY_AUDIBLE,
        PermissionDelegate.PERMISSION_AUTOPLAY_INAUDIBLE,
        -> "autoplay"
        else -> null
    }

    private fun permPrefs() = app?.getSharedPreferences("aven_site_perms", Context.MODE_PRIVATE)

    private fun defaultChoice(id: String): String = if (id == "autoplay") "allow" else "ask"

    private fun permChoice(host: String, id: String): String {
        val fallback = defaultChoice(id)
        if (privateMode || host.isEmpty()) return fallback
        return permPrefs()?.getString("$host|$id", fallback) ?: fallback
    }

    private fun savePerm(host: String, id: String, value: String) {
        if (value != "allow" && value != "block" && value != "ask") return
        permPrefs()?.edit()?.putString("$host|$id", value)?.apply()
    }

    private fun decide(host: String, id: String): GeckoResult<Int> {
        val pending = GeckoResult<Int>()
        resolveChoice(host, id) { allowed ->
            pending.complete(
                if (allowed) PermissionDelegate.ContentPermission.VALUE_ALLOW
                else PermissionDelegate.ContentPermission.VALUE_DENY,
            )
        }
        return pending
    }

    private fun resolveChoice(host: String, id: String, done: (Boolean) -> Unit) {
        when (permChoice(host, id)) {
            "allow" -> done(true)
            "block" -> done(false)
            else -> askPermission(host, id, done)
        }
    }

    private fun askPermission(host: String, id: String, done: (Boolean) -> Unit) {
        val payload = mapOf(
            "host" to host,
            "id" to id,
        )
        main.post {
            val messenger = channel
            if (messenger == null) {
                done(false)
                return@post
            }
            messenger.invokeMethod("permissionPrompt", payload, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    val allow = result == true
                    if (!privateMode && host.isNotEmpty()) {
                        savePerm(host, id, if (allow) "allow" else "block")
                    }
                    done(allow)
                }

                override fun error(code: String, message: String?, details: Any?) {
                    done(false)
                }

                override fun notImplemented() {
                    done(false)
                }
            })
        }
    }

    private fun siteSettings(): List<Map<String, String>> {
        val host = siteHost(url ?: "")
        return sitePerms.map { (id, label) ->
            mapOf(
                "id" to id,
                "label" to label,
                "value" to permChoice(host, id),
                "fallback" to defaultChoice(id),
                "host" to host,
            )
        }
    }

    private fun downloadUrl(raw: String) {
        if (!raw.startsWith("http://") && !raw.startsWith("https://")) return
        val application = app ?: return
        val name = raw.substringAfterLast('/').substringBefore('?').ifBlank { "aven-indirme" }
        try {
            val request = DownloadManager.Request(Uri.parse(raw))
                .setTitle(name)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, name)
            val manager = application.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            manager.enqueue(request)
            watchDownloads()
        } catch (error: Throwable) {
            Log.e(tag, "download failed", error)
        }
    }

    private fun openDownload(id: Long) {
        val application = app ?: return
        val activity = hostActivity ?: return
        val manager = application.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val uri = manager.getUriForDownloadedFile(id) ?: return
        val mime = manager.getMimeTypeForDownloadedFile(id) ?: "*/*"
        val view = android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            activity.startActivity(view)
        } catch (error: Throwable) {
            Log.e(tag, "open download failed", error)
        }
    }

    private fun cancelDownload(id: Long) {
        val application = app ?: return
        val manager = application.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        manager.remove(id)
        emit("downloads", listDownloads())
    }

    private fun download(response: WebResponse) {
        val raw = response.uri ?: return
        downloadUrl(raw)
    }

    private fun listDownloads(): List<Map<String, String>> {
        val application = app ?: return emptyList()
        val manager = application.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val cursor = manager.query(DownloadManager.Query()) ?: return emptyList()
        val items = ArrayList<Map<String, String>>()
        try {
            val titleCol = cursor.getColumnIndex(DownloadManager.COLUMN_TITLE)
            val statusCol = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
            val idCol = cursor.getColumnIndex(DownloadManager.COLUMN_ID)
            val soFarCol = cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
            val totalCol = cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
            var count = 0
            while (cursor.moveToNext() && count < 40) {
                val status = if (statusCol >= 0) cursor.getInt(statusCol) else 0
                val soFar = if (soFarCol >= 0) cursor.getLong(soFarCol) else 0L
                val total = if (totalCol >= 0) cursor.getLong(totalCol) else -1L
                val progress = when {
                    status == DownloadManager.STATUS_SUCCESSFUL -> 100
                    total > 0 -> ((soFar * 100) / total).toInt().coerceIn(0, 100)
                    else -> -1
                }
                val label = when (status) {
                    DownloadManager.STATUS_SUCCESSFUL -> "success"
                    DownloadManager.STATUS_RUNNING -> "running"
                    DownloadManager.STATUS_PENDING -> "pending"
                    DownloadManager.STATUS_PAUSED -> "paused"
                    DownloadManager.STATUS_FAILED -> "failed"
                    else -> ""
                }
                items.add(
                    mapOf(
                        "title" to (if (titleCol >= 0) cursor.getString(titleCol) ?: "" else ""),
                        "status" to label,
                        "id" to (if (idCol >= 0) cursor.getLong(idCol).toString() else ""),
                        "progress" to progress.toString(),
                    ),
                )
                count += 1
            }
        } finally {
            cursor.close()
        }
        return items
    }

    private fun watchDownloads() {
        if (downloadWatch != null) return
        val task = object : Runnable {
            override fun run() {
                val items = listDownloads()
                emit("downloads", items)
                val active = items.any {
                    val status = it["status"]
                    status == "running" || status == "pending" || status == "paused"
                }
                if (active) {
                    main.postDelayed(this, 600)
                } else {
                    downloadWatch = null
                }
            }
        }
        downloadWatch = task
        main.post(task)
    }

    private fun onCall(method: String, arguments: Any?, result: MethodChannel.Result) {
        val needsEngine = method == "loadUrl" || method == "reload" ||
            method == "goBack" || method == "goForward"
        if (needsEngine) ensureStarted()
        val current = session
        when (method) {
            "loadUrl" -> {
                val url = (arguments as? Map<*, *>)?.get("url") as? String
                if (url.isNullOrEmpty()) {
                    result.error("url", "missing url", null)
                } else {
                    val target = showing()
                    if (target == null) {
                        pendingLoads.add(url)
                    } else {
                        target.setActive(true)
                        if (extensionReady) target.loadUri(url) else pendingLoads.add(url)
                    }
                    result.success(null)
                }
            }
            "reload" -> {
                showing()?.reload()
                result.success(null)
            }
            "goBack" -> {
                showing()?.goBack(true)
                result.success(null)
            }
            "goForward" -> {
                showing()?.goForward(true)
                result.success(null)
            }
            "setPrivate" -> {
                wantPrivate = (arguments as? Map<*, *>)?.get("enabled") == true
                applyPrivateMode()
                result.success(null)
            }
            "find" -> {
                val args = arguments as? Map<*, *>
                val query = args?.get("query") as? String ?: ""
                val backwards = args?.get("backwards") == true
                val finder = showing()?.finder
                if (query.isEmpty() || finder == null) {
                    result.success(mapOf("current" to 0, "total" to 0))
                } else {
                    val flags = if (backwards) GeckoSession.FINDER_FIND_BACKWARDS else 0
                    finder.find(query, flags).accept({ found ->
                        main.post {
                            result.success(
                                mapOf(
                                    "current" to (found?.current ?: 0),
                                    "total" to (found?.total ?: 0),
                                ),
                            )
                        }
                    }, { _ ->
                        main.post { result.success(mapOf("current" to 0, "total" to 0)) }
                    })
                }
            }
            "capturePreview" -> {
                val bitmap = textureOf(view)?.bitmap
                if (bitmap == null) {
                    result.success(null)
                } else {
                    val maxW = 360
                    val scaled = if (bitmap.width > maxW) {
                        val height = (bitmap.height * (maxW.toFloat() / bitmap.width)).toInt().coerceAtLeast(1)
                        Bitmap.createScaledBitmap(bitmap, maxW, height, true)
                    } else {
                        bitmap
                    }
                    val bytes = ByteArrayOutputStream()
                    scaled.compress(Bitmap.CompressFormat.JPEG, 45, bytes)
                    if (scaled !== bitmap) scaled.recycle()
                    result.success(bytes.toByteArray())
                }
            }
            "clearFind" -> {
                showing()?.finder?.clear()
                result.success(null)
            }
            "requestAutofill" -> result.success(requestAutofill())
            "openAutofillSettings" -> result.success(openAutofillSettings())
            "listDownloads" -> result.success(listDownloads())
            "downloadUrl" -> {
                val raw = (arguments as? Map<*, *>)?.get("url") as? String ?: ""
                downloadUrl(raw)
                result.success(null)
            }
            "openDownload" -> {
                val id = (arguments as? Map<*, *>)?.get("id")?.toString()?.toLongOrNull()
                if (id != null) openDownload(id)
                result.success(null)
            }
            "cancelDownload" -> {
                val id = (arguments as? Map<*, *>)?.get("id")?.toString()?.toLongOrNull()
                if (id != null) cancelDownload(id)
                result.success(null)
            }
            "getSecurity" -> result.success(HashMap(security))
            "getSiteSettings" -> result.success(siteSettings())
            "setSiteSetting" -> {
                val args = arguments as? Map<*, *>
                val id = args?.get("id") as? String
                val value = args?.get("value") as? String
                val host = siteHost(url ?: "")
                if (!id.isNullOrEmpty() && !value.isNullOrEmpty() && host.isNotEmpty() && !privateMode) {
                    savePerm(host, id, value)
                }
                result.success(null)
            }
            "share" -> {
                val text = (arguments as? Map<*, *>)?.get("text") as? String ?: ""
                val activity = hostActivity
                if (activity == null || text.isEmpty()) {
                    result.success(null)
                } else {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    activity.startActivity(Intent.createChooser(send, "Paylaş"))
                    result.success(null)
                }
            }
            "canGoBack" -> result.success(canGoBack)
            "canGoForward" -> result.success(canGoForward)
            "getTitle" -> result.success(title)
            "getUserAgent" -> {
                if (current == null) {
                    result.success(userAgent ?: GeckoSession.getDefaultUserAgent())
                } else {
                    try {
                        current.getUserAgent().accept({ value ->
                            main.post { result.success(value ?: userAgent) }
                        }, {
                            main.post { result.success(userAgent ?: GeckoSession.getDefaultUserAgent()) }
                        })
                    } catch (_: Throwable) {
                        result.success(userAgent ?: GeckoSession.getDefaultUserAgent())
                    }
                }
            }
            "setUserAgent" -> {
                userAgent = (arguments as? Map<*, *>)?.get("agent") as? String
                if (current != null) applyAgent(current)
                result.success(null)
            }
            "setTextZoom" -> {
                val raw = (arguments as? Map<*, *>)?.get("zoom")
                textZoom = when (raw) {
                    is Int -> raw
                    is Long -> raw.toInt()
                    is Double -> raw.toInt()
                    else -> 100
                }.coerceIn(50, 300)
                postZoom()
                result.success(null)
            }
            "setMediaGesture" -> {
                requireMediaGesture = (arguments as? Map<*, *>)?.get("require") == true
                result.success(null)
            }
            "eval" -> {
                val code = (arguments as? Map<*, *>)?.get("code") as? String
                if (code == null) {
                    result.error("js", "missing code", null)
                } else if (session == null) {
                    result.success(null)
                } else {
                    val id = ids.incrementAndGet()
                    pendingEval[id] = result
                    main.postDelayed({
                        pendingEval.remove(id)?.error("js", "timeout", null)
                    }, 8000)
                    val message = JSONObject()
                        .put("type", "eval")
                        .put("id", id)
                        .put("code", code)
                    val currentPort = port
                    if (currentPort == null) evalQueue.add(message) else currentPort.postMessage(message)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun postZoom() {
        val message = JSONObject()
            .put("type", "zoom")
            .put("zoom", textZoom)
        val currentPort = port
        if (currentPort == null) evalQueue.add(message) else currentPort.postMessage(message)
    }

    private fun markAutofill(root: View) {
        var node: View? = root
        while (node != null) {
            node.importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_YES
            val parent = node.parent
            node = parent as? View
        }
    }

    private fun requestAutofill(): String {
        val activity = hostActivity
        val gecko = view
        val manager = activity?.getSystemService(AutofillManager::class.java)
            ?: return "unsupported"
        if (!manager.isAutofillSupported) return "unsupported"
        if (!manager.isEnabled || !manager.hasEnabledAutofillServices()) return "off"
        if (gecko == null || !gecko.isAttachedToWindow) return "failed"
        return try {
            markAutofill(gecko)
            manager.notifyViewEntered(gecko)
            manager.requestAutofill(gecko)
            "ok"
        } catch (_: Throwable) {
            "failed"
        }
    }

    private fun openAutofillSettings(): Boolean {
        val activity = hostActivity ?: return false
        val intent = Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE).apply {
            data = Uri.parse("package:com.google.android.gms")
        }
        return try {
            activity.startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun textureOf(root: View?): TextureView? {
        if (root is TextureView) return root
        if (root is ViewGroup) {
            for (index in 0 until root.childCount) {
                textureOf(root.getChildAt(index))?.let { return it }
            }
        }
        return null
    }

    private fun evalNow(code: String) {
        val message = JSONObject()
            .put("type", "eval")
            .put("id", ids.incrementAndGet())
            .put("code", code)
        val currentPort = port
        if (currentPort == null) evalQueue.add(message) else currentPort.postMessage(message)
    }

    private fun handleExtMessage(message: Any) {
        val obj = message as? JSONObject ?: return
        main.post {
            when (obj.optString("type")) {
                "channel" -> emit(
                    "js",
                    mapOf(
                        "channel" to obj.optString("name"),
                        "message" to obj.optString("data"),
                    ),
                )
                "evalResult" -> {
                    val id = obj.optInt("id")
                    val pending = pendingEval.remove(id) ?: return@post
                    if (obj.has("error") && !obj.isNull("error")) {
                        pending.error("js", obj.optString("error"), null)
                        return@post
                    }
                    val value = if (obj.has("value")) obj.opt("value") else null
                    if (value is JSONObject && value.has("__avenError")) {
                        pending.error("js", value.optString("__avenError"), null)
                    } else {
                        pending.success(dartValue(value))
                    }
                }
            }
        }
    }

    private fun dartValue(value: Any?): Any? {
        return when (value) {
            null, JSONObject.NULL -> null
            is JSONObject, is JSONArray -> value.toString()
            else -> value
        }
    }

    private fun emit(method: String, args: Any?) {
        main.post { channel?.invokeMethod(method, args) }
    }

    private fun isEmbeddable(uri: String): Boolean {
        val scheme = uri.substringBefore(':', "").lowercase()
        if (scheme.isEmpty()) return true
        return scheme == "http" ||
            scheme == "https" ||
            scheme == "about" ||
            scheme == "data" ||
            scheme == "blob" ||
            scheme == "javascript" ||
            scheme == "file" ||
            scheme == "content"
    }

    private const val pauseMediaJs = """
(function(){
  window.__avenWantPlay = false;
  function kill(v){
    try { v.pause(); v.muted = true; } catch (e) {}
  }
  try { document.querySelectorAll('video,audio').forEach(kill); } catch (e) {}
})();
"""
}

private class GeckoViewFactory(private val activity: Activity) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: android.content.Context, viewId: Int, args: Any?): PlatformView {
        return GeckoPlatformView(activity)
    }
}

private class GeckoPlatformView(activity: Activity) : PlatformView {
    private val geckoView = GeckoView(activity)

    init {
        GeckoBrowser.attach(geckoView)
    }

    override fun getView(): View = geckoView

    override fun dispose() {
        GeckoBrowser.detach(geckoView)
    }
}
