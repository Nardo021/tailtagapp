package com.josh.tailtag.aviation

import java.text.Normalizer
import java.util.Locale

internal object AviationText {
    private val whitespace = setOf(
        '\t', '\n', '\u000B', '\u000C', '\r',
        '\u001C', '\u001D', '\u001E', '\u001F',
        ' ', '\u0085', '\u00A0', '\u1680',
        '\u2000', '\u2001', '\u2002', '\u2003', '\u2004',
        '\u2005', '\u2006', '\u2007', '\u2008', '\u2009', '\u200A',
        '\u2028', '\u2029', '\u202F', '\u205F', '\u3000',
    )
    private val hyphens = setOf('-', '‐', '‑', '‒', '–', '—', '_', '/', '\\')

    fun normalize(value: String?): String {
        if (value.isNullOrEmpty()) return ""
        val folded = fold(stripMarks(value))
        val replaced = buildString(folded.length) {
            folded.codePoints().forEach { codePoint ->
                if (codePoint <= Char.MAX_VALUE.code && hyphens.contains(codePoint.toChar())) {
                    append(' ')
                } else {
                    appendCodePoint(codePoint)
                }
            }
        }
        return collapse(replaced)
    }

    fun compact(normalized: String): String = normalized.replace(" ", "")

    fun isAsciiAlphanumeric(value: String): Boolean {
        return value.isNotEmpty() && value.all { char -> char in 'a'..'z' || char in '0'..'9' }
    }

    private fun fold(value: String): String {
        val builder = StringBuilder()
        value.codePoints().forEach { codePoint ->
            val mapped = CaseFoldExceptions.values[codePoint]
            if (mapped != null) {
                builder.append(mapped)
            } else {
                builder.append(String(Character.toChars(codePoint)).lowercase(Locale.ROOT))
            }
        }
        return stripMarks(builder.toString())
    }

    private fun stripMarks(value: String): String {
        val decomposed = Normalizer.normalize(value, Normalizer.Form.NFD)
        return buildString(decomposed.length) {
            decomposed.codePoints().forEach { codePoint ->
                if (!isCombiningMark(codePoint)) appendCodePoint(codePoint)
            }
        }
    }

    private fun collapse(value: String): String {
        val parts = ArrayList<String>()
        val current = StringBuilder()
        value.codePoints().forEach { codePoint ->
            if (codePoint <= Char.MAX_VALUE.code && whitespace.contains(codePoint.toChar())) {
                if (current.isNotEmpty()) {
                    parts.add(current.toString())
                    current.setLength(0)
                }
            } else {
                current.appendCodePoint(codePoint)
            }
        }
        if (current.isNotEmpty()) parts.add(current.toString())
        return parts.joinToString(" ")
    }

    private fun isCombiningMark(codePoint: Int): Boolean {
        return when (Character.getType(codePoint)) {
            Character.NON_SPACING_MARK.toInt(),
            Character.ENCLOSING_MARK.toInt(),
            Character.COMBINING_SPACING_MARK.toInt(),
            -> true
            else -> false
        }
    }
}
