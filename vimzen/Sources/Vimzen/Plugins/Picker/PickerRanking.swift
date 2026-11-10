import Foundation

public struct RankedResult: Sendable, Identifiable {
    public let id: String
    public let display: String
    public let detail: String?
    public let badge: String
    public let url: URL?
    public let score: Double

    public init(
        id: String,
        display: String,
        detail: String?,
        badge: String,
        url: URL?,
        score: Double
    ) {
        self.id = id
        self.display = display
        self.detail = detail
        self.badge = badge
        self.url = url
        self.score = score
    }
}

fileprivate struct ScoredItem {
    let item: PickerItem
    let score: Double
}

public struct PickerRanking {
    private enum Tuning {
        static let consecutiveBonus = 0.40
        static let boundaryBonus = 0.20
        static let exactCaseBonus = 0.10
        static let activeTabBoost = 0.30
        static let exactMatchBoost = 0.50
        static let halfLifeDays = 30.0
        static let maxResults = 12
    }

    private static let sourceWeights: [PickerSourceKind: Double] = [
        .openTab: 1.00,
        .googleSuggest: 0.60,
        .typedHistory: 0.85,
        .linkHistory: 0.75,
        .command: 0.95
    ]

    /// Main ranking entry point. Evaluates, scores, deduplicates, and orders candidates.
    public static func rank(
        query: String,
        candidates: [PickerItem],
        hasActiveTab: Bool,
        now: Date = Date()
    ) -> [RankedResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Score every candidate
        let scored: [ScoredItem] = candidates.compactMap { item in
            let matchTarget = bestMatchTarget(item)
            let m: Double

            if trimmedQuery.isEmpty {
                // Empty query shows MRU tabs only; suppress external suggestions
                m = item.source == .openTab ? 1.0 : -1.0
            } else {
                m = subsequenceMatch(query: trimmedQuery, in: matchTarget)
            }

            // Exclude items that failed subsequence match
            guard m >= 0 else { return nil }

            let f = frecency(
                visitCount: item.visitCount,
                typedCount: item.typedCount,
                lastVisit: item.lastVisitAt,
                now: now
            )

            let s = sourceWeights[item.source] ?? 0.50
            let tabBoost = (hasActiveTab && item.source == .openTab) ? Tuning.activeTabBoost : 0.0
            let exactBoost = exactMatchBoost(item, query: trimmedQuery)

            let finalScore = (m * f * s) + tabBoost + exactBoost
            return ScoredItem(item: item, score: finalScore)
        }

        // 2. Sort by descending score (tie-breaking by recency)
        let sorted = scored.sorted {
            if abs($0.score - $1.score) > 0.0001 {
                return $0.score > $1.score
            }
            let d0 = $0.item.lastVisitAt ?? .distantPast
            let d1 = $1.item.lastVisitAt ?? .distantPast
            return d0 > d1
        }

        // 3. Deduplicate by domain (highest-scoring candidate per domain wins)
        let deduped = deduplicateByDomain(sorted)

        // 4. Prefix to top N results
        let topResults = Array(deduped.prefix(Tuning.maxResults))

        return topResults.map { scored in
            RankedResult(
                id: scored.item.id,
                display: scored.item.display,
                detail: scored.item.detail,
                badge: scored.item.badge,
                url: scored.item.url,
                score: (scored.score * 100).rounded() / 100.0
            )
        }
    }

    /// Evaluates subsequence match quality with consecutive and word-boundary bonuses.
    /// Returns -1.0 if not all characters match in order.
    public static func subsequenceMatch(query: String, in target: String) -> Double {
        if query.isEmpty { return 0.0 }
        if target.isEmpty { return -1.0 }

        let qChars = Array(query.lowercased())
        let tChars = Array(target.lowercased())

        var qi = 0
        var ti = 0
        var positions: [Int] = []
        positions.reserveCapacity(qChars.count)

        while qi < qChars.count && ti < tChars.count {
            if qChars[qi] == tChars[ti] {
                positions.append(ti)
                qi += 1
            }
            ti += 1
        }

        // If all query characters were not found in order, exclude
        guard qi == qChars.count else { return -1.0 }

        var score = 0.30 // Base match bonus

        // Consecutive run bonus
        var runLength = 1
        var maxRun = 1
        for i in 1..<positions.count {
            if positions[i] == positions[i - 1] + 1 {
                runLength += 1
                maxRun = max(maxRun, runLength)
            } else {
                runLength = 1
            }
        }
        score += Tuning.consecutiveBonus * (Double(maxRun) / Double(qChars.count))

        // Word boundary bonus: prefix or preceded by separator
        let boundaries: Set<Character> = ["/", "-", ".", " ", "_", ":"]
        var boundaryHits = 0
        for pos in positions {
            if pos == 0 || boundaries.contains(tChars[pos - 1]) {
                boundaryHits += 1
            }
        }
        score += Tuning.boundaryBonus * (Double(boundaryHits) / Double(qChars.count))

        // Exact case match bonus
        if target.contains(query) {
            score += Tuning.exactCaseBonus
        }

        // Span penalty: tighter target lengths score higher
        let spanFactor = 1.0 / log2(Double(target.count) + 2.0)
        score *= (0.6 + 0.4 * spanFactor)

        return min(max(score, 0.0), 1.0)
    }

    /// Computes recency with half-life decay.
    public static func frecency(
        visitCount: Int,
        typedCount: Int,
        lastVisit: Date?,
        now: Date = Date()
    ) -> Double {
        let v = max(Double(visitCount), 1.0)
        let ageDays: Double
        if let lastVisit = lastVisit {
            ageDays = max(0.0, now.timeIntervalSince(lastVisit) / 86_400.0)
        } else {
            ageDays = 30.0
        }

        let decay = pow(0.5, ageDays / Tuning.halfLifeDays)
        return min(v * decay, 1.5)
    }

    private static func exactMatchBoost(_ item: PickerItem, query: String) -> Double {
        if query.isEmpty { return 0.0 }
        let q = query.lowercased()
        if item.url?.absoluteString.lowercased() == q { return Tuning.exactMatchBoost }
        if item.url?.host?.lowercased() == q { return Tuning.exactMatchBoost }
        if item.title?.lowercased() == q { return Tuning.exactMatchBoost }
        return 0.0
    }

    private static func deduplicateByDomain(_ items: [ScoredItem]) -> [ScoredItem] {
        var seenDomains = Set<String>()
        return items.filter { scored in
            guard let host = scored.item.url?.host else {
                return true // Keep non-URL items (e.g. raw suggestions or commands)
            }
            let normalizedHost = host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            if scored.item.source == .openTab {
                seenDomains.insert(normalizedHost)
                return true
            }
            return seenDomains.insert(normalizedHost).inserted
        }
    }

    private static func bestMatchTarget(_ item: PickerItem) -> String {
        if let title = item.title, !title.isEmpty {
            return title
        }
        if let host = item.url?.host {
            return host + (item.url?.path ?? "")
        }
        return item.display
    }
}
