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
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Same-LAN handoff: the TV build advertises itself, the phone finds it and
 * sends the open page or a direct video URL.
 */
internal object AvenCast {
    private const val serviceType = "_avenbrowser._tcp."
    private const val discoverCode = 4102
    private const val hostCode = 4103

    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var server: ServerSocket? = null
    private var registration: NsdManager.RegistrationListener? = null
    private var nsd: NsdManager? = null
    private var multicast: WifiManager.MulticastLock? = null
    private var pendingDiscover: MethodChannel.Result? = null
    private var discoverActivity: Activity? = null
    private var pendingHost: Activity? = null

    fun attach(messenger: MethodChannel) {
        channel = messenger
    }

    fun host(activity: Activity) {
        if (server != null) return
        if (!ensureNearby(activity, hostCode)) {
            pendingHost = activity
            return
        }
        startServer(activity.applicationContext)
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
            hostCode -> {
                val activity = pendingHost
                pendingHost = null
                if (granted && activity != null) startServer(activity.applicationContext)
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
                try {
                    val client = socket.accept()
                    client.soTimeout = 4000
                    val line = client.getInputStream().bufferedReader().readLine()
                    client.close()
                    if (!line.isNullOrBlank()) deliver(line)
                } catch (_: Throwable) {
                    break
                }
            }
        }.start()
        val manager = context.getSystemService(NsdManager::class.java) ?: return
        nsd = manager
        val info = NsdServiceInfo().apply {
            serviceName = "Aven TV"
            serviceType = serviceType
            port = socket.localPort
        }
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {}
            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {}
            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
        }
        registration = listener
        try {
            manager.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (_: Throwable) {
        }
    }

    private fun deliver(line: String) {
        val obj = try {
            JSONObject(line)
        } catch (_: Throwable) {
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
            manager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, listener)
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
}
