package dev.furina.avenbrowser

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.KeyEvent
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.lang.ref.WeakReference
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Same-LAN handoff: the TV build advertises itself, the phone finds it and
 * sends the open page or a direct video URL. The same link carries remote
 * commands (keys, cursor moves, typed text) from the phone's TV remote.
 */
internal object AvenCast {
    private const val castServiceType = "_avenbrowser._tcp."
    private const val discoverCode = 4102

    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var server: ServerSocket? = null
    private var registration: NsdManager.RegistrationListener? = null
    private var nsd: NsdManager? = null
    private var multicast: WifiManager.MulticastLock? = null
    private var pendingDiscover: MethodChannel.Result? = null
    private var discoverActivity: Activity? = null
    private var hostActivity: WeakReference<Activity>? = null

    // Phone side of the remote: one kept-open socket, written in order.
    private val remoteWriter = Executors.newSingleThreadExecutor()
    private var remoteSocket: Socket? = null
    private var remoteTarget = ""

    fun attach(messenger: MethodChannel) {
        channel = messenger
    }

    /**
     * TV: listen and advertise right away. Advertising a service on the LAN
     * needs no runtime permission, so the TV never asks for nearby devices —
     * asking used to block this on a denial and re-prompt on every launch.
     */
    fun host(activity: Activity) {
        hostActivity = WeakReference(activity)
        if (server != null) return
        startServer(activity.applicationContext)
    }

    /** Phone: sends one remote command; reconnects once if the TV dropped the link. */
    fun sendRemote(host: String, port: Int, payload: Map<String, Any?>, result: MethodChannel.Result) {
        if (host.isBlank() || port <= 0) {
            result.success(false)
            return
        }
        val line = JSONObject(payload).toString() + "\n"
        remoteWriter.execute {
            val target = "$host:$port"
            var ok = false
            for (attempt in 0..1) {
                try {
                    var socket = remoteSocket
                    if (socket == null || socket.isClosed || remoteTarget != target) {
                        try {
                            socket?.close()
                        } catch (_: Throwable) {
                        }
                        socket = Socket().apply {
                            tcpNoDelay = true
                            connect(InetSocketAddress(host, port), 2500)
                        }
                        remoteSocket = socket
                        remoteTarget = target
                    }
                    socket.getOutputStream().apply {
                        write(line.toByteArray(Charsets.UTF_8))
                        flush()
                    }
                    ok = true
                    break
                } catch (_: Throwable) {
                    try {
                        remoteSocket?.close()
                    } catch (_: Throwable) {
                    }
                    remoteSocket = null
                }
            }
            main.post { result.success(ok) }
        }
    }

    fun closeRemote() {
        remoteWriter.execute {
            try {
                remoteSocket?.close()
            } catch (_: Throwable) {
            }
            remoteSocket = null
        }
    }

    fun discover(activity: Activity, result: MethodChannel.Result) {
        if (!ensureNearby(activity, discoverCode)) {
            pendingDiscover = result
            discoverActivity = activity
            return
        }
        scan(activity.applicationContext, result)
    }

    fun onPermission(requestCode: Int, grantResults: IntArray) {
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        when (requestCode) {
            discoverCode -> {
                val pending = pendingDiscover
                val activity = discoverActivity
                pendingDiscover = null
                discoverActivity = null
                if (!granted || pending == null || activity == null) {
                    pending?.success(
                        mapOf("devices" to emptyList<Map<String, String>>(), "error" to "permission"),
                    )
                    return
                }
                scan(activity.applicationContext, pending)
            }
        }
    }

    fun send(host: String, port: Int, url: String, play: Boolean, result: MethodChannel.Result) {
        if (host.isBlank() || port <= 0 || url.isBlank()) {
            result.success(false)
            return
        }
        Thread {
            val ok = try {
                Socket().use { socket ->
                    socket.connect(InetSocketAddress(host, port), 2500)
                    val line = JSONObject().put("url", url).put("play", play).toString() + "\n"
                    socket.getOutputStream().write(line.toByteArray(Charsets.UTF_8))
                }
                true
            } catch (_: Throwable) {
                false
            }
            main.post { result.success(ok) }
        }.start()
    }

    fun stop() {
        try {
            registration?.let { nsd?.unregisterService(it) }
        } catch (_: Throwable) {
        }
        registration = null
        try {
            server?.close()
        } catch (_: Throwable) {
        }
        server = null
        if (multicast?.isHeld == true) multicast?.release()
    }

    private fun ensureNearby(activity: Activity, code: Int): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        val perm = Manifest.permission.NEARBY_WIFI_DEVICES
        if (ContextCompat.checkSelfPermission(activity, perm) == PackageManager.PERMISSION_GRANTED) {
            return true
        }
        ActivityCompat.requestPermissions(activity, arrayOf(perm), code)
        return false
    }

    private fun holdMulticast(context: Context) {
        if (multicast?.isHeld == true) return
        val wifi = context.applicationContext.getSystemService(WifiManager::class.java) ?: return
        val lock = wifi.createMulticastLock("aven-cast")
        lock.setReferenceCounted(false)
        lock.acquire()
        multicast = lock
    }

    private fun startServer(context: Context) {
        if (server != null) return
        holdMulticast(context)
        val socket = ServerSocket(0)
        server = socket
        Thread {
            while (!socket.isClosed) {
                val client = try {
                    socket.accept()
                } catch (_: Throwable) {
                    break
                }
                // Each phone gets its own reader: a link send is one line, the
                // remote keeps the socket open for many. A client that stalls or
                // drops only loses its own link; the TV keeps listening.
                Thread { serve(client) }.start()
            }
        }.start()
        val manager = context.getSystemService(NsdManager::class.java) ?: return
        nsd = manager
        val info = NsdServiceInfo().apply {
            serviceName = "Aven TV"
            serviceType = castServiceType
            port = socket.localPort
        }
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {
                Log.i("AvenCast", "advertised ${serviceInfo.serviceName} on port ${socket.localPort}")
            }

            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                Log.w("AvenCast", "advertising failed: $errorCode")
            }
            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {}
            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
        }
        registration = listener
        try {
            manager.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (error: Throwable) {
            Log.w("AvenCast", "advertising failed", error)
        }
    }

    private fun serve(client: Socket) {
        try {
            client.soTimeout = 120_000
            val reader = client.getInputStream().bufferedReader()
            while (true) {
                val line = reader.readLine() ?: break
                if (line.isNotBlank()) deliver(line)
            }
        } catch (_: Throwable) {
        } finally {
            try {
                client.close()
            } catch (_: Throwable) {
            }
        }
    }

    private fun deliver(line: String) {
        val obj = try {
            JSONObject(line)
        } catch (_: Throwable) {
            return
        }
        val cmd = obj.optString("cmd")
        if (cmd.isNotBlank()) {
            remote(cmd, obj)
            return
        }
        val url = obj.optString("url")
        if (url.isBlank()) return
        val play = obj.optBoolean("play")
        main.post {
            channel?.invokeMethod("cast", mapOf("url" to url, "play" to play))
        }
    }

    private fun scan(context: Context, result: MethodChannel.Result) {
        holdMulticast(context)
        val manager = context.getSystemService(NsdManager::class.java)
        if (manager == null) {
            result.success(mapOf("devices" to emptyList<Map<String, Any>>(), "error" to ""))
            return
        }
        val found = LinkedHashMap<String, Map<String, Any>>()
        val finished = AtomicBoolean(false)
        fun finish() {
            if (!finished.compareAndSet(false, true)) return
            main.post {
                result.success(mapOf("devices" to found.values.toList(), "error" to ""))
            }
        }
        val listener = object : NsdManager.DiscoveryListener {
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                finish()
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                try {
                    manager.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                        override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {}

                        override fun onServiceResolved(info: NsdServiceInfo) {
                            val host = info.host?.hostAddress ?: return
                            if (host.contains(':')) return
                            val key = "$host:${info.port}"
                            found[key] = mapOf(
                                "name" to info.serviceName,
                                "host" to host,
                                "port" to info.port,
                            )
                        }
                    })
                } catch (_: Throwable) {
                }
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {}
        }
        try {
            manager.discoverServices(castServiceType, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (_: Throwable) {
            finish()
            return
        }
        main.postDelayed({
            try {
                manager.stopServiceDiscovery(listener)
            } catch (_: Throwable) {
            }
            finish()
        }, 2200)
    }

    /** TV: keys go through the activity like a real remote; the rest is Dart's. */
    private fun remote(cmd: String, obj: JSONObject) {
        if (cmd == "key") {
            val code = when (obj.optString("key")) {
                "up" -> KeyEvent.KEYCODE_DPAD_UP
                "down" -> KeyEvent.KEYCODE_DPAD_DOWN
                "left" -> KeyEvent.KEYCODE_DPAD_LEFT
                "right" -> KeyEvent.KEYCODE_DPAD_RIGHT
                "ok" -> KeyEvent.KEYCODE_DPAD_CENTER
                "back" -> KeyEvent.KEYCODE_BACK
                "play" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                else -> return
            }
            main.post { pressKey(code) }
            return
        }
        val args = HashMap<String, Any?>()
        args["cmd"] = cmd
        for (key in obj.keys()) args[key] = obj.opt(key)
        main.post { channel?.invokeMethod("remote", args) }
    }

    fun pressKey(code: Int) {
        val activity = hostActivity?.get() ?: return
        val now = SystemClock.uptimeMillis()
        activity.dispatchKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_DOWN, code, 0))
        activity.dispatchKeyEvent(KeyEvent(now, now + 40, KeyEvent.ACTION_UP, code, 0))
    }
}
