import Foundation

struct IndexedAviationRecord<Record: Sendable>: Sendable {
    let record: Record
    let recordId: String
    let codesNorm: [String]
    let codesCompact: [String]
    let namesNorm: [String]
    let namesCompact: [String]
    let identifierCompacts: Set<String>
}

struct AviationSearchIndex<Record: Sendable>: Sendable {
    let entries: [IndexedAviationRecord<Record>]
    private let exactCodes: [String: IntList]
    private let prefixBuckets: [UInt64: IntList]
    private let trigramBuckets: [UInt64: IntList]

    init(records: [Record], id: (Record) -> String, codes: (Record) -> [String], names: (Record) -> [String]) {
        var built: [IndexedAviationRecord<Record>] = []
        var exact: [String: IntList] = [:]
        var prefixes: [UInt64: IntList] = [:]
        var trigrams: [UInt64: IntList] = [:]
        built.reserveCapacity(records.count)
        for record in records {
            let recordId = id(record)
            let localId = recordId.split(separator: ":", maxSplits: 1).last.map(String.init) ?? recordId
            var codeValues = codes(record)
            if localId != recordId {
                codeValues.append(localId)
            }
            var codesNorm: [String] = []
            var codesCompact: [String] = []
            for value in codeValues {
                let normalized = AviationText.normalize(value)
                let compact = AviationText.compact(normalized)
                if !compact.isEmpty {
                    codesNorm.append(normalized)
                    codesCompact.append(compact)
                }
            }
            var namesNorm: [String] = []
            var namesCompact: [String] = []
            for value in names(record) {
                let normalized = AviationText.normalize(value)
                if !normalized.isEmpty {
                    namesNorm.append(normalized)
                    namesCompact.append(AviationText.compact(normalized))
                }
            }
            let identifierCompacts = Set(
                [recordId, localId].map { AviationText.compact(AviationText.normalize($0)) }.filter { !$0.isEmpty }
            )
            let entry = IndexedAviationRecord(
                record: record,
                recordId: recordId,
                codesNorm: codesNorm,
                codesCompact: codesCompact,
                namesNorm: namesNorm,
                namesCompact: namesCompact,
                identifierCompacts: identifierCompacts
            )
            let index = built.count
            built.append(entry)
            var seenExact: Set<String> = []
            var seenPrefix: Set<UInt64> = []
            var seenTrigram: Set<UInt64> = []
            for codeCompact in entry.codesCompact {
                if seenExact.insert(codeCompact).inserted {
                    appendIndex(index, for: codeCompact, into: &exact)
                }
                if codeCompact.count >= 2 {
                    let key = Self.packPrefix(codeCompact)
                    if seenPrefix.insert(key).inserted {
                        appendIndex(index, for: key, into: &prefixes)
                    }
                }
                if !entry.identifierCompacts.contains(codeCompact) {
                    Self.addTrigrams(codeCompact, index, &trigrams, &seenTrigram)
                }
            }
            for nameCompact in entry.namesCompact {
                if nameCompact.count >= 2 {
                    let key = Self.packPrefix(nameCompact)
                    if seenPrefix.insert(key).inserted {
                        appendIndex(index, for: key, into: &prefixes)
                    }
                }
                Self.addTrigrams(nameCompact, index, &trigrams, &seenTrigram)
            }
        }
        entries = built
        exactCodes = exact
        prefixBuckets = prefixes
        trigramBuckets = trigrams
    }

    func exactCodeCount(query: String) -> Int {
        let compact = AviationText.compact(AviationText.normalize(query))
        return exactCodes[compact]?.values.count ?? 0
    }

    func search(query: String, limit: Int, include: (Record) -> Bool = { _ in true }) throws -> [Record] {
        if limit < 0 {
            throw AviationCatalogError.invalidLimit
        }
        let normalized = AviationText.normalize(query)
        let compact = AviationText.compact(normalized)
        if limit == 0 || normalized.isEmpty || compact.count < 2 {
            return []
        }
        let shortCode = compact.count <= 3 && AviationText.isASCIIAlphanumeric(compact)
        var candidates = Set(prefixBuckets[Self.packPrefix(compact)]?.values ?? [])
        if compact.count >= 3 {
            for index in trigramBuckets[Self.packTrigram(compact)]?.values ?? [] {
                candidates.insert(index)
            }
        }
        var ranked: [(Int, String, Record)] = []
        ranked.reserveCapacity(candidates.count)
        for index in candidates {
            let entry = entries[index]
            guard include(entry.record) else { continue }
            guard let tier = Self.tier(entry, normalized, compact, shortCode) else { continue }
            ranked.append((tier, entry.recordId, entry.record))
        }
        ranked.sort { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            return lhs.1 < rhs.1
        }
        return ranked.prefix(limit).map(\.2)
    }

    private static func addTrigrams(
        _ value: String,
        _ index: Int,
        _ buckets: inout [UInt64: IntList],
        _ seen: inout Set<UInt64>
    ) {
        var iterator = value.unicodeScalars.makeIterator()
        guard var first = iterator.next(), var second = iterator.next(), var third = iterator.next() else { return }
        while true {
            let tri = pack(first, second, third)
            if seen.insert(tri).inserted {
                appendIndex(index, for: tri, into: &buckets)
            }
            guard let next = iterator.next() else { break }
            first = second
            second = third
            third = next
        }
    }

    private static func packPrefix(_ value: String) -> UInt64 {
        let scalars = Array(value.unicodeScalars.prefix(2))
        guard scalars.count == 2 else { return 0 }
        return pack(scalars[0], scalars[1], Unicode.Scalar(0))
    }

    private static func packTrigram(_ value: String) -> UInt64 {
        let scalars = Array(value.unicodeScalars.prefix(3))
        guard scalars.count == 3 else { return 0 }
        return pack(scalars[0], scalars[1], scalars[2])
    }

    private static func pack(_ first: Unicode.Scalar, _ second: Unicode.Scalar, _ third: Unicode.Scalar) -> UInt64 {
        UInt64(first.value) | (UInt64(second.value) << 21) | (UInt64(third.value) << 42)
    }

    private static func tier(
        _ entry: IndexedAviationRecord<Record>,
        _ queryNorm: String,
        _ queryCompact: String,
        _ shortCode: Bool
    ) -> Int? {
        var best: Int?
        for index in entry.codesNorm.indices {
            let codeNorm = entry.codesNorm[index]
            let codeCompact = entry.codesCompact[index]
            let tier: Int
            if codeCompact == queryCompact || codeNorm == queryNorm {
                return 0
            } else if queryCompact.count >= 2 && codeCompact.hasPrefix(queryCompact) {
                tier = 2
            } else if !entry.identifierCompacts.contains(codeCompact) && queryCompact.count >= 4 && codeCompact.contains(queryCompact) {
                tier = 4
            } else {
                continue
            }
            if best == nil || tier < best! {
                best = tier
            }
        }
        for index in entry.namesNorm.indices {
            let nameNorm = entry.namesNorm[index]
            let nameCompact = entry.namesCompact[index]
            let tier: Int
            if nameNorm == queryNorm || nameCompact == queryCompact {
                tier = 1
            } else if nameNorm.hasPrefix(queryNorm) || (queryCompact.count >= 2 && nameCompact.hasPrefix(queryCompact)) {
                tier = 3
            } else if !shortCode && queryCompact.count >= 3 && (nameNorm.contains(queryNorm) || nameCompact.contains(queryCompact)) {
                tier = 4
            } else {
                continue
            }
            if best == nil || tier < best! {
                best = tier
            }
        }
        return best
    }
}

public enum AviationQueryResolution<Record: Sendable>: Sendable {
    case blank
    case matches([Record])
    case ambiguous([Record])
    case unmatched(String)

    public var kindName: String {
        switch self {
        case .blank: return "blank"
        case .matches: return "matches"
        case .ambiguous: return "ambiguous"
        case .unmatched: return "unmatched"
        }
    }
}

func resolveAviationQuery<Record>(_ query: String, matches: [Record], exactCodeCount: Int = 0) -> AviationQueryResolution<Record> {
    if AviationText.normalize(query).isEmpty {
        return .blank
    }
    if !matches.isEmpty {
        if exactCodeCount > 1 {
            return .ambiguous(matches)
        }
        return .matches(matches)
    }
    return .unmatched(query.trimmingCharacters(in: aviationWhitespace))
}

/// Appended only while a search index is being built. Search reads `values` after that.
private final class IntList: @unchecked Sendable {
    var values: [Int] = []
}

private func appendIndex<Key: Hashable>(_ index: Int, for key: Key, into buckets: inout [Key: IntList]) {
    if let list = buckets[key] {
        list.values.append(index)
    } else {
        let list = IntList()
        list.values.append(index)
        buckets[key] = list
    }
}

private let aviationWhitespace = CharacterSet(charactersIn: "\t\n\u{000B}\u{000C}\r\u{001C}\u{001D}\u{001E}\u{001F} \u{0085}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}")
