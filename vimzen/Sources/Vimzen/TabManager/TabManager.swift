import AppKit
import Combine

@MainActor
public final class TabManager: ObservableObject {
    @Published public private(set) var tabs: [Tab] = []
    @Published public private(set) var activeTabId: UUID?
    public private(set) var previousActiveTabId: UUID?

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
    public func createTab(url: URL? = nil, activate: Bool = true) -> Tab {
        let tab = Tab()
        tabs.append(tab)

        // Add webview to container
        tab.webView.frame = containerView.bounds
        tab.webView.autoresizingMask = [.width, .height]
        containerView.addSubview(tab.webView)

        if let url = url {
            tab.load(url: url)
        }

        if activate {
            switchToTab(id: tab.id)
        } else {
            tab.webView.isHidden = true
        }

        return tab
    }

    public func switchToTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        if activeTabId != id {
            previousActiveTabId = activeTabId
        }
        activeTabId = id

        for tab in tabs {
            let isActive = tab.id == id
            tab.webView.isHidden = !isActive
            if isActive {
                tab.markActive()
                containerView.window?.makeFirstResponder(tab.webView)
            }
        }
    }

    public func nextTab() {
        guard !tabs.isEmpty, let currentId = activeTabId,
              let currentIndex = tabs.firstIndex(where: { $0.id == currentId }) else { return }
        let nextIndex = (currentIndex + 1) % tabs.count
        switchToTab(id: tabs[nextIndex].id)
    }

    public func previousTab() {
        guard !tabs.isEmpty, let currentId = activeTabId,
              let currentIndex = tabs.firstIndex(where: { $0.id == currentId }) else { return }
        let prevIndex = (currentIndex - 1 + tabs.count) % tabs.count
        switchToTab(id: tabs[prevIndex].id)
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

        let sameDomainTabs = tabs.filter { tab in
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
              tabs.contains(where: { $0.id == prevId }) else {
            let toast = NotificationToast(message: "No alternate tab", duration: 2.0)
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

        if previousActiveTabId == id {
            // Pick next most recently active tab excluding current active
            previousActiveTabId = tabs.filter { $0.id != activeTabId }
                .sorted { $0.lastActiveAt > $1.lastActiveAt }
                .first?.id
        }

        if activeTabId == id {
            if !tabs.isEmpty {
                let nextIndex = min(index, tabs.count - 1)
                switchToTab(id: tabs[nextIndex].id)
            } else {
                activeTabId = nil
            }
        }
    }
}
