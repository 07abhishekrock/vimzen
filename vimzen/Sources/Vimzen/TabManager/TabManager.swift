import AppKit
import Combine

@MainActor
public final class TabManager: ObservableObject {
    @Published public private(set) var tabs: [Tab] = []
    @Published public private(set) var activeTabByProfile: [UUID: UUID] = [:]
    @Published public private(set) var activeTabId: UUID?
    public private(set) var previousActiveTabByProfile: [UUID: UUID] = [:]

    public var currentProfileTabs: [Tab] {
        tabs.filter { $0.profileId == ProfileManager.shared.activeProfileId }
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
        } else {
            tab.loadNewTabTemplate()
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
        activeTabId = id

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

    // MARK: - Media Controls

    public var audibleTabsCount: Int {
        tabs.filter { $0.isAudible }.count
    }

    public func toggleActiveTabMute() {
        guard let current = activeTab else { return }
        current.toggleMute()
        let state = current.isMuted ? "Muted" : "Unmuted"
        PluginRegistry.shared.showToast(
            NotificationToast(message: "\(state): \(current.title.isEmpty ? "Tab" : current.title)", duration: 2.0)
        )
    }

    public func toggleMuteAllAudibleTabs() {
        let audibleTabs = tabs.filter { $0.isAudible || $0.isPlayingMedia }
        if audibleTabs.contains(where: { !$0.isMuted }) {
            // Mute all playing tabs
            for tab in audibleTabs {
                tab.toggleMute(enable: true)
            }
            PluginRegistry.shared.showToast(
                NotificationToast(message: "Muted all media tabs (\(audibleTabs.count))", duration: 2.0)
            )
        } else {
            // Unmute all
            let mutedTabs = tabs.filter { $0.isMuted }
            for tab in mutedTabs {
                tab.toggleMute(enable: false)
            }
            PluginRegistry.shared.showToast(
                NotificationToast(message: "Unmuted all media tabs", duration: 2.0)
            )
        }
    }

    public func cycleMediaTabs(delta: Int = 1) {
        var candidates = tabs.filter { $0.isAudible || $0.isPlayingMedia || $0.lastAudibleAt != nil }
        if candidates.isEmpty {
            PluginRegistry.shared.showToast(
                NotificationToast(message: "No media tabs playing or recently active", duration: 2.0)
            )
            return
        }

        // Rank candidates per Architecture §5.2:
        // 1. Currently audible & unmuted (most recent first)
        // 2. Currently playing but muted
        // 3. Paused / recently audible
        candidates.sort { a, b in
            let scoreA: Int = (a.isAudible && !a.isMuted) ? 3 : (a.isPlayingMedia ? 2 : 1)
            let scoreB: Int = (b.isAudible && !b.isMuted) ? 3 : (b.isPlayingMedia ? 2 : 1)
            if scoreA != scoreB {
                return scoreA > scoreB
            }
            let timeA = a.lastAudibleAt ?? a.lastActiveAt
            let timeB = b.lastAudibleAt ?? b.lastActiveAt
            return timeA > timeB
        }

        guard let active = activeTab, let currentIndex = candidates.firstIndex(where: { $0.id == active.id }) else {
            // Jump to top candidate
            let target = candidates[0]
            switchToTab(id: target.id)
            PluginRegistry.shared.showToast(
                NotificationToast(message: "Media: \(target.title.isEmpty ? (target.url?.host ?? "Tab") : target.title)", duration: 2.0)
            )
            return
        }

        // Cycle to next/prev candidate in ring order
        let total = candidates.count
        let nextIndex = ((currentIndex + delta) % total + total) % total
        let target = candidates[nextIndex]
        switchToTab(id: target.id)
        PluginRegistry.shared.showToast(
            NotificationToast(message: "Media: \(target.title.isEmpty ? (target.url?.host ?? "Tab") : target.title)", duration: 2.0)
        )
    }
}
