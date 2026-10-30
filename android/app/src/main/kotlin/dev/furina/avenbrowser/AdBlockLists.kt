package dev.furina.avenbrowser

import android.content.Context

/**
 * Bundled hosts list (~250k names). It loads on a background thread so app
 * start is not held up, and is kept as sorted 64-bit hashes (~2 MB) instead
 * of a String set (~30 MB) — that matters on low-memory TV boxes.
 */
internal object AdBlockLists {
    @Volatile
    private var hashes = LongArray(0)

    @Volatile
    private var started = false

    fun ensureLoaded(context: Context) {
        if (started) return
        synchronized(this) {
            if (started) return
            started = true
        }
        val app = context.applicationContext
        Thread({ hashes = read(app) }, "aven-adblock-list").apply {
            priority = Thread.MIN_PRIORITY
            start()
        }
    }

    /** False until the list has loaded; the first page may slip through. */
    fun contains(host: String): Boolean {
        val table = hashes
        return table.isNotEmpty() && table.binarySearch(hash(host)) >= 0
    }

    private fun read(context: Context): LongArray {
        return try {
            var out = LongArray(262_144)
            var size = 0
            context.assets.open("adblock_hosts.txt").bufferedReader().useLines { lines ->
                for (line in lines) {
                    var t = line.trim().lowercase()
                    if (t.startsWith("0.0.0.0 ")) t = t.removePrefix("0.0.0.0 ").trim()
                    if (t.startsWith("127.0.0.1 ")) t = t.removePrefix("127.0.0.1 ").trim()
                    if (t.isEmpty() || t.startsWith("#") || isAllowedHost(t)) continue
                    if (size == out.size) out = out.copyOf(size * 2)
                    out[size++] = hash(t)
                }
            }
            out = out.copyOf(size)
            out.sort()
            out
        } catch (_: Exception) {
            LongArray(0)
        }
    }

    /** FNV-1a 64; collisions across ~250k names are vanishingly unlikely. */
    private fun hash(text: String): Long {
        var h = -0x340d631b7bdddcdbL
        for (ch in text) {
            h = h xor ch.code.toLong()
            h *= 0x100000001b3L
        }
        return h
    }
}
