package dev.furina.avenbrowser

import android.content.Context
import android.util.Log
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * EasyList network and site-specific hiding rules, used next to the hosts
 * list. The list is downloaded (not bundled) and refreshed weekly; until the
 * first download finishes nothing extra is blocked.
 *
 * Supported: `||host^`, `|start`, `end|`, `*`, `^`, `@@` exceptions and the
 * `third-party` / `domain=` / basic type options. Rules with options we do
 * not understand (redirects, scriptlets, popup, csp…) are skipped rather
 * than guessed, so they cannot break pages.
 */
internal object FilterLists {
    private const val listUrl = "https://easylist.to/easylist/easylist.txt"
    private const val fileName = "easylist.txt"
    private const val maxAgeMs = 7L * 24 * 60 * 60 * 1000

    @Volatile
    private var engine: FilterEngine? = null

    @Volatile
    private var started = false

    fun ensureLoaded(context: Context) {
        if (started) return
        synchronized(this) {
            if (started) return
            started = true
        }
        val app = context.applicationContext
        Thread({ load(app) }, "aven-filter-lists").apply {
            priority = Thread.MIN_PRIORITY
            start()
        }
    }

    /** True when EasyList blocks [url] loaded by a page on [pageHost]. */
    fun blocks(url: String, host: String, pageHost: String?, thirdParty: Boolean): Boolean {
        return engine?.blocks(url.lowercase(), host, pageHost, thirdParty) == true
    }

    /** CSS hiding rules EasyList has for this site (empty when none). */
    fun hidingCss(pageHost: String?): String {
        val current = engine ?: return ""
        if (pageHost.isNullOrEmpty()) return ""
        val selectors = current.selectorsFor(pageHost)
        if (selectors.isEmpty()) return ""
        return selectors.joinToString(",") + cosmeticHideRule
    }

    private fun load(context: Context) {
        val file = File(context.filesDir, fileName)
        try {
            if (file.exists()) engine = FilterEngine.parse(file.readLines())
            val stale = !file.exists() || System.currentTimeMillis() - file.lastModified() > maxAgeMs
            if (stale && download(file)) engine = FilterEngine.parse(file.readLines())
            val ready = engine
            if (ready != null) Log.i("AvenFilters", "EasyList: ${ready.summary()}")
        } catch (error: Throwable) {
            Log.w("AvenFilters", "EasyList load failed", error)
        }
    }

    private fun download(target: File): Boolean {
        val connection = URL(listUrl).openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 10_000
            connection.readTimeout = 20_000
            if (connection.responseCode != 200) return false
            val temp = File(target.parentFile, "$fileName.part")
            connection.inputStream.use { input -> temp.outputStream().use { input.copyTo(it) } }
            // A truncated download must not replace a good copy.
            if (temp.length() < 100_000 || !temp.renameTo(target)) {
                temp.delete()
                return false
            }
            true
        } catch (_: Throwable) {
            false
        } finally {
            connection.disconnect()
        }
    }
}

internal class FilterEngine private constructor(
    private val blockByHost: Map<String, List<NetRule>>,
    private val blockByToken: Map<String, List<NetRule>>,
    private val blockLoose: List<NetRule>,
    private val allowByHost: Map<String, List<NetRule>>,
    private val allowByToken: Map<String, List<NetRule>>,
    private val allowLoose: List<NetRule>,
    private val hiding: Map<String, List<String>>,
) {
    fun summary(): String {
        val net = blockByHost.values.sumOf { it.size } + blockByToken.values.sumOf { it.size } + blockLoose.size
        return "$net block rules, ${hiding.size} sites with hiding rules"
    }

    fun blocks(url: String, host: String, pageHost: String?, thirdParty: Boolean): Boolean {
        val type = guessType(url)
        if (!matches(url, host, pageHost, thirdParty, type, blockByHost, blockByToken, blockLoose)) {
            return false
        }
        return !matches(url, host, pageHost, thirdParty, type, allowByHost, allowByToken, allowLoose)
    }

    fun selectorsFor(pageHost: String): List<String> {
        val out = ArrayList<String>()
        forEachParent(pageHost) { name -> hiding[name]?.let { out.addAll(it) } }
        return if (out.size > 400) out.subList(0, 400) else out
    }

    private fun matches(
        url: String,
        host: String,
        pageHost: String?,
        thirdParty: Boolean,
        type: String?,
        byHost: Map<String, List<NetRule>>,
        byToken: Map<String, List<NetRule>>,
        loose: List<NetRule>,
    ): Boolean {
        var hit = false
        forEachParent(host) { name ->
            if (!hit) hit = byHost[name]?.any { it.applies(url, pageHost, thirdParty, type) } == true
        }
        if (hit) return true
        for (token in tokens(url)) {
            val rules = byToken[token] ?: continue
            if (rules.any { it.applies(url, pageHost, thirdParty, type) }) return true
        }
        return loose.any { it.applies(url, pageHost, thirdParty, type) }
    }

    companion object {
        private val typeOptions = mapOf(
            "script" to "script",
            "image" to "image",
            "stylesheet" to "stylesheet",
            "css" to "stylesheet",
            "font" to "font",
            "media" to "media",
            "xmlhttprequest" to "xhr",
            "xhr" to "xhr",
            "subdocument" to "frame",
            "frame" to "frame",
            "object" to "other",
            "ping" to "other",
            "websocket" to "other",
            "other" to "other",
        )

        fun parse(lines: List<String>): FilterEngine {
            val blockByHost = HashMap<String, MutableList<NetRule>>()
            val blockByToken = HashMap<String, MutableList<NetRule>>()
            val blockLoose = ArrayList<NetRule>()
            val allowByHost = HashMap<String, MutableList<NetRule>>()
            val allowByToken = HashMap<String, MutableList<NetRule>>()
            val allowLoose = ArrayList<NetRule>()
            val hiding = HashMap<String, MutableList<String>>()

            for (raw in lines) {
                val line = raw.trim()
                if (line.isEmpty() || line.startsWith("!") || line.startsWith("[")) continue
                if (line.contains("##") || line.contains("#@#") || line.contains("#?#") ||
                    line.contains("#$#") || line.contains("#%#")
                ) {
                    parseHiding(line, hiding)
                    continue
                }
                val allow = line.startsWith("@@")
                val rule = parseNet(if (allow) line.substring(2) else line) ?: continue
                val (byHost, byToken, loose) = if (allow) {
                    Triple(allowByHost, allowByToken, allowLoose)
                } else {
                    Triple(blockByHost, blockByToken, blockLoose)
                }
                when {
                    rule.hostKey != null -> byHost.getOrPut(rule.hostKey) { ArrayList(1) }.add(rule)
                    rule.token != null -> byToken.getOrPut(rule.token) { ArrayList(1) }.add(rule)
                    else -> loose.add(rule)
                }
            }
            return FilterEngine(blockByHost, blockByToken, blockLoose, allowByHost, allowByToken, allowLoose, hiding)
        }

        /** Site-specific `a.com,b.com##selector` only; generic and procedural rules are skipped. */
        private fun parseHiding(line: String, hiding: HashMap<String, MutableList<String>>) {
            val at = line.indexOf("##")
            if (at <= 0) return
            val selector = line.substring(at + 2)
            if (selector.isEmpty() || selector.startsWith("+js") || selector.contains(":-abp-") ||
                selector.contains(":has-text(") || selector.contains(":upward(") ||
                selector.contains(":remove(") || selector.contains(":style(") ||
                selector.contains(":matches-") || selector.contains(":xpath(") ||
                selector.contains(":min-text-length(") || selector.contains(":watch-attr(") ||
                selector.contains(":others(") || selector.startsWith("^")
            ) {
                return
            }
            for (domain in line.substring(0, at).split(',')) {
                val name = domain.trim().lowercase()
                if (name.isEmpty() || name.startsWith("~") || name.contains('*') || name.contains('/')) continue
                hiding.getOrPut(name) { ArrayList(2) }.add(selector)
            }
        }

        private fun parseNet(text: String): NetRule? {
            var pattern = text
            var options = ""
            val dollar = text.lastIndexOf('$')
            if (dollar >= 0 && !text.startsWith("/")) {
                pattern = text.substring(0, dollar)
                options = text.substring(dollar + 1)
            }
            if (pattern.length > 1 && pattern.startsWith("/") && pattern.endsWith("/")) return null
            pattern = pattern.lowercase()
            if (pattern.isEmpty() || pattern == "*" || pattern == "|" || pattern == "||") return null

            var thirdParty: Boolean? = null
            val types = HashSet<String>()
            val notTypes = HashSet<String>()
            val include = ArrayList<String>()
            val exclude = ArrayList<String>()
            if (options.isNotEmpty()) {
                for (rawOption in options.split(',')) {
                    val option = rawOption.trim().lowercase()
                    val name = option.substringBefore('=').removePrefix("~")
                    val negated = option.startsWith("~")
                    when {
                        name == "third-party" || name == "3p" -> thirdParty = !negated
                        name == "first-party" || name == "1p" -> thirdParty = negated
                        name == "domain" || name == "from" -> {
                            for (entry in option.substringAfter('=').split('|')) {
                                if (entry.startsWith("~")) exclude.add(entry.substring(1)) else if (entry.isNotEmpty()) include.add(entry)
                            }
                        }
                        name == "important" -> Unit
                        typeOptions.containsKey(name) -> {
                            val type = typeOptions.getValue(name)
                            if (negated) notTypes.add(type) else types.add(type)
                        }
                        // Redirects, scriptlets, popups and anything unknown are skipped.
                        else -> return null
                    }
                }
            }
            // Wildcard domain entries (example.*) are not supported.
            if (include.any { it.contains('*') } || exclude.any { it.contains('*') }) return null

            val hostKey = hostOnly(pattern)
            val token = if (hostKey == null) bestToken(pattern) else null
            return NetRule(pattern, hostKey, token, thirdParty, types, notTypes, include, exclude)
        }

        /** `||ads.example.com^` (optionally with a trailing `|`) → `ads.example.com`. */
        private fun hostOnly(pattern: String): String? {
            if (!pattern.startsWith("||")) return null
            var rest = pattern.substring(2)
            if (rest.endsWith("^|")) rest = rest.dropLast(2) else if (rest.endsWith("^")) rest = rest.dropLast(1) else return null
            if (rest.isEmpty() || rest.any { !(it.isLetterOrDigit() || it == '.' || it == '-') }) return null
            return rest
        }

        /**
         * Longest literal run that is guaranteed to be a whole URL token: it
         * must sit between separators in the pattern, never at an unanchored
         * edge or next to '*', where the URL token could be longer.
         */
        private fun bestToken(pattern: String): String? {
            var best: String? = null
            var i = 0
            while (i < pattern.length) {
                if (!isTokenChar(pattern[i])) {
                    i++
                    continue
                }
                val start = i
                while (i < pattern.length && isTokenChar(pattern[i])) i++
                val before = if (start == 0) null else pattern[start - 1]
                val after = if (i == pattern.length) null else pattern[i]
                val candidate = pattern.substring(start, i)
                val current = best
                if (before != null && before != '*' && after != null && after != '*' &&
                    candidate.length >= 3 && (current == null || candidate.length > current.length)
                ) {
                    best = candidate
                }
            }
            return best
        }

        internal fun isTokenChar(c: Char) = c in 'a'..'z' || c in '0'..'9' || c == '%'

        internal fun tokens(url: String): Set<String> {
            val out = HashSet<String>()
            var start = -1
            for (i in url.indices) {
                if (isTokenChar(url[i])) {
                    if (start < 0) start = i
                } else if (start >= 0) {
                    if (i - start >= 3) out.add(url.substring(start, i))
                    start = -1
                }
            }
            if (start >= 0 && url.length - start >= 3) out.add(url.substring(start))
            return out
        }

        internal inline fun forEachParent(host: String, action: (String) -> Unit) {
            var cursor = host
            while (true) {
                action(cursor)
                val dot = cursor.indexOf('.')
                if (dot <= 0 || dot >= cursor.length - 1) break
                cursor = cursor.substring(dot + 1)
            }
        }

        private fun guessType(url: String): String? {
            val path = url.substringBefore('?').substringBefore('#')
            return when {
                path.endsWith(".js") || path.endsWith(".mjs") -> "script"
                path.endsWith(".css") -> "stylesheet"
                path.endsWith(".png") || path.endsWith(".jpg") || path.endsWith(".jpeg") ||
                    path.endsWith(".gif") || path.endsWith(".webp") || path.endsWith(".svg") ||
                    path.endsWith(".avif") || path.endsWith(".ico") -> "image"
                path.endsWith(".woff") || path.endsWith(".woff2") || path.endsWith(".ttf") ||
                    path.endsWith(".otf") -> "font"
                path.endsWith(".mp4") || path.endsWith(".webm") || path.endsWith(".mp3") -> "media"
                path.endsWith(".html") || path.endsWith(".htm") -> "frame"
                else -> null
            }
        }
    }
}

internal class NetRule(
    private val pattern: String,
    val hostKey: String?,
    val token: String?,
    private val thirdParty: Boolean?,
    private val types: Set<String>,
    private val notTypes: Set<String>,
    private val include: List<String>,
    private val exclude: List<String>,
) {
    @Volatile
    private var regex: Regex? = null

    fun applies(url: String, pageHost: String?, isThirdParty: Boolean, type: String?): Boolean {
        if (thirdParty != null && thirdParty != isThirdParty) return false
        // Unknown request type: type-limited rules still apply (ad URLs rarely
        // change type), but an explicit "not this type" never blocks blindly.
        if (type != null) {
            if (types.isNotEmpty() && type !in types) return false
            if (type in notTypes) return false
        } else if (notTypes.isNotEmpty() && types.isEmpty()) {
            return false
        }
        if (include.isNotEmpty() || exclude.isNotEmpty()) {
            val page = pageHost ?: return false
            if (exclude.any { page == it || page.endsWith(".$it") }) return false
            if (include.isNotEmpty() && include.none { page == it || page.endsWith(".$it") }) return false
        }
        if (hostKey != null) return true
        val compiled = regex ?: toRegex(pattern).also { regex = it }
        return compiled.containsMatchIn(url)
    }

    private fun toRegex(pattern: String): Regex {
        val out = StringBuilder()
        var body = pattern
        when {
            body.startsWith("||") -> {
                out.append("^[a-z][a-z0-9+.-]*:(?://)?(?:[^/?#]*\\.)?")
                body = body.substring(2)
            }
            body.startsWith("|") -> {
                out.append('^')
                body = body.substring(1)
            }
        }
        val endAnchor = body.endsWith("|")
        if (endAnchor) body = body.dropLast(1)
        for (c in body) {
            when (c) {
                '*' -> out.append(".*")
                '^' -> out.append("(?:[^a-z0-9_.%-]|$)")
                else -> if (c.isLetterOrDigit()) out.append(c) else out.append('\\').append(c)
            }
        }
        if (endAnchor) out.append('$')
        return Regex(out.toString())
    }
}
