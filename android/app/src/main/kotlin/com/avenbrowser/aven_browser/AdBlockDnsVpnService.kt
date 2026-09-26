package com.avenbrowser.aven_browser

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat

/**
 * DNS-only VPN: keeps traffic on the underlying network but points this app
 * at AdGuard DNS. Local [AdBlockLists] still do host intercept in WebView.
 */
class AdBlockDnsVpnService : VpnService() {
    private var tun: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val mode = intent?.getStringExtra(EXTRA_MODE) ?: MODE_OFF
        if (mode == MODE_OFF || intent?.action == ACTION_STOP) {
            // Satisfy FGS contract if we were started via startForegroundService by mistake.
            startForeground(NOTIF_ID, buildNotification(MODE_OFF))
            stopVpn()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground(NOTIF_ID, buildNotification(mode))
        startVpn(mode)
        return START_STICKY
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    private fun startVpn(mode: String) {
        stopVpn()
        val primary = "94.140.14.14" // AdGuard DNS Default
        val secondary = "94.140.15.15"
        val label = "AdGuard DNS"
        try {
            val cm = getSystemService(ConnectivityManager::class.java)
            val active = cm?.activeNetwork
            val builder = Builder()
                .setSession("Aven $label")
                .setMtu(1500)
                .addAddress("10.8.1.2", 32)
                .addDnsServer(primary)
                .addDnsServer(secondary)
                .allowFamily(android.system.OsConstants.AF_INET)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }
            if (active != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                builder.setUnderlyingNetworks(arrayOf(active))
            }
            // No default route: traffic stays on Wi‑Fi/Ethernet; DNS uses VPN servers.
            tun = builder.establish()
            if (tun == null) {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        } catch (_: Exception) {
            stopVpn()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun stopVpn() {
        try {
            tun?.close()
        } catch (_: Exception) {
        }
        tun = null
    }

    private fun buildNotification(mode: String): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm?.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Reklam DNS",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("AdGuard DNS açık")
            .setContentText("Yerel host listesi + DNS engelleme")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val ACTION_STOP = "com.avenbrowser.aven_browser.STOP_DNS_VPN"
        const val EXTRA_MODE = "mode"
        const val MODE_OFF = "off"
        const val MODE_ADGUARD = "adguard"
        private const val CHANNEL_ID = "aven_adblock_dns"
        private const val NOTIF_ID = 42

        fun prepareIntent(context: Context): Intent? = VpnService.prepare(context)

        fun start(context: Context, mode: String) {
            val i = Intent(context, AdBlockDnsVpnService::class.java)
                .putExtra(EXTRA_MODE, mode)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        }

        fun stop(context: Context) {
            // Must not use startForegroundService for stop — Android kills the app if
            // startForeground() is not called in time (boot with mode=off hit this).
            context.stopService(Intent(context, AdBlockDnsVpnService::class.java))
        }
    }
}
