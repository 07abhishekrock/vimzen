import AppKit
import Combine

/// Centralized reactive data bus supplying telemetry and state to all plugins.
/// Core engine and managers publish their state here; plugins subscribe only to what they need.
@MainActor
public final class PluginDataBus: ObservableObject {
    public static let shared = PluginDataBus()

    @Published public private(set) var mode: Mode = .normal
    @Published public private(set) var pendingKeys: String = ""
    @Published public private(set) var tabsCount: Int = 0
    @Published public private(set) var activeTabTitle: String = ""
    @Published public private(set) var activeTabURL: URL? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var estimatedProgress: Double = 0.0

    private var cancellables = Set<AnyCancellable>()
    private var activeTabCancellables = Set<AnyCancellable>()

    private init() {}

    /// Connects the key engine and tab manager to the data bus.
    public func attach(keyEngine: KeyEngine, tabManager: TabManager) {
        cancellables.removeAll()

        keyEngine.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] newMode in
                self?.mode = newMode
            }
            .store(in: &cancellables)

        keyEngine.$pendingKeys
            .receive(on: RunLoop.main)
            .sink { [weak self] keys in
                self?.pendingKeys = keys
            }
            .store(in: &cancellables)

        tabManager.$tabs
            .receive(on: RunLoop.main)
            .sink { [weak self] tabs in
                self?.tabsCount = tabs.count
            }
            .store(in: &cancellables)

        tabManager.$activeTabId
            .receive(on: RunLoop.main)
            .sink { [weak self, weak tabManager] _ in
                self?.observeActiveTab(tabManager?.activeTab)
            }
            .store(in: &cancellables)

        // Initial state synchronization
        mode = keyEngine.mode
        pendingKeys = keyEngine.pendingKeys
        tabsCount = tabManager.tabs.count
        observeActiveTab(tabManager.activeTab)
    }

    private func observeActiveTab(_ tab: Tab?) {
        activeTabCancellables.removeAll()
        guard let tab = tab else {
            activeTabTitle = ""
            activeTabURL = nil
            isLoading = false
            estimatedProgress = 0.0
            return
        }

        tab.$title
            .receive(on: RunLoop.main)
            .sink { [weak self] title in
                self?.activeTabTitle = title
            }
            .store(in: &activeTabCancellables)

        tab.$url
            .receive(on: RunLoop.main)
            .sink { [weak self] url in
                self?.activeTabURL = url
            }
            .store(in: &activeTabCancellables)

        tab.$isLoading
            .receive(on: RunLoop.main)
            .sink { [weak self] loading in
                self?.isLoading = loading
            }
            .store(in: &activeTabCancellables)

        tab.$estimatedProgress
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                self?.estimatedProgress = progress
            }
            .store(in: &activeTabCancellables)

        activeTabTitle = tab.title
        activeTabURL = tab.url
        isLoading = tab.isLoading
        estimatedProgress = tab.estimatedProgress
    }
}
