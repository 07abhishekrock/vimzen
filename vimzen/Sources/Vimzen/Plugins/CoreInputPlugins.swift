import AppKit

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

        if let googleItems = try? await googleSource.items(matching: query) {
            candidates.append(contentsOf: googleItems)
        }

        let hasActiveTab = tabManager?.activeTab != nil
        return PickerRanking.rank(query: query, candidates: candidates, hasActiveTab: hasActiveTab)
    }

    public func onSubmit(input: String, controller: AnyObject?) {
        guard let mainVC = controller as? MainViewController else { return }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

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
