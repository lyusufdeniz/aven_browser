package dev.furina.avenbrowser

import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.util.Log
import android.webkit.CookieManager
import android.webkit.URLUtil
import android.widget.Toast

/**
 * Downloads through Android's DownloadManager for the WebView page (phone
 * and TV). Files land in the public Downloads folder; APKs
 * open in the system installer.
 */
internal object AvenDownloads {
    private const val tag = "AvenDownloads"
    private const val apkMime = "application/vnd.android.package-archive"

    /** Starts a download; returns the file name, or null when it could not start. */
    fun start(
        context: Context,
        url: String,
        userAgent: String? = null,
        contentDisposition: String? = null,
        mimeType: String? = null,
    ): String? {
        if (!url.startsWith("http://") && !url.startsWith("https://")) return null
        val name = URLUtil.guessFileName(url, contentDisposition, mimeType)
            .ifBlank { "aven-download" }
        return try {
            val request = DownloadManager.Request(Uri.parse(url))
                .setTitle(name)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, name)
            if (!mimeType.isNullOrBlank()) request.setMimeType(mimeType)
            if (!userAgent.isNullOrBlank()) request.addRequestHeader("User-Agent", userAgent)
            // Signed-in downloads need the page's cookies.
            CookieManager.getInstance().getCookie(url)?.let { request.addRequestHeader("Cookie", it) }
            manager(context).enqueue(request)
            name
        } catch (error: Throwable) {
            Log.e(tag, "download failed", error)
            null
        }
    }

    /** Starts a download from a page and tells the viewer it began. */
    fun startWithNotice(
        context: Context,
        url: String,
        userAgent: String?,
        contentDisposition: String?,
        mimeType: String?,
    ) {
        val name = start(context, url, userAgent, contentDisposition, mimeType)
        val text = if (name != null) {
            context.getString(R.string.aven_download_started, name)
        } else {
            context.getString(R.string.aven_download_start_failed)
        }
        Toast.makeText(context, text, Toast.LENGTH_SHORT).show()
    }

    fun list(context: Context): List<Map<String, String>> {
        val cursor = manager(context).query(DownloadManager.Query()) ?: return emptyList()
        val items = ArrayList<Map<String, String>>()
        cursor.use {
            val titleCol = it.getColumnIndex(DownloadManager.COLUMN_TITLE)
            val statusCol = it.getColumnIndex(DownloadManager.COLUMN_STATUS)
            val idCol = it.getColumnIndex(DownloadManager.COLUMN_ID)
            val soFarCol = it.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
            val totalCol = it.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
            val mimeCol = it.getColumnIndex(DownloadManager.COLUMN_MEDIA_TYPE)
            while (it.moveToNext() && items.size < 40) {
                val status = if (statusCol >= 0) it.getInt(statusCol) else 0
                val soFar = if (soFarCol >= 0) it.getLong(soFarCol) else 0L
                val total = if (totalCol >= 0) it.getLong(totalCol) else -1L
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
                val title = if (titleCol >= 0) it.getString(titleCol) ?: "" else ""
                val mime = if (mimeCol >= 0) it.getString(mimeCol) ?: "" else ""
                items.add(
                    mapOf(
                        "title" to title,
                        "status" to label,
                        "id" to (if (idCol >= 0) it.getLong(idCol).toString() else ""),
                        "progress" to progress.toString(),
                        "apk" to (mime == apkMime || title.endsWith(".apk", ignoreCase = true)).toString(),
                    ),
                )
            }
        }
        return items
    }

    /**
     * Opens a finished download. APKs go to the system installer; on Android 8+
     * the viewer is first sent to "Install unknown apps" if Aven is not allowed yet.
     */
    fun open(activity: Activity, id: Long) {
        val manager = manager(activity)
        val uri = manager.getUriForDownloadedFile(id) ?: return
        var mime = manager.getMimeTypeForDownloadedFile(id) ?: "*/*"
        if (uri.toString().endsWith(".apk", ignoreCase = true)) mime = apkMime
        if (mime == apkMime && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            val settings = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}"),
            )
            try {
                activity.startActivity(settings)
                Toast.makeText(activity, R.string.aven_install_allow, Toast.LENGTH_LONG).show()
                return
            } catch (_: Throwable) {
                // Some TV builds have no such screen; try the installer anyway.
            }
        }
        val view = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            activity.startActivity(view)
        } catch (error: Throwable) {
            Log.e(tag, "open download failed", error)
            Toast.makeText(activity, R.string.aven_open_failed, Toast.LENGTH_SHORT).show()
        }
    }

    fun remove(context: Context, id: Long) {
        manager(context).remove(id)
    }

    private fun manager(context: Context) =
        context.applicationContext.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
}
