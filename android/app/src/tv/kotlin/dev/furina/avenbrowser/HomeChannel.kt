package dev.furina.avenbrowser

import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.tvprovider.media.tv.PreviewChannel
import androidx.tvprovider.media.tv.PreviewChannelHelper
import androidx.tvprovider.media.tv.PreviewProgram
import androidx.tvprovider.media.tv.TvContractCompat

/**
 * Android TV home screen row: "Aven · Bookmarks" (or recent pages when there
 * are no bookmarks). Each card reopens its page in Aven.
 */
internal object HomeChannel {
    private const val channelKey = "aven_links"
    private const val prefs = "aven_home_channel"
    private const val signatureKey = "signature"

    fun sync(context: Context, title: String, links: List<Map<String, String>>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        Thread {
            try {
                publish(context.applicationContext, title, links)
            } catch (error: Throwable) {
                // The launcher may not support channels (non-Google TV builds).
                Log.w("AvenHomeChannel", "publish failed", error)
            }
        }.start()
    }

    private fun publish(context: Context, title: String, links: List<Map<String, String>>) {
        val store = context.getSharedPreferences(prefs, Context.MODE_PRIVATE)
        val signature = title + "\n" + links.joinToString("\n") { "${it["title"]}|${it["url"]}" }
        val helper = PreviewChannelHelper(context)
        // Read our row directly: PreviewChannelHelper.getAllChannels() throws on
        // channels that were stored without a description.
        var channelId = findChannel(context)
        if (channelId != null && store.getString(signatureKey, null) == signature) return

        if (channelId == null) {
            val appLink = Uri.parse(openIntent(context, null).toUri(Intent.URI_INTENT_SCHEME))
            val built = PreviewChannel.Builder()
                .setDisplayName(title)
                .setDescription(title)
                .setInternalProviderId(channelKey)
                .setAppLinkIntentUri(appLink)
                .setLogo(appLogo(context))
                .build()
            // The first channel an app publishes shows up without asking.
            channelId = helper.publishDefaultChannel(built)
        } else {
            val values = ContentValues().apply {
                put(TvContractCompat.Channels.COLUMN_DISPLAY_NAME, title)
                put(TvContractCompat.Channels.COLUMN_DESCRIPTION, title)
            }
            context.contentResolver.update(
                TvContractCompat.buildChannelUri(channelId),
                values,
                null,
                null,
            )
        }

        clearPrograms(context, channelId)
        links.forEachIndexed { index, link ->
            val url = link["url"].orEmpty()
            if (url.isEmpty()) return@forEachIndexed
            val host = Uri.parse(url).host.orEmpty().removePrefix("www.")
            val program = PreviewProgram.Builder()
                .setChannelId(channelId)
                .setType(TvContractCompat.PreviewPrograms.TYPE_CLIP)
                .setTitle(link["title"].orEmpty().ifBlank { host })
                .setDescription(host)
                .setPosterArtAspectRatio(TvContractCompat.PreviewPrograms.ASPECT_RATIO_1_1)
                .setPosterArtUri(Uri.parse("https://www.google.com/s2/favicons?domain=$host&sz=256"))
                .setIntentUri(Uri.parse(openIntent(context, url).toUri(Intent.URI_INTENT_SCHEME)))
                .setInternalProviderId(url)
                .setWeight(links.size - index)
                .build()
            helper.publishPreviewProgram(program)
        }
        store.edit().putString(signatureKey, signature).apply()
        Log.i("AvenHomeChannel", "channel $channelId: ${countPrograms(context, channelId)} cards")
    }

    private fun findChannel(context: Context): Long? {
        context.contentResolver.query(
            TvContractCompat.Channels.CONTENT_URI,
            arrayOf(
                TvContractCompat.Channels._ID,
                TvContractCompat.Channels.COLUMN_INTERNAL_PROVIDER_ID,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(1) == channelKey) return cursor.getLong(0)
            }
        }
        return null
    }

    private fun countPrograms(context: Context, channelId: Long): Int {
        return context.contentResolver.query(
            TvContractCompat.buildPreviewProgramsUriForChannel(channelId),
            arrayOf(TvContractCompat.PreviewPrograms._ID),
            null,
            null,
            null,
        )?.use { it.count } ?: 0
    }

    private fun clearPrograms(context: Context, channelId: Long) {
        val uri = TvContractCompat.buildPreviewProgramsUriForChannel(channelId)
        val ids = mutableListOf<Long>()
        context.contentResolver.query(
            uri,
            arrayOf(TvContractCompat.PreviewPrograms._ID),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) ids.add(cursor.getLong(0))
        }
        for (id in ids) {
            context.contentResolver.delete(TvContractCompat.buildPreviewProgramUri(id), null, null)
        }
    }

    private fun openIntent(context: Context, url: String?): Intent {
        return Intent(Intent.ACTION_VIEW).apply {
            component = ComponentName(context, MainActivity::class.java)
            if (url != null) putExtra(MainActivity.EXTRA_OPEN_URL, url)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    private fun appLogo(context: Context): Bitmap {
        val drawable = ContextCompat.getDrawable(context, R.mipmap.ic_launcher)!!
        val size = 160
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(Canvas(bitmap))
        return bitmap
    }
}
