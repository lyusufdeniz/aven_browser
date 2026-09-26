package com.avenbrowser.aven_browser

import android.content.Context

internal object AdBlockLists {
    @Volatile
    var hosts: Set<String> = emptySet()
        private set

    @Volatile
    private var loaded = false

    fun ensureLoaded(context: Context) {
        if (loaded) return
        synchronized(this) {
            if (loaded) return
            hosts = try {
                context.assets.open("adblock_hosts.txt").bufferedReader().useLines { lines ->
                    lines.map { it.trim().lowercase() }
                        .filter { it.isNotEmpty() && !it.startsWith("#") && !isAllowedHost(it) }
                        .toSet()
                }
            } catch (_: Exception) {
                emptySet()
            }
            loaded = true
        }
    }
}
