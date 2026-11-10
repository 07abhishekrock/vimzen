import Foundation

@MainActor
public final class GoogleSuggestSource: PickerSource {
    public let sourceKind: PickerSourceKind = .googleSuggest
    public let badge: String = "SUGG"

    private struct CacheEntry {
        let timestamp: Date
        let items: [PickerItem]
    }

    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 60.0
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 4.0
        self.session = URLSession(configuration: config)
    }

    public func items(matching query: String) async throws -> [PickerItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Don't query Google for empty or 1-character queries
        guard trimmed.count >= 2 else { return [] }

        // Check in-memory TTL cache
        let cacheKey = trimmed.lowercased()
        if let entry = cache[cacheKey], Date().timeIntervalSince(entry.timestamp) < cacheTTL {
            return entry.items
        }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://suggestqueries.google.com/complete/search?client=firefox&q=\(encoded)") else {
            return []
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }

            // Google Suggest format: ["query", ["sug 1", "sug 2", ...]]
            guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                  json.count >= 2,
                  let suggestions = json[1] as? [String] else {
                return []
            }

            let items: [PickerItem] = suggestions.map { suggestion in
                let searchTarget = suggestion.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? suggestion
                let searchURL = URL(string: "https://www.google.com/search?q=\(searchTarget)")

                return PickerItem(
                    id: "google:\(suggestion.lowercased())",
                    display: suggestion,
                    detail: "Google Search",
                    badge: self.badge,
                    url: searchURL,
                    title: suggestion,
                    source: .googleSuggest,
                    visitCount: 0,
                    lastVisitAt: nil,
                    typedCount: 0
                )
            }

            cache[cacheKey] = CacheEntry(timestamp: Date(), items: items)
            return items
        } catch {
            // Network failure or timeout returns empty without interrupting UI
            return []
        }
    }
}
