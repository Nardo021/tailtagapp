package com.josh.tailtag.data

internal data class StoredEntry(
    val id: String,
    val photos: List<String>,
    val registration: String,
    val airline: String,
    val location: String,
    val aircraftType: String?,
    val notes: String?,
    val timestamp: Long,
)

internal sealed class EntryDecodeResult {
    data class Entries(val entries: List<StoredEntry>) : EntryDecodeResult()
    data object Corrupt : EntryDecodeResult()
    data object MissingFields : EntryDecodeResult()
}

/**
 * Reads and writes the existing `entries` JSON array.
 * Parsing failures stay failures — they are never reported as an empty list.
 */
internal object EntryJson {
    fun encode(entries: List<StoredEntry>): String {
        val builder = StringBuilder()
        builder.append('[')
        entries.forEachIndexed { index, entry ->
            if (index > 0) builder.append(',')
            builder.append('{')
            appendStringField(builder, "id", entry.id)
            builder.append(',')
            builder.append("\"photos\":")
            builder.append('[')
            entry.photos.forEachIndexed { photoIndex, photo ->
                if (photoIndex > 0) builder.append(',')
                builder.append('"')
                builder.append(escape(photo))
                builder.append('"')
            }
            builder.append(']')
            builder.append(',')
            appendStringField(builder, "registration", entry.registration)
            builder.append(',')
            appendStringField(builder, "airline", entry.airline)
            builder.append(',')
            appendStringField(builder, "location", entry.location)
            builder.append(',')
            appendStringField(builder, "aircraftType", entry.aircraftType.orEmpty())
            builder.append(',')
            appendStringField(builder, "notes", entry.notes.orEmpty())
            builder.append(',')
            builder.append("\"timestamp\":")
            builder.append(entry.timestamp)
            builder.append('}')
        }
        builder.append(']')
        return builder.toString()
    }

    fun decode(raw: String): EntryDecodeResult {
        val parser = JsonParser(raw)
        val value = parser.parseValue() ?: return EntryDecodeResult.Corrupt
        if (!parser.isFinished()) return EntryDecodeResult.Corrupt
        val array = value as? JsonArray ?: return EntryDecodeResult.Corrupt
        val entries = ArrayList<StoredEntry>(array.items.size)
        val seenIds = HashSet<String>()
        for (item in array.items) {
            val objectValue = item as? JsonObject ?: return EntryDecodeResult.MissingFields
            val id = objectValue.string("id") ?: return EntryDecodeResult.MissingFields
            if (id.isBlank() || !seenIds.add(id)) return EntryDecodeResult.MissingFields
            if (!objectValue.has("registration") || !objectValue.has("airline") || !objectValue.has("location") || !objectValue.has("timestamp") || !objectValue.has("photos")) {
                return EntryDecodeResult.MissingFields
            }
            val registration = objectValue.string("registration") ?: return EntryDecodeResult.MissingFields
            val airline = objectValue.string("airline") ?: return EntryDecodeResult.MissingFields
            val location = objectValue.string("location") ?: return EntryDecodeResult.MissingFields
            val timestamp = objectValue.long("timestamp") ?: return EntryDecodeResult.MissingFields
            val photosValue = objectValue.fields["photos"] as? JsonArray ?: return EntryDecodeResult.MissingFields
            val photos = ArrayList<String>(photosValue.items.size)
            for (photo in photosValue.items) {
                val path = (photo as? JsonString)?.value ?: return EntryDecodeResult.MissingFields
                photos.add(path)
            }
            entries.add(
                StoredEntry(
                    id = id,
                    photos = photos,
                    registration = registration,
                    airline = airline,
                    location = location,
                    aircraftType = objectValue.string("aircraftType")?.takeUnless { it.isBlank() },
                    notes = objectValue.string("notes")?.takeUnless { it.isBlank() },
                    timestamp = timestamp,
                ),
            )
        }
        return EntryDecodeResult.Entries(entries)
    }

    private fun appendStringField(builder: StringBuilder, name: String, value: String) {
        builder.append('"')
        builder.append(name)
        builder.append("\":\"")
        builder.append(escape(value))
        builder.append('"')
    }

    private fun escape(value: String): String {
        val builder = StringBuilder(value.length)
        for (character in value) {
            when (character) {
                '\\' -> builder.append("\\\\")
                '"' -> builder.append("\\\"")
                '\n' -> builder.append("\\n")
                '\r' -> builder.append("\\r")
                '\t' -> builder.append("\\t")
                else -> if (character.code < 0x20) {
                    builder.append("\\u")
                    builder.append(character.code.toString(16).padStart(4, '0'))
                } else {
                    builder.append(character)
                }
            }
        }
        return builder.toString()
    }
}

private class JsonParser(private val raw: String) {
    private var index = 0

    fun isFinished(): Boolean {
        skipWhitespace()
        return index >= raw.length
    }

    fun parseValue(): JsonValue? {
        skipWhitespace()
        if (index >= raw.length) return null
        return when (raw[index]) {
            '{' -> parseObject()
            '[' -> parseArray()
            '"' -> JsonString(parseString() ?: return null)
            '-', in '0'..'9' -> parseNumber()
            else -> null
        }
    }

    private fun parseObject(): JsonObject? {
        index++
        val fields = LinkedHashMap<String, JsonValue>()
        skipWhitespace()
        if (consume('}')) return JsonObject(fields)
        while (index < raw.length) {
            skipWhitespace()
            if (raw.getOrNull(index) != '"') return null
            val key = parseString() ?: return null
            skipWhitespace()
            if (!consume(':')) return null
            val value = parseValue() ?: return null
            fields[key] = value
            skipWhitespace()
            when {
                consume(',') -> continue
                consume('}') -> return JsonObject(fields)
                else -> return null
            }
        }
        return null
    }

    private fun parseArray(): JsonArray? {
        index++
        val items = ArrayList<JsonValue>()
        skipWhitespace()
        if (consume(']')) return JsonArray(items)
        while (index < raw.length) {
            val value = parseValue() ?: return null
            items.add(value)
            skipWhitespace()
            when {
                consume(',') -> continue
                consume(']') -> return JsonArray(items)
                else -> return null
            }
        }
        return null
    }

    private fun parseString(): String? {
        if (!consume('"')) return null
        val builder = StringBuilder()
        while (index < raw.length) {
            val character = raw[index]
            index++
            when (character) {
                '"' -> return builder.toString()
                '\\' -> {
                    if (index >= raw.length) return null
                    when (val escaped = raw[index++]) {
                        '"', '\\', '/' -> builder.append(escaped)
                        'b' -> builder.append('\b')
                        'f' -> builder.append('\u000C')
                        'n' -> builder.append('\n')
                        'r' -> builder.append('\r')
                        't' -> builder.append('\t')
                        'u' -> {
                            if (index + 4 > raw.length) return null
                            val hex = raw.substring(index, index + 4)
                            index += 4
                            val code = hex.toIntOrNull(16) ?: return null
                            builder.append(code.toChar())
                        }
                        else -> return null
                    }
                }
                else -> if (character.code < 0x20) return null else builder.append(character)
            }
        }
        return null
    }

    private fun parseNumber(): JsonNumber? {
        val start = index
        if (raw.getOrNull(index) == '-') index++
        if (index >= raw.length || !raw[index].isDigit()) return null
        if (raw[index] == '0') {
            index++
        } else {
            while (index < raw.length && raw[index].isDigit()) index++
        }
        if (raw.getOrNull(index) == '.') return null
        if (raw.getOrNull(index) == 'e' || raw.getOrNull(index) == 'E') return null
        val text = raw.substring(start, index)
        val longValue = text.toLongOrNull() ?: return null
        return JsonNumber(longValue)
    }

    private fun skipWhitespace() {
        while (index < raw.length && raw[index].isWhitespace()) index++
    }

    private fun consume(expected: Char): Boolean {
        if (raw.getOrNull(index) != expected) return false
        index++
        return true
    }
}

private sealed class JsonValue
private class JsonObject(val fields: Map<String, JsonValue>) : JsonValue() {
    fun has(name: String): Boolean = fields.containsKey(name)
    fun string(name: String): String? = (fields[name] as? JsonString)?.value
    fun long(name: String): Long? = (fields[name] as? JsonNumber)?.value
}
private class JsonArray(val items: List<JsonValue>) : JsonValue()
private class JsonString(val value: String) : JsonValue()
private class JsonNumber(val value: Long) : JsonValue()
