import Foundation

@MainActor
public final class HistoryPickerSource: PickerSource {
    public let sourceKind: PickerSourceKind = .linkHistory
    public let badge: String = "HIST"

    public init() {}

    public func items(matching query: String) async throws -> [PickerItem] {
        let activeProfile = ProfileManager.shared.activeProfile

        // Incognito has zero persistent history
        if activeProfile.isEphemeral {
            return []
        }

        let entries = await HistoryStore.shared.search(
            query: query,
            profileId: activeProfile.id,
            limit: 100
        )

        return entries.map { entry in
            PickerItem(
                id: entry.id,
                display: entry.title,
                detail: entry.url.absoluteString,
                badge: badge,
                url: entry.url,
                title: entry.title,
                source: entry.typedCount > 0 ? .typedHistory : .linkHistory,
                visitCount: entry.visitCount,
                lastVisitAt: entry.lastVisitTime,
                typedCount: entry.typedCount
            )
        }
    }
}
