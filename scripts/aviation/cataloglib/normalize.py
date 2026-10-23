"""Locale-independent search-text normalization.

The same steps are implemented in Swift (CFStringFold) and Kotlin.
Whitespace is the Python ``str.isspace()`` set, not Java's narrower
``Character.isWhitespace``.
"""

from __future__ import annotations

import unicodedata

# Python str.isspace() code points. Kept explicit so other languages can match.
WHITESPACE = frozenset(
    {
        "\t",
        "\n",
        "\v",
        "\f",
        "\r",
        "\x1c",
        "\x1d",
        "\x1e",
        "\x1f",
        " ",
        "\u0085",
        "\u00a0",
        "\u1680",
        "\u2000",
        "\u2001",
        "\u2002",
        "\u2003",
        "\u2004",
        "\u2005",
        "\u2006",
        "\u2007",
        "\u2008",
        "\u2009",
        "\u200a",
        "\u2028",
        "\u2029",
        "\u202f",
        "\u205f",
        "\u3000",
    }
)

HYPHENS = frozenset("-‐‑‒–—_/\\")

NULL_CODE_MARKERS = frozenset(
    {
        "",
        "-",
        "--",
        "—",
        "–",
        "−",
        "―",
        "n/a",
        "na",
        "none",
        "null",
        "unknown",
        "?",
        "\\n",
        "\\N",
    }
)


def normalize_search_text(value: object) -> str:
    if value is None:
        return ""
    text = str(value)
    if not text:
        return ""
    text = _strip_marks(_casefold_after_strip(text))
    text = "".join(" " if ch in HYPHENS else ch for ch in text)
    return _collapse_whitespace(text)


def compact_search_text(normalized: str) -> str:
    return normalized.replace(" ", "")


def is_ascii_alnum(value: str) -> bool:
    return bool(value) and all(("a" <= ch <= "z") or ("0" <= ch <= "9") for ch in value)


def ascii_upper(value: str) -> str:
    return "".join(chr(ord(ch) - 32) if "a" <= ch <= "z" else ch for ch in value)


def clean_code(value: object) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    if text.casefold() in NULL_CODE_MARKERS:
        return None
    text = ascii_upper(text)
    if not text or text.casefold() in NULL_CODE_MARKERS:
        return None
    return text


def _strip_marks(text: str) -> str:
    decomposed = unicodedata.normalize("NFD", text)
    return "".join(ch for ch in decomposed if unicodedata.combining(ch) == 0)


def _casefold_after_strip(text: str) -> str:
    return _strip_marks(text).casefold()


def collapse_whitespace(text: str) -> str:
    parts: list[str] = []
    current: list[str] = []
    for ch in text:
        if ch in WHITESPACE:
            if current:
                parts.append("".join(current))
                current = []
        else:
            current.append(ch)
    if current:
        parts.append("".join(current))
    return " ".join(parts)


def _collapse_whitespace(text: str) -> str:
    return collapse_whitespace(text)
