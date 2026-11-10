import Foundation

@MainActor
public final class TabsPickerSource: PickerSource {
    public let sourceKind: PickerSourceKind = .openTab
    public let badge: String = "TAB"

    private weak var tabManager: TabManager?

    public init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    public func items(matching query: String) async throws -> [PickerItem] {
        guard let tabManager = tabManager else { return [] }

        // Most recently active tabs first, scoped to current profile
        let sortedTabs = tabManager.currentProfileTabs.sorted {
            $0.lastActiveAt > $1.lastActiveAt
        }

        return sortedTabs.map { tab in
            let displayTitle = tab.title.isEmpty ? (tab.url?.host ?? "New Tab") : tab.title
            let detail = tab.url?.absoluteString

            return PickerItem(
                id: "tab:\(tab.id.uuidString)",
                display: displayTitle,
                detail: detail,
                badge: badge,
                url: tab.url,
                title: tab.title,
                source: .openTab,
                visitCount: 1,
                lastVisitAt: tab.lastActiveAt,
                typedCount: 1
            )
        }
    }
}
