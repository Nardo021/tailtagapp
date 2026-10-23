package com.josh.tailtag.aviation

internal class IndexedRecord<T>(
    val record: T,
    val recordId: String,
    val codesNorm: List<String>,
    val codesCompact: List<String>,
    val namesNorm: List<String>,
    val namesCompact: List<String>,
    val identifierCompacts: Set<String>,
)

class AviationSearchIndex<T>(records: List<T>, id: (T) -> String, codes: (T) -> List<String>, names: (T) -> List<String>) {
    private val entries: List<IndexedRecord<T>> = records.map { record ->
        val recordId = id(record)
        val localId = recordId.substringAfter(':', recordId)
        val codesNorm = ArrayList<String>()
        val codesCompact = ArrayList<String>()
        val codeValues = codes(record).toMutableList()
        if (localId != recordId) codeValues.add(localId)
        for (value in codeValues) {
            val normalized = AviationText.normalize(value)
            val compact = AviationText.compact(normalized)
            if (compact.isNotEmpty()) {
                codesNorm.add(normalized)
                codesCompact.add(compact)
            }
        }
        val namesNorm = ArrayList<String>()
        val namesCompact = ArrayList<String>()
        for (value in names(record)) {
            val normalized = AviationText.normalize(value)
            if (normalized.isNotEmpty()) {
                namesNorm.add(normalized)
                namesCompact.add(AviationText.compact(normalized))
            }
        }
        val identifierCompacts = listOf(recordId, localId).mapNotNull { value ->
            AviationText.compact(AviationText.normalize(value)).ifEmpty { null }
        }.toSet()
        IndexedRecord(record, recordId, codesNorm, codesCompact, namesNorm, namesCompact, identifierCompacts)
    }
    private val exactCodes: Map<String, List<Int>>
    private val prefixBuckets: Map<String, List<Int>>
    private val trigramBuckets: Map<String, List<Int>>

    init {
        val exact = HashMap<String, ArrayList<Int>>()
        val prefixes = HashMap<String, ArrayList<Int>>()
        val trigrams = HashMap<String, ArrayList<Int>>()
        for ((index, entry) in entries.withIndex()) {
            val seenExact = HashSet<String>()
            val seenPrefix = HashSet<String>()
            val seenTrigram = HashSet<String>()
            for (codeCompact in entry.codesCompact) {
                if (seenExact.add(codeCompact)) exact.getOrPut(codeCompact) { ArrayList() }.add(index)
                if (codeCompact.length >= 2) {
                    val key = codeCompact.substring(0, 2)
                    if (seenPrefix.add(key)) prefixes.getOrPut(key) { ArrayList() }.add(index)
                }
                if (codeCompact !in entry.identifierCompacts) addTrigrams(codeCompact, index, trigrams, seenTrigram)
            }
            for (nameCompact in entry.namesCompact) {
                if (nameCompact.length >= 2) {
                    val key = nameCompact.substring(0, 2)
                    if (seenPrefix.add(key)) prefixes.getOrPut(key) { ArrayList() }.add(index)
                }
                addTrigrams(nameCompact, index, trigrams, seenTrigram)
            }
        }
        exactCodes = exact
        prefixBuckets = prefixes
        trigramBuckets = trigrams
    }

    fun exactCodeCount(query: String): Int {
        val compact = AviationText.compact(AviationText.normalize(query))
        return exactCodes[compact]?.size ?: 0
    }

    fun search(query: String, limit: Int): List<T> {
        require(limit >= 0) { "limit must be >= 0" }
        val normalized = AviationText.normalize(query)
        val compact = AviationText.compact(normalized)
        if (limit == 0 || normalized.isEmpty() || compact.length < 2) return emptyList()
        val shortCode = compact.length <= 3 && AviationText.isAsciiAlphanumeric(compact)
        val candidates = HashSet<Int>()
        prefixBuckets[compact.substring(0, 2)]?.let(candidates::addAll)
        if (compact.length >= 3) trigramBuckets[compact.substring(0, 3)]?.let(candidates::addAll)
        val ranked = ArrayList<Triple<Int, String, T>>()
        for (index in candidates) {
            val entry = entries[index]
            val tier = tier(entry, normalized, compact, shortCode) ?: continue
            ranked.add(Triple(tier, entry.recordId, entry.record))
        }
        ranked.sortWith(compareBy({ it.first }, { it.second }))
        return ranked.take(limit).map { it.third }
    }

    private fun tier(entry: IndexedRecord<T>, queryNorm: String, queryCompact: String, shortCode: Boolean): Int? {
        var best: Int? = null
        for (index in entry.codesNorm.indices) {
            val codeNorm = entry.codesNorm[index]
            val codeCompact = entry.codesCompact[index]
            val tier = if (codeCompact == queryCompact || codeNorm == queryNorm) {
                return 0
            } else if (queryCompact.length >= 2 && codeCompact.startsWith(queryCompact)) {
                2
            } else if (codeCompact !in entry.identifierCompacts && queryCompact.length >= 4 && codeCompact.contains(queryCompact)) {
                4
            } else {
                continue
            }
            if (best == null || tier < best) best = tier
        }
        for (index in entry.namesNorm.indices) {
            val nameNorm = entry.namesNorm[index]
            val nameCompact = entry.namesCompact[index]
            val tier = if (nameNorm == queryNorm || nameCompact == queryCompact) {
                1
            } else if (nameNorm.startsWith(queryNorm) || (queryCompact.length >= 2 && nameCompact.startsWith(queryCompact))) {
                3
            } else if (!shortCode && queryCompact.length >= 3 && (nameNorm.contains(queryNorm) || nameCompact.contains(queryCompact))) {
                4
            } else {
                continue
            }
            if (best == null || tier < best) best = tier
        }
        return best
    }

    private fun addTrigrams(value: String, index: Int, buckets: MutableMap<String, ArrayList<Int>>, seen: MutableSet<String>) {
        if (value.length < 3) return
        for (offset in 0..value.length - 3) {
            val tri = value.substring(offset, offset + 3)
            if (seen.add(tri)) buckets.getOrPut(tri) { ArrayList() }.add(index)
        }
    }
}

sealed class AviationQueryResolution<out T> {
    data object Blank : AviationQueryResolution<Nothing>()
    data class Matches<T>(val records: List<T>) : AviationQueryResolution<T>()
    data class Ambiguous<T>(val records: List<T>) : AviationQueryResolution<T>()
    data class Unmatched(val text: String) : AviationQueryResolution<Nothing>()

    val kindName: String
        get() = when (this) {
            Blank -> "blank"
            is Matches -> "matches"
            is Ambiguous -> "ambiguous"
            is Unmatched -> "unmatched"
        }
}

private val aviationWhitespace = charArrayOf(
    '\t', '\n', '\u000B', '\u000C', '\r',
    '\u001C', '\u001D', '\u001E', '\u001F',
    ' ', '\u0085', '\u00A0', '\u1680',
    '\u2000', '\u2001', '\u2002', '\u2003', '\u2004',
    '\u2005', '\u2006', '\u2007', '\u2008', '\u2009', '\u200A',
    '\u2028', '\u2029', '\u202F', '\u205F', '\u3000',
).toSet()

fun <T> resolveAviationQuery(query: String, matches: List<T>, exactCodeCount: Int = 0): AviationQueryResolution<T> {
    if (AviationText.normalize(query).isEmpty()) return AviationQueryResolution.Blank
    if (matches.isNotEmpty()) {
        if (exactCodeCount > 1) return AviationQueryResolution.Ambiguous(matches)
        return AviationQueryResolution.Matches(matches)
    }
    return AviationQueryResolution.Unmatched(query.trim { aviationWhitespace.contains(it) })
}
