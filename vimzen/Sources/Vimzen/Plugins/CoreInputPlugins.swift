import AppKit

public enum VimzenDefaults {
    /// Maximum number of MRU tabs to display in the combobox for an empty query.
    public static let emptyComboboxTabLimit = 5
}

// MARK: - Open URL Input Plugin

@MainActor
public final class OpenUrlInputPlugin: InputPlugin {
    public let id = "input.open"
    public let prompt = "OPEN"
    public let promptIconName: String? = "globe"
    public let commandAliases = [":open", ":o"]
    public let placeholder = "Enter URL or search query (e.g. groww.in, github.com)..."
    public let isComboboxEnabled: Bool = true

    private let inNewTab: Bool
    private weak var tabManager: TabManager?
    private lazy var tabsSource: TabsPickerSource? = {
        guard let tm = tabManager else { return nil }
        return TabsPickerSource(tabManager: tm)
    }()
    private let googleSource = GoogleSuggestSource()
    private let historySource = HistoryPickerSource()

    public init(tabManager: TabManager? = nil, inNewTab: Bool = false) {
        self.tabManager = tabManager
        self.inNewTab = inNewTab
    }

    public func queryItems(query: String) async -> [RankedResult] {
        var candidates: [PickerItem] = []

        if let tabsSource = tabsSource {
            if let tabItems = try? await tabsSource.items(matching: query) {
                candidates.append(contentsOf: tabItems)
            }
        }

        if !query.isEmpty {
            if let histItems = try? await historySource.items(matching: query) {
                candidates.append(contentsOf: histItems)
            }
            if let googleItems = try? await googleSource.items(matching: query) {
                candidates.append(contentsOf: googleItems)
            }
        }

        let hasActiveTab = tabManager?.activeTab != nil
        let ranked = PickerRanking.rank(query: query, candidates: candidates, hasActiveTab: hasActiveTab)
        if query.isEmpty {
            return Array(ranked.prefix(VimzenDefaults.emptyComboboxTabLimit))
        }
        return ranked
    }

    public func queryItemsStreaming(
        query: String,
        onUpdate: @escaping @MainActor ([RankedResult]) -> Void
    ) async {
        var tabCandidates: [PickerItem] = []
        if let tabsSource = tabsSource {
            tabCandidates = (try? await tabsSource.items(matching: query)) ?? []
        }
        if Task.isCancelled { return }

        let hasActiveTab = tabManager?.activeTab != nil
        let tabsRanked = PickerRanking.rank(query: query, candidates: tabCandidates, hasActiveTab: hasActiveTab)
        let cappedTabs = query.isEmpty
            ? Array(tabsRanked.prefix(VimzenDefaults.emptyComboboxTabLimit))
            : tabsRanked

        onUpdate(cappedTabs)

        if query.isEmpty { return }

        var secondaryCandidates: [PickerItem] = []
        if let histItems = try? await historySource.items(matching: query) {
            secondaryCandidates.append(contentsOf: histItems)
        }
        let googleCandidates = (try? await googleSource.items(matching: query)) ?? []
        secondaryCandidates.append(contentsOf: googleCandidates)

        if Task.isCancelled { return }

        let secondaryRanked = PickerRanking.rank(query: query, candidates: secondaryCandidates, hasActiveTab: hasActiveTab)
        onUpdate(cappedTabs + secondaryRanked)
    }

    public func onSubmit(input: String, controller: AnyObject?) {
        guard let mainVC = controller as? MainViewController else { return }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // If an existing open tab was selected, switch to it
        if trimmed.hasPrefix("tab:"), let uuid = UUID(uuidString: String(trimmed.dropFirst(4))) {
            mainVC.tabManager.switchToTab(id: uuid)
            return
        }

        let targetURL = resolveURL(trimmed)

        // Record typed visit in history (for persistent profiles)
        let activeProfile = ProfileManager.shared.activeProfile
        if !activeProfile.isEphemeral {
            HistoryStore.shared.recordVisit(
                url: targetURL,
                title: trimmed,
                profileId: activeProfile.id,
                isTyped: true
            )
        }

        if inNewTab || mainVC.tabManager.activeTab == nil {
            mainVC.tabManager.createTab(url: targetURL, activate: true)
        } else {
            mainVC.tabManager.activeTab?.load(url: targetURL)
        }
    }

    public func onCancel(controller: AnyObject?) {
        guard let mainVC = controller as? MainViewController else { return }
        if let activeWebView = mainVC.tabManager.activeTab?.webView {
            mainVC.view.window?.makeFirstResponder(activeWebView)
        }
    }

    private func resolveURL(_ input: String) -> URL {
        if input.starts(with: "http://") || input.starts(with: "https://") {
            return URL(string: input) ?? URL(string: "https://google.com/search?q=\(input)")!
        } else if input.contains(".") && !input.contains(" ") {
            return URL(string: "https://\(input)")!
        } else {
            let encoded = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
            return URL(string: "https://www.google.com/search?q=\(encoded)")!
        }
    }
}

// MARK: - Command (Ex) Input Plugin

@MainActor
public final class CommandInputPlugin: InputPlugin {
    public let id = "input.command"
    public let prompt = "COMMAND"
    public let promptIconName: String? = "command"
    public let commandAliases = [":"]
    public let placeholder = ":q to close, :qa to quit, :r to reload, :open <url>"

    public init() {}

    public func onSubmit(input: String, controller: AnyObject?) {
        guard let mainVC = controller as? MainViewController else { return }
        let cmd = input.trimmingCharacters(in: .whitespacesAndNewlines)

        switch cmd {
        case ":q", "q":
            // Close active tab and trigger 4s interactive undo toast per Architecture §10.4
            if let activeTab = mainVC.tabManager.activeTab {
                let savedURL = activeTab.url
                let savedTitle = activeTab.title
                mainVC.tabManager.closeActiveTab()

                let toast = NotificationToast(
                    message: "Closed: \(savedTitle.isEmpty ? (savedURL?.host ?? "Tab") : savedTitle)",
                    actionKey: "u",
                    actionLabel: "restore",
                    duration: 4.0,
                    onAction: { [weak mainVC] in
                        if let url = savedURL {
                            mainVC?.tabManager.createTab(url: url, activate: true)
                        }
                    }
                )
                PluginRegistry.shared.showToast(toast)
            }
        case ":qa", ":qall", "qa":
            NSApp.terminate(nil)
        case ":r", ":reload", "r":
            mainVC.tabManager.activeTab?.reload()
        case ":tabnew", "tabnew", ":t", "t":
            mainVC.tabManager.createTab(url: nil, activate: true)
        case ":b#", "b#", ":b #", "b #":
            mainVC.tabManager.switchToLastActiveTab()
        case ":b", "b", ":tabs", "tabs", ":buffers", "buffers":
            mainVC.keyEngine.onTriggerInputPlugin?("input.tab-picker")
        case ":p#", "p#", ":p #", "p #", ":profile#", "profile#":
            mainVC.tabManager.switchToLastActiveProfile()
        case ":p", "p", ":profile", "profile":
            mainVC.keyEngine.onTriggerInputPlugin?("input.profile-picker")
        case _ where cmd.starts(with: ":p new ") || cmd.starts(with: "p new ") || cmd.starts(with: ":profile new ") || cmd.starts(with: "profile new "):
            let name = cmd.replacingOccurrences(of: "^:?(p|profile)\\s+new\\s+", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                let created = ProfileManager.shared.createProfile(name: name)
                mainVC.tabManager.switchProfile(to: created.id)
            }
        case _ where cmd.starts(with: ":p ") || cmd.starts(with: "p ") || cmd.starts(with: ":profile ") || cmd.starts(with: "profile "):
            let name = cmd.replacingOccurrences(of: "^:?(p|profile)\\s+", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            if let match = ProfileManager.shared.profile(named: name) {
                mainVC.tabManager.switchProfile(to: match.id)
            }
        case _ where cmd.starts(with: ":send ") || cmd.starts(with: "send ") || cmd.starts(with: ":transfer ") || cmd.starts(with: "transfer "):
            let name = cmd.replacingOccurrences(of: "^:?(send|transfer)\\s+", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            if let match = ProfileManager.shared.profile(named: name) {
                mainVC.tabManager.moveCurrentTab(to: match.id)
            }
        case ":history", "history":
            mainVC.keyEngine.onTriggerInputPlugin?("input.history-picker")
        case _ where cmd.starts(with: ":clearhistory") || cmd.starts(with: "clearhistory"):
            let arg = cmd.replacingOccurrences(of: "^:?clearhistory\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            let activeProf = ProfileManager.shared.activeProfile
            if arg == "today" {
                HistoryStore.shared.clear(profileId: activeProf.id, scope: .today)
                PluginRegistry.shared.showToast(NotificationToast(message: "Cleared today's history (\(activeProf.name))", duration: 2.0))
            } else if arg.starts(with: "--domain ") || arg.starts(with: "domain ") {
                let dom = arg.replacingOccurrences(of: "^(--domain|domain)\\s+", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                HistoryStore.shared.clear(profileId: activeProf.id, scope: .domain(dom))
                PluginRegistry.shared.showToast(NotificationToast(message: "Cleared history for \(dom)", duration: 2.0))
            } else {
                HistoryStore.shared.clear(profileId: activeProf.id, scope: .all)
                PluginRegistry.shared.showToast(NotificationToast(message: "Cleared all history (\(activeProf.name))", duration: 2.0))
            }
        case _ where cmd.starts(with: ":clearcookie") || cmd.starts(with: "clearcookie"):
            var arg = cmd.replacingOccurrences(of: "^:?clearcookies?\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            if arg.starts(with: "--domain ") {
                arg = arg.replacingOccurrences(of: "^--domain\\s+", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let domainArg = arg.isEmpty ? nil : arg
            SecurityManager.clearCookies(domain: domainArg, profile: ProfileManager.shared.activeProfile, tabManager: mainVC.tabManager)
        case _ where cmd.starts(with: ":clearstorage") || cmd.starts(with: "clearstorage") || cmd.starts(with: ":cleartokens") || cmd.starts(with: "cleartokens"):
            var arg = cmd.replacingOccurrences(of: "^:?(clearstorage|cleartokens)\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            if arg.starts(with: "--domain ") {
                arg = arg.replacingOccurrences(of: "^--domain\\s+", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let domainArg = arg.isEmpty ? nil : arg
            SecurityManager.clearStorage(domain: domainArg, profile: ProfileManager.shared.activeProfile, tabManager: mainVC.tabManager)
        case _ where cmd.starts(with: ":forget") || cmd.starts(with: "forget"):
            var arg = cmd.replacingOccurrences(of: "^:?forget(site)?\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            if arg.starts(with: "--domain ") {
                arg = arg.replacingOccurrences(of: "^--domain\\s+", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let domainArg = arg.isEmpty ? nil : arg
            SecurityManager.forget(domain: domainArg, profile: ProfileManager.shared.activeProfile, tabManager: mainVC.tabManager)
        case _ where cmd == ":js" || cmd == "js" || cmd.starts(with: ":js ") || cmd.starts(with: "js ") || cmd == ":toggle js" || cmd == "toggle js":
            let sub = cmd.replacingOccurrences(of: "^:?(js|toggle\\s+js)\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let activeTab = mainVC.tabManager.activeTab else { break }
            if sub == "on" {
                activeTab.toggleJavaScript(enable: true)
            } else if sub == "off" {
                activeTab.toggleJavaScript(enable: false)
            } else {
                activeTab.toggleJavaScript()
            }
            let status = activeTab.isJavaScriptEnabled ? "ON" : "OFF (isolated)"
            PluginRegistry.shared.showToast(NotificationToast(message: "JavaScript: \(status)", duration: 2.0))
        case ":cert", "cert", ":ssl", "ssl":
            let summary = mainVC.tabManager.activeTab?.certificateSummary() ?? "No active tab"
            PluginRegistry.shared.showToast(NotificationToast(message: summary, duration: 4.0))
        case ":scripts", "scripts":
            let dir = UserScriptManager.shared.scriptsDirectory
            NSWorkspace.shared.open(dir)
            let count = UserScriptManager.shared.loadScripts().count
            PluginRegistry.shared.showToast(NotificationToast(message: "Userscripts: \(count) loaded (~/.config/vimzen/scripts)", duration: 3.0))
        case ":reloadscripts", "reloadscripts":
            mainVC.tabManager.activeTab?.reload()
            let count = UserScriptManager.shared.loadScripts().count
            PluginRegistry.shared.showToast(NotificationToast(message: "Reloaded \(count) userscript(s)", duration: 2.0))
        case _ where cmd.starts(with: ":tabnew ") || cmd.starts(with: "tabnew ") || cmd.starts(with: ":t ") || cmd.starts(with: "t "):
            let urlPart = cmd.replacingOccurrences(of: "^:?(tabnew|t)\\s+", with: "", options: .regularExpression)
            OpenNewTabInputPlugin(tabManager: mainVC.tabManager).onSubmit(input: urlPart, controller: controller)
        case _ where cmd.starts(with: ":open ") || cmd.starts(with: "open "):
            let urlPart = cmd.replacingOccurrences(of: "^:?open\\s+", with: "", options: .regularExpression)
            OpenUrlInputPlugin(tabManager: mainVC.tabManager, inNewTab: false).onSubmit(input: urlPart, controller: controller)
        default:
            break
        }
    }

    public func onCancel(controller: AnyObject?) {
        guard let mainVC = controller as? MainViewController else { return }
        if let activeWebView = mainVC.tabManager.activeTab?.webView {
            mainVC.view.window?.makeFirstResponder(activeWebView)
        }
    }
}

// MARK: - Tab Switcher / Picker Input Plugin

@MainActor
public final class TabPickerInputPlugin: InputPlugin {
    public let id = "input.tab-picker"
    public let prompt = "TABS"
    public let promptIconName: String? = "rectangle.stack"
    public let commandAliases = [":tabs", ":b", ":buffers"]
    public let placeholder = "Filter open tabs (<C-j>/<C-k>, ↵ to switch)..."
    public let isComboboxEnabled: Bool = true

    private weak var tabManager: TabManager?
    private lazy var tabsSource: TabsPickerSource? = {
        guard let tm = tabManager else { return nil }
        return TabsPickerSource(tabManager: tm)
    }()

    public init(tabManager: TabManager? = nil) {
        self.tabManager = tabManager
    }

    public func queryItems(query: String) async -> [RankedResult] {
        guard let tabsSource = tabsSource else { return [] }
        let raw = (try? await tabsSource.items(matching: query)) ?? []
        let hasActiveTab = tabManager?.activeTab != nil
        let ranked = PickerRanking.rank(query: query, candidates: raw, hasActiveTab: hasActiveTab)
        if query.isEmpty {
            return Array(ranked.prefix(VimzenDefaults.emptyComboboxTabLimit))
        }
        return ranked
    }

    public func onSubmit(input: String, controller: AnyObject?) {
        guard let mainVC = controller as? MainViewController else { return }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 1. Direct UUID match (from combobox selection id)
        if trimmed.hasPrefix("tab:"), let uuid = UUID(uuidString: String(trimmed.dropFirst(4))) {
            mainVC.tabManager.switchToTab(id: uuid)
            return
        }

        // 2. Fuzzy / prefix match against open tabs
        if let match = mainVC.tabManager.tabs.first(where: {
            $0.id.uuidString.lowercased() == trimmed.lowercased() ||
            $0.title.lowercased().contains(trimmed.lowercased()) ||
            $0.url?.absoluteString.lowercased().contains(trimmed.lowercased()) == true ||
            $0.url?.host?.lowercased().contains(trimmed.lowercased()) == true
        }) {
            mainVC.tabManager.switchToTab(id: match.id)
        }
    }

    public func onCancel(controller: AnyObject?) {
        guard let mainVC = controller as? MainViewController else { return }
        if let activeWebView = mainVC.tabManager.activeTab?.webView {
            mainVC.view.window?.makeFirstResponder(activeWebView)
        }
    }
}

// MARK: - Profile Switcher Input Plugin (gp / :profile / :p)

@MainActor
public final class ProfilePickerInputPlugin: InputPlugin {
    public let id = "input.profile-picker"
    public let prompt = "PROFILE"
    public let promptIconName: String? = "person.2.fill"
    public let commandAliases = [":profile", ":p"]
    public let placeholder = "Switch profile workspace (<C-j>/<C-k>, ↵ to switch)..."
    public let isComboboxEnabled: Bool = true

    private weak var tabManager: TabManager?
    private lazy var source: ProfilePickerSource? = {
        guard let tm = tabManager else { return nil }
        return ProfilePickerSource(tabManager: tm)
    }()

    public init(tabManager: TabManager? = nil) {
        self.tabManager = tabManager
    }

    public func queryItems(query: String) async -> [RankedResult] {
        guard let source = source else { return [] }
        let candidates = (try? await source.items(matching: query)) ?? []
        return PickerRanking.rank(query: query, candidates: candidates, hasActiveTab: false)
    }

    public func onSubmit(input: String, controller: AnyObject?) {
        guard let mainVC = controller as? MainViewController else { return }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 1. Direct profile UUID match (from combobox selection id)
        if trimmed.hasPrefix("profile:"), let uuid = UUID(uuidString: String(trimmed.dropFirst(8))) {
            mainVC.tabManager.switchProfile(to: uuid)
            return
        }

        // 2. Exact or badge match
        if let match = ProfileManager.shared.profile(named: trimmed) {
            mainVC.tabManager.switchProfile(to: match.id)
            return
        }

        // 3. Substring match
        if let match = ProfileManager.shared.profiles.first(where: {
            $0.name.lowercased().contains(trimmed.lowercased()) ||
            $0.badge.lowercased().contains(trimmed.lowercased())
        }) {
            mainVC.tabManager.switchProfile(to: match.id)
        }
    }

    public func onCancel(controller: AnyObject?) {
        guard let mainVC = controller as? MainViewController else { return }
        if let activeWebView = mainVC.tabManager.activeTab?.webView {
            mainVC.view.window?.makeFirstResponder(activeWebView)
        }
    }
}

// MARK: - Move Tab to Profile Input Plugin (gP / :send / :transfer)

@MainActor
public final class MoveTabProfileInputPlugin: InputPlugin {
    public let id = "input.move-tab-profile"
    public let prompt = "MOVE TAB"
    public let promptIconName: String? = "arrow.right.square.fill"
    public let commandAliases = [":send", ":transfer"]
    public let placeholder = "Move current tab to profile (<C-j>/<C-k>, ↵ to move)..."
    public let isComboboxEnabled: Bool = true

    private weak var tabManager: TabManager?
    private lazy var source: ProfilePickerSource? = {
        guard let tm = tabManager else { return nil }
        return ProfilePickerSource(tabManager: tm)
    }()

    public init(tabManager: TabManager? = nil) {
        self.tabManager = tabManager
    }

    public func queryItems(query: String) async -> [RankedResult] {
        guard let source = source else { return [] }
        let candidates = (try? await source.items(matching: query)) ?? []
        // In move tab mode, show destination profiles (other than active profile)
        let activeId = ProfileManager.shared.activeProfileId
        let filtered = candidates.filter { $0.id != "profile:\(activeId.uuidString)" }
        return PickerRanking.rank(query: query, candidates: filtered.isEmpty ? candidates : filtered, hasActiveTab: false)
    }

    public func onSubmit(input: String, controller: AnyObject?) {
        guard let mainVC = controller as? MainViewController else { return }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 1. Direct profile UUID match (from combobox selection id)
        if trimmed.hasPrefix("profile:"), let uuid = UUID(uuidString: String(trimmed.dropFirst(8))) {
            mainVC.tabManager.moveCurrentTab(to: uuid)
            return
        }

        // 2. Exact or badge match
        if let match = ProfileManager.shared.profile(named: trimmed) {
            mainVC.tabManager.moveCurrentTab(to: match.id)
            return
        }

        // 3. Substring match
        if let match = ProfileManager.shared.profiles.first(where: {
            $0.name.lowercased().contains(trimmed.lowercased()) ||
            $0.badge.lowercased().contains(trimmed.lowercased())
        }) {
            mainVC.tabManager.moveCurrentTab(to: match.id)
        }
    }

    public func onCancel(controller: AnyObject?) {
        guard let mainVC = controller as? MainViewController else { return }
        if let activeWebView = mainVC.tabManager.activeTab?.webView {
            mainVC.view.window?.makeFirstResponder(activeWebView)
        }
    }
}

// MARK: - History Switcher Input Plugin (gh / ,h / :history)

@MainActor
public final class HistoryPickerInputPlugin: InputPlugin {
    public let id = "input.history-picker"
    public let prompt = "HISTORY"
    public let promptIconName: String? = "clock.fill"
    public let commandAliases = [":history", ":h"]
    public let placeholder = "Search browsing history (<C-j>/<C-k>, ↵ to open)..."
    public let isComboboxEnabled: Bool = true

    private let source = HistoryPickerSource()

    public init() {}

    public func queryItems(query: String) async -> [RankedResult] {
        let candidates = (try? await source.items(matching: query)) ?? []
        return PickerRanking.rank(query: query, candidates: candidates, hasActiveTab: false)
    }

    public func onSubmit(input: String, controller: AnyObject?) {
        guard let mainVC = controller as? MainViewController else { return }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Strip prefix if any (hist:profileString:URL)
        let targetString: String
        if trimmed.hasPrefix("hist:") {
            let parts = trimmed.components(separatedBy: ":")
            targetString = parts.dropFirst(2).joined(separator: ":")
        } else {
            targetString = trimmed
        }

        let targetURL = resolveURL(targetString)
        if mainVC.tabManager.activeTab == nil {
            mainVC.tabManager.createTab(url: targetURL, activate: true)
        } else {
            mainVC.tabManager.activeTab?.load(url: targetURL)
        }
    }

    public func onCancel(controller: AnyObject?) {
        guard let mainVC = controller as? MainViewController else { return }
        if let activeWebView = mainVC.tabManager.activeTab?.webView {
            mainVC.view.window?.makeFirstResponder(activeWebView)
        }
    }

    private func resolveURL(_ input: String) -> URL {
        if input.starts(with: "http://") || input.starts(with: "https://") {
            return URL(string: input) ?? URL(string: "https://google.com/search?q=\(input)")!
        } else if input.contains(".") && !input.contains(" ") {
            return URL(string: "https://\(input)")!
        } else {
            let encoded = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
            return URL(string: "https://www.google.com/search?q=\(encoded)")!
        }
    }
}
