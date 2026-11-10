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
    @Published public private(set) var activeProfile: Profile = Profile.personal
    @Published public private(set) var activeTabTitle: String = ""
    @Published public private(set) var activeTabAlias: String? = nil
    @Published public private(set) var activeTabURL: URL? = nil
    @Published public private(set) var activeTabTopColor: NSColor? = nil
    @Published public private(set) var audibleTabsCount: Int = 0
    @Published public private(set) var activeTabIsAudible: Bool = false
    @Published public private(set) var activeTabIsMuted: Bool = false
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
            .sink { [weak self, weak tabManager] _ in
                guard let self = self, let tabManager = tabManager else { return }
                self.tabsCount = tabManager.currentProfileTabs.count
                self.audibleTabsCount = tabManager.audibleTabsCount
            }
            .store(in: &cancellables)

        ProfileManager.shared.$activeProfileId
            .receive(on: RunLoop.main)
            .sink { [weak self, weak tabManager] _ in
                guard let self = self, let tabManager = tabManager else { return }
                self.activeProfile = ProfileManager.shared.activeProfile
                self.tabsCount = tabManager.currentProfileTabs.count
                self.observeActiveTab(tabManager.activeTab)
            }
            .store(in: &cancellables)

        tabManager.$activeTabId
            .receive(on: RunLoop.main)
            .sink { [weak self, weak tabManager] tabId in
                guard let self = self, let tabManager = tabManager else { return }
                let current = tabManager.tabs.first(where: { $0.id == tabId })
                self.observeActiveTab(current)
            }
            .store(in: &cancellables)

        // Initial state synchronization
        mode = keyEngine.mode
        pendingKeys = keyEngine.pendingKeys
        activeProfile = ProfileManager.shared.activeProfile
        tabsCount = tabManager.currentProfileTabs.count
        observeActiveTab(tabManager.activeTab)
    }

    private func observeActiveTab(_ tab: Tab?) {
        activeTabCancellables.removeAll()
        guard let tab = tab else {
            activeTabTitle = ""
            activeTabAlias = nil
            activeTabURL = nil
            activeTabTopColor = nil
            activeTabIsAudible = false
            activeTabIsMuted = false
            isLoading = false
            estimatedProgress = 0.0
            return
        }

        tab.$alias
            .receive(on: RunLoop.main)
            .sink { [weak self] alias in
                self?.activeTabAlias = alias
            }
            .store(in: &activeTabCancellables)

        activeTabAlias = tab.alias

        tab.$isAudible
            .receive(on: RunLoop.main)
            .sink { [weak self] audible in
                self?.activeTabIsAudible = audible
            }
            .store(in: &activeTabCancellables)

        tab.$isMuted
            .receive(on: RunLoop.main)
            .sink { [weak self] muted in
                self?.activeTabIsMuted = muted
            }
            .store(in: &activeTabCancellables)

        activeTabIsAudible = tab.isAudible
        activeTabIsMuted = tab.isMuted

        tab.$topColor
            .receive(on: RunLoop.main)
            .sink { [weak self] color in
                self?.activeTabTopColor = color
            }
            .store(in: &activeTabCancellables)

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
