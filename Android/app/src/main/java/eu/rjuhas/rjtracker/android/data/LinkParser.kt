package eu.rjuhas.rjtracker.android.data

import android.net.Uri

data class ParsedLink(val kind: LinkKind, val baseUrl: String, val token: String) {
    val id: String get() = "${kind.name.lowercase()}:$token"
}

/** Accepts full links, links inside a pasted message, rjtracker:// links and bare paths. */
object LinkParser {
    private val pattern = Regex("""(https?://[^\s/]+)?/?(school|shared)/([A-Za-z0-9_-]{8,160})""")

    fun parse(raw: String?, defaultBase: String): ParsedLink? {
        val text = raw?.trim().orEmpty()
        if (text.isEmpty()) return null
        val normalized = if (text.startsWith("rjtracker://")) {
            val uri = Uri.parse(text)
            val host = uri.getQueryParameter("server")?.trimEnd('/') ?: defaultBase
            "$host/${uri.host}${uri.path}"
        } else text
        val match = pattern.find(normalized) ?: return null
        val base = (match.groupValues[1].ifBlank { defaultBase }).trimEnd('/')
        val kind = if (match.groupValues[2] == "school") LinkKind.SCHOOL else LinkKind.GUEST
        if (kind == LinkKind.SCHOOL && match.groupValues[3].length < 20) return null
        return ParsedLink(kind, base, match.groupValues[3])
    }
}
