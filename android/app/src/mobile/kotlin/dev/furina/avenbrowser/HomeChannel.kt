package dev.furina.avenbrowser

import android.content.Context

/** Phone build: there is no TV home screen to publish to. */
internal object HomeChannel {
    fun sync(context: Context, title: String, links: List<Map<String, String>>) = Unit
}
