import AppKit

@MainActor
public final class MainViewController: NSViewController {
    public let tabManager = TabManager()
    public lazy var keyEngine = KeyEngine(tabManager: tabManager)

    private let dragHeader = WindowDragHeaderView()
    private let statusBar = StatusBarView()

    public override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1024, height: 720))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1.0).cgColor
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        registerCorePlugins()
        setupHierarchy()
        setupBindings()
    }

    private func registerCorePlugins() {
        let registry = PluginRegistry.shared

        // Category 1: View Plugins (Slot-based placement per Architecture §10.2)
        registry.registerViewPlugin(ModeBadgePlugin(order: 1), into: .left)
        registry.registerViewPlugin(PendingKeysPlugin(order: 2), into: .left)
        registry.registerViewPlugin(PageIdentityPlugin(order: 3), into: .left)
        registry.registerViewPlugin(LoadingStatusPlugin(order: 10), into: .right)
        registry.registerViewPlugin(TabsCountPlugin(order: 20), into: .right)

        // Category 2: Input Plugins (Command Bar Takeovers per Architecture §10.3)
        registry.registerInputPlugin(OpenUrlInputPlugin(inNewTab: false))
        registry.registerInputPlugin(OpenNewTabInputPlugin())
        registry.registerInputPlugin(CommandInputPlugin())
    }

    private func setupHierarchy() {
        // Draggable window header at top (28px)
        dragHeader.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dragHeader)

        // Webview tab container view
        let container = tabManager.containerView
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        // 26px Zen bottom bar with plugin slots and input takeover
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBar)

        NSLayoutConstraint.activate([
            // Top drag header
            dragHeader.topAnchor.constraint(equalTo: view.topAnchor),
            dragHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dragHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dragHeader.heightAnchor.constraint(equalToConstant: 28),

            // Tab webview container takes between drag header and bottom bar
            container.topAnchor.constraint(equalTo: dragHeader.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            // Status bar at bottom (26px)
            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    private func setupBindings() {
        statusBar.bind(keyEngine: keyEngine, tabManager: tabManager)

        // Trigger input plugin takeover (e.g. 'o', 'O', ':')
        keyEngine.onTriggerInputPlugin = { [weak self] pluginId in
            guard let self = self else { return }
            if PluginRegistry.shared.activateInputPlugin(id: pluginId) != nil {
                self.keyEngine.setMode(.command)
                let prefill = (pluginId == "input.open") ? (self.tabManager.activeTab?.url?.absoluteString ?? "") : ""
                self.statusBar.activateInput(prefill: prefill)
            }
        }

        keyEngine.onCancelInputPlugin = { [weak self] in
            guard let self = self else { return }
            self.cancelCurrentInput()
        }

        statusBar.onInputSubmit = { [weak self] input in
            guard let self = self else { return }
            if let activePlugin = PluginRegistry.shared.activeInputPlugin {
                activePlugin.onSubmit(input: input, controller: self)
            }
            self.finishCurrentInput()
        }

        statusBar.onInputCancel = { [weak self] in
            guard let self = self else { return }
            if let activePlugin = PluginRegistry.shared.activeInputPlugin {
                activePlugin.onCancel(controller: self)
            }
            self.cancelCurrentInput()
        }
    }

    private func finishCurrentInput() {
        PluginRegistry.shared.deactivateInputPlugin()
        keyEngine.setMode(.normal)
        if let activeWebView = tabManager.activeTab?.webView {
            view.window?.makeFirstResponder(activeWebView)
        }
    }

    private func cancelCurrentInput() {
        PluginRegistry.shared.deactivateInputPlugin()
        keyEngine.setMode(.normal)
        if let activeWebView = tabManager.activeTab?.webView {
            view.window?.makeFirstResponder(activeWebView)
        }
    }
}

// Concrete Open-New-Tab variant of InputPlugin
@MainActor
public final class OpenNewTabInputPlugin: InputPlugin {
    public let id = "input.open-new-tab"
    public let prompt = "NEW TAB"
    public let promptIconName: String? = "globe"
    public let commandAliases = [":tabnew", ":t"]
    public let placeholder = "Enter URL for new tab (e.g. groww.in)..."

    private let inner = OpenUrlInputPlugin(inNewTab: true)

    public func onSubmit(input: String, controller: AnyObject?) {
        inner.onSubmit(input: input, controller: controller)
    }

    public func onCancel(controller: AnyObject?) {
        inner.onCancel(controller: controller)
    }
}
