import AppKit
import Combine

@MainActor
public final class TabManager: ObservableObject {
    @Published public private(set) var tabs: [Tab] = []
    @Published public private(set) var activeTabByProfile: [UUID: UUID] = [:]
    public private(set) var previousActiveTabByProfile: [UUID: UUID] = [:]

    public var currentProfileTabs: [Tab] {
        tabs.filter { $0.profileId == ProfileManager.shared.activeProfileId }
    }

    public var activeTabId: UUID? {
        activeTabByProfile[ProfileManager.shared.activeProfileId]
    }

    public var previousActiveTabId: UUID? {
        previousActiveTabByProfile[ProfileManager.shared.activeProfileId]
    }

    public var activeTab: Tab? {
        guard let id = activeTabId else { return nil }
        return tabs.first(where: { $0.id == id })
    }

    public let containerView = NSView()

    public init() {
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1.0).cgColor
    }

    @discardableResult
    public func createTab(url: URL? = nil, activate: Bool = true, profile: Profile? = nil) -> Tab {
        let targetProfile = profile ?? ProfileManager.shared.activeProfile
        let config = ProfileManager.shared.configuration(for: targetProfile)
        let tab = Tab(profileId: targetProfile.id, webViewConfiguration: config)
        tabs.append(tab)

        // Add webview to container
        tab.webView.frame = containerView.bounds
        tab.webView.autoresizingMask = [.width, .height]
        containerView.addSubview(tab.webView)

        if let url = url {
            tab.load(url: url)
        }

        if targetProfile.id == ProfileManager.shared.activeProfileId {
            if activate || activeTabId == nil {
                switchToTab(id: tab.id)
            } else {
                tab.webView.isHidden = true
            }
        } else {
            tab.webView.isHidden = true
            if activeTabByProfile[targetProfile.id] == nil {
                activeTabByProfile[targetProfile.id] = tab.id
            }
        }

        return tab
    }

    public func switchToTab(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }

        // If tab belongs to a different profile, switch active profile
        if tab.profileId != ProfileManager.shared.activeProfileId {
            ProfileManager.shared.setActiveProfile(id: tab.profileId)
        }

        let profileId = tab.profileId
        if activeTabByProfile[profileId] != id {
            previousActiveTabByProfile[profileId] = activeTabByProfile[profileId]
        }
        activeTabByProfile[profileId] = id

        for t in tabs {
            let isActive = (t.id == id)
            t.webView.isHidden = !isActive
            if isActive {
                t.markActive()
                containerView.window?.makeFirstResponder(t.webView)
            }
        }
    }

    public func switchProfile(to profileId: UUID) {
        guard let targetProfile = ProfileManager.shared.profiles.first(where: { $0.id == profileId }) else { return }

        // 1. Hide current active tab
        if let currentActive = activeTab {
            currentActive.webView.isHidden = true
        }

        // 2. Set active profile
        ProfileManager.shared.setActiveProfile(id: profileId)

        // 3. Find or create active tab for target profile
        if let targetTabId = activeTabByProfile[profileId],
           tabs.contains(where: { $0.id == targetTabId }) {
            switchToTab(id: targetTabId)
        } else if let firstTab = currentProfileTabs.first {
            switchToTab(id: firstTab.id)
        } else {
            // Target profile has no tabs yet — create a blank one
            createTab(url: nil, activate: true, profile: targetProfile)
        }

        // 4. Flash toast alert
        let toast = NotificationToast(
            message: "Profile: \(targetProfile.name) (\(currentProfileTabs.count) tabs)",
            duration: 2.0
        )
        PluginRegistry.shared.showToast(toast)
    }

    public func switchToLastActiveProfile() {
        guard let prevProfileId = ProfileManager.shared.previousActiveProfileId,
              ProfileManager.shared.profiles.contains(where: { $0.id == prevProfileId }) else {
            let toast = NotificationToast(message: "No alternate profile", duration: 2.0)
            PluginRegistry.shared.showToast(toast)
            return
        }
        switchProfile(to: prevProfileId)
    }

    public func moveCurrentTab(to targetProfileId: UUID) {
        guard let currentTab = activeTab else { return }
        guard targetProfileId != currentTab.profileId else { return }
        guard let targetProfile = ProfileManager.shared.profiles.first(where: { $0.id == targetProfileId }) else { return }

        let savedURL = currentTab.url
        let savedTitle = currentTab.title

        // Close the tab in the current profile (keeping other tabs in current profile as-is)
        closeTab(id: currentTab.id)

        // Switch to the target profile
        switchProfile(to: targetProfileId)

        // Open the moved tab in the target profile and activate it
        let movedTab = createTab(url: savedURL, activate: true, profile: targetProfile)
        if !savedTitle.isEmpty {
            movedTab.title = savedTitle
        }

        // Flash toast
        let toast = NotificationToast(
            message: "Moved to \(targetProfile.name)",
            duration: 2.5
        )
        PluginRegistry.shared.showToast(toast)
    }

    public func nextTab() {
        let profileTabs = currentProfileTabs
        guard !profileTabs.isEmpty, let currentId = activeTabId,
              let currentIndex = profileTabs.firstIndex(where: { $0.id == currentId }) else { return }
        let nextIndex = (currentIndex + 1) % profileTabs.count
        switchToTab(id: profileTabs[nextIndex].id)
    }

    public func previousTab() {
        let profileTabs = currentProfileTabs
        guard !profileTabs.isEmpty, let currentId = activeTabId,
              let currentIndex = profileTabs.firstIndex(where: { $0.id == currentId }) else { return }
        let prevIndex = (currentIndex - 1 + profileTabs.count) % profileTabs.count
        switchToTab(id: profileTabs[prevIndex].id)
    }

    public func nextSameDomainTab(count: Int = 1) {
        cycleSameDomainTab(delta: count)
    }

    public func previousSameDomainTab(count: Int = 1) {
        cycleSameDomainTab(delta: -count)
    }

    private func cycleSameDomainTab(delta: Int) {
        guard let current = activeTab, let host = current.url?.host else {
            let toast = NotificationToast(message: "Current tab has no web domain", duration: 2.0)
            PluginRegistry.shared.showToast(toast)
            return
        }
        let currentDomain = normalizeDomain(host)
        guard !currentDomain.isEmpty else { return }

        let sameDomainTabs = currentProfileTabs.filter { tab in
            guard let h = tab.url?.host else { return false }
            return normalizeDomain(h) == currentDomain
        }

        guard sameDomainTabs.count > 1 else {
            let toast = NotificationToast(message: "Only 1 tab for \(currentDomain)", duration: 2.0)
            PluginRegistry.shared.showToast(toast)
            return
        }

        guard let currentIndex = sameDomainTabs.firstIndex(where: { $0.id == current.id }) else { return }
        let total = sameDomainTabs.count
        let nextIndex = ((currentIndex + delta) % total + total) % total
        switchToTab(id: sameDomainTabs[nextIndex].id)
    }

    private func normalizeDomain(_ host: String) -> String {
        host.lowercased().replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }

    public func switchToLastActiveTab() {
        guard let prevId = previousActiveTabId,
              currentProfileTabs.contains(where: { $0.id == prevId }) else {
            let toast = NotificationToast(message: "No alternate tab in this profile", duration: 2.0)
            PluginRegistry.shared.showToast(toast)
            return
        }
        switchToTab(id: prevId)
    }

    public func closeActiveTab() {
        guard let activeId = activeTabId else { return }
        closeTab(id: activeId)
    }

    public func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closingTab = tabs.remove(at: index)
        closingTab.webView.removeFromSuperview()

        let profileId = closingTab.profileId

        if previousActiveTabByProfile[profileId] == id {
            previousActiveTabByProfile[profileId] = tabs.filter { $0.profileId == profileId && $0.id != activeTabByProfile[profileId] }
                .sorted { $0.lastActiveAt > $1.lastActiveAt }
                .first?.id
        }

        if activeTabByProfile[profileId] == id {
            let remainingProfileTabs = tabs.filter { $0.profileId == profileId }
            if let nextTab = remainingProfileTabs.last {
                if profileId == ProfileManager.shared.activeProfileId {
                    switchToTab(id: nextTab.id)
                } else {
                    activeTabByProfile[profileId] = nextTab.id
                }
            } else {
                activeTabByProfile[profileId] = nil
                if profileId == ProfileManager.shared.activeProfileId {
                    // Create a blank tab if all tabs in active profile were closed
                    createTab(url: nil, activate: true)
                }
            }
        }
    }
}
