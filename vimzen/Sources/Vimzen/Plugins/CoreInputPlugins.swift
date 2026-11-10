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

        let googleCandidates = (try? await googleSource.items(matching: query)) ?? []
        if Task.isCancelled { return }

        let googleRanked = PickerRanking.rank(query: query, candidates: googleCandidates, hasActiveTab: hasActiveTab)
        onUpdate(cappedTabs + googleRanked)
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
