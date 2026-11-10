import AppKit

@MainActor
public final class MainViewController: NSViewController {
    public let tabManager = TabManager()
    public lazy var keyEngine = KeyEngine(tabManager: tabManager)

    private let dragHeader = WindowDragHeaderView()
    private let statusBar = StatusBarView()
    private let omnibar = OmnibarView()
    private var openInNewTab: Bool = false

    public override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1024, height: 720))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1.0).cgColor
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupHierarchy()
        setupBindings()
    }

    private func setupHierarchy() {
        // Draggable window header at top
        dragHeader.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dragHeader)

        // Tab container view
        let container = tabManager.containerView
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        // Status bar view
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBar)

        // Omnibar overlay (docks directly on the bottom bar)
        omnibar.isHidden = true
        omnibar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(omnibar)

        NSLayoutConstraint.activate([
            // Draggable top header (28px)
            dragHeader.topAnchor.constraint(equalTo: view.topAnchor),
            dragHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dragHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dragHeader.heightAnchor.constraint(equalToConstant: 28),

            // Webview container takes between drag header and bottom bar
            container.topAnchor.constraint(equalTo: dragHeader.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            // Status bar at bottom (26px)
            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 26),

            // Omnibar mounts directly on the bottom bar itself
            omnibar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            omnibar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            omnibar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            omnibar.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    private func setupBindings() {
        statusBar.bind(keyEngine: keyEngine, tabManager: tabManager)

        keyEngine.onOpenPrompt = { [weak self] newTab in
            guard let self = self else { return }
            self.openInNewTab = newTab
            let prefill = newTab ? "" : (self.tabManager.activeTab?.url?.absoluteString ?? "")
            self.keyEngine.setMode(.command)
            self.omnibar.activate(prefilled: prefill)
        }

        keyEngine.onCancelPrompt = { [weak self] in
            guard let self = self else { return }
            self.omnibar.isHidden = true
            if let activeWebView = self.tabManager.activeTab?.webView {
                self.view.window?.makeFirstResponder(activeWebView)
            }
        }

        omnibar.onSubmit = { [weak self] input in
            guard let self = self else { return }
            self.navigateTo(input: input, inNewTab: self.openInNewTab)
            self.keyEngine.setMode(.normal)
        }

        omnibar.onCancel = { [weak self] in
            guard let self = self else { return }
            self.keyEngine.setMode(.normal)
            if let activeWebView = self.tabManager.activeTab?.webView {
                self.view.window?.makeFirstResponder(activeWebView)
            }
        }
    }

    private func navigateTo(input: String, inNewTab: Bool) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let targetURL: URL
        if trimmed.starts(with: "http://") || trimmed.starts(with: "https://") {
            targetURL = URL(string: trimmed) ?? URL(string: "https://google.com/search?q=\(trimmed)")!
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            targetURL = URL(string: "https://\(trimmed)")!
        } else {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            targetURL = URL(string: "https://www.google.com/search?q=\(encoded)")!
        }

        if inNewTab || tabManager.activeTab == nil {
            tabManager.createTab(url: targetURL, activate: true)
        } else {
            tabManager.activeTab?.load(url: targetURL)
        }
    }
}
