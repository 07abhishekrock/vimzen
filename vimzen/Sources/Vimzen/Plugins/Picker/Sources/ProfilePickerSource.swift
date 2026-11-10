import Foundation

@MainActor
public final class ProfilePickerSource: PickerSource {
    public let sourceKind: PickerSourceKind = .command
    public let badge: String = "PROF"

    private weak var tabManager: TabManager?

    public init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    public func items(matching query: String) async throws -> [PickerItem] {
        guard let tabManager = tabManager else { return [] }
        let profiles = ProfileManager.shared.profiles
        let activeProfileId = ProfileManager.shared.activeProfileId

        return profiles.map { profile in
            let tabCount = tabManager.tabs.filter { $0.profileId == profile.id }.count
            let isCurrent = (profile.id == activeProfileId)
            let currentSuffix = isCurrent ? "  (active)" : ""

            return PickerItem(
                id: "profile:\(profile.id.uuidString)",
                display: "\(profile.name)\(currentSuffix)",
                detail: "\(tabCount) tab\(tabCount == 1 ? "" : "s")",
                badge: profile.badge.uppercased(),
                url: nil,
                title: profile.name,
                source: .command,
                visitCount: isCurrent ? 5 : 1,
                lastVisitAt: isCurrent ? Date() : nil,
                typedCount: 1
            )
        }
    }
}
