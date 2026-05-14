import Foundation

/// Shared fuzzy / subsequence matcher used by both the focus/send list
/// filter and the manage overlay's target + snapshot pickers.
///
/// `query` matches a candidate if its characters appear in order somewhere
/// in the candidate string — not necessarily contiguously. So `hm` matches
/// both "home" and "home-management"; `arc` matches "archives". This is
/// broader than substring matching (which the manage flow used previously)
/// and lets the user reach a workspace with a few sparse keystrokes.
enum FuzzyMatch {
    /// Returns matched candidates sorted by tightness — earlier first match
    /// + smaller span wins. Lowercase-insensitive. Empty query passes all
    /// candidates through unchanged.
    static func filter<T>(_ items: [T], query: String,
                          keyPath: (T) -> String) -> [T] {
        guard !query.isEmpty else { return items }
        let q = query.lowercased()
        var scored: [(T, Int)] = []
        for item in items {
            if let score = subseqScore(query: q, name: keyPath(item).lowercased()) {
                scored.append((item, score))
            }
        }
        scored.sort { $0.1 < $1.1 }
        return scored.map(\.0)
    }

    /// Score a single (query, candidate) pair. Lower score = better match.
    /// Returns nil when the query isn't a subsequence of the candidate.
    /// Score = (span between first and last match) × 100 + first-match index.
    /// That ranking prefers tight, leading matches over loose tail matches.
    static func subseqScore(query: String, name: String) -> Int? {
        var qi = query.startIndex
        var firstHit: Int?
        var lastHit: Int = 0
        for (i, ch) in name.enumerated() {
            if qi == query.endIndex { break }
            if ch == query[qi] {
                if firstHit == nil { firstHit = i }
                lastHit = i
                qi = query.index(after: qi)
            }
        }
        guard qi == query.endIndex, let first = firstHit else { return nil }
        return (lastHit - first) * 100 + first
    }
}
