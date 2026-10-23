import Foundation

enum AviationText {
    private static let whitespace: Set<Unicode.Scalar> = [
        "\t", "\n", "\u{000B}", "\u{000C}", "\r",
        "\u{001C}", "\u{001D}", "\u{001E}", "\u{001F}",
        " ", "\u{0085}", "\u{00A0}", "\u{1680}",
        "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}", "\u{2004}",
        "\u{2005}", "\u{2006}", "\u{2007}", "\u{2008}", "\u{2009}", "\u{200A}",
        "\u{2028}", "\u{2029}", "\u{202F}", "\u{205F}", "\u{3000}",
    ]
    private static let hyphens: Set<Unicode.Scalar> = ["-", "‐", "‑", "‒", "–", "—", "_", "/", "\\"]

    static func normalize(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let folded = casefold(stripMarks(value))
        let replaced = String(String.UnicodeScalarView(folded.unicodeScalars.map { hyphens.contains($0) ? " " : $0 }))
        return collapse(stripMarks(replaced))
    }

    static func compact(_ normalized: String) -> String {
        normalized.replacingOccurrences(of: " ", with: "")
    }

    static func isASCIIAlphanumeric(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57)
        }
    }

    private static func stripMarks(_ value: String) -> String {
        let mutable = NSMutableString(string: value)
        CFStringNormalize(mutable, .D)
        var output = ""
        for scalar in String(mutable).unicodeScalars where scalar.properties.canonicalCombiningClass == .notReordered {
            output.unicodeScalars.append(scalar)
        }
        return output
    }

    private static func casefold(_ value: String) -> String {
        let mutable = NSMutableString(string: value)
        CFStringFold(mutable, .compareCaseInsensitive, nil)
        return String(mutable)
    }

    private static func collapse(_ value: String) -> String {
        var parts: [String] = []
        var current = ""
        for scalar in value.unicodeScalars {
            if whitespace.contains(scalar) {
                if !current.isEmpty {
                    parts.append(current)
                    current = ""
                }
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        if !current.isEmpty {
            parts.append(current)
        }
        return parts.joined(separator: " ")
    }
}
