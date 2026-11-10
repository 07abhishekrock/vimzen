import AppKit
import Combine

@MainActor
public final class StatusBarView: NSView {
    private let modeContainer = NSView()
    private let modeLabel = NSTextField(labelWithString: "NORMAL")
    private let pendingKeysLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "Vimzen")
    private let urlLabel = NSTextField(labelWithString: "")
    private let statusIndicator = NSTextField(labelWithString: "Ready")
    private let progressIndicator = NSProgressIndicator()
    private let tabsCountLabel = NSTextField(labelWithString: "0 tabs")

    private var cancellables = Set<AnyCancellable>()
    private var activeTabCancellables = Set<AnyCancellable>()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1.0).cgColor

        // Top border line
        let border = CALayer()
        border.backgroundColor = NSColor(calibratedWhite: 0.20, alpha: 1.0).cgColor
        border.frame = CGRect(x: 0, y: bounds.height - 1, width: 2000, height: 1)
        border.autoresizingMask = [.layerWidthSizable]
        layer?.addSublayer(border)

        // Mode Badge Container with proper padding
        modeContainer.wantsLayer = true
        modeContainer.layer?.cornerRadius = 3
        modeContainer.layer?.masksToBounds = true
        modeContainer.translatesAutoresizingMaskIntoConstraints = false

        modeLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .heavy)
        modeLabel.alignment = .center
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        modeContainer.addSubview(modeLabel)

        // Pending Keys (showcmd)
        pendingKeysLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        pendingKeysLabel.textColor = NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.06, alpha: 1.0)
        pendingKeysLabel.translatesAutoresizingMaskIntoConstraints = false

        // Title Label
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = NSColor(calibratedWhite: 0.90, alpha: 1.0)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // URL Label (max 20 characters)
        urlLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        urlLabel.textColor = NSColor(calibratedWhite: 0.50, alpha: 1.0)
        urlLabel.lineBreakMode = .byClipping
        urlLabel.translatesAutoresizingMaskIntoConstraints = false

        // Status Indicator
        statusIndicator.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        statusIndicator.textColor = NSColor(calibratedWhite: 0.60, alpha: 1.0)
        statusIndicator.translatesAutoresizingMaskIntoConstraints = false

        // Progress Indicator
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        // Tab count
        tabsCountLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        tabsCountLabel.textColor = NSColor(calibratedWhite: 0.50, alpha: 1.0)
        tabsCountLabel.translatesAutoresizingMaskIntoConstraints = false

        // Assemble Left Stack
        let leftStack = NSStackView(views: [modeContainer, pendingKeysLabel, titleLabel, urlLabel])
        leftStack.orientation = .horizontal
        leftStack.spacing = 8
        leftStack.alignment = .centerY
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leftStack)

        // Assemble Right Stack
        let rightStack = NSStackView(views: [progressIndicator, statusIndicator, tabsCountLabel])
        rightStack.orientation = .horizontal
        rightStack.spacing = 8
        rightStack.alignment = .centerY
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rightStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),

            // Mode badge internal padding (6px horizontal, 18px height)
            modeContainer.heightAnchor.constraint(equalToConstant: 18),
            modeLabel.leadingAnchor.constraint(equalTo: modeContainer.leadingAnchor, constant: 6),
            modeLabel.trailingAnchor.constraint(equalTo: modeContainer.trailingAnchor, constant: -6),
            modeLabel.centerYAnchor.constraint(equalTo: modeContainer.centerYAnchor),

            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftStack.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -16),

            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateModeBadge(mode: .normal)
    }

    public func bind(keyEngine: KeyEngine, tabManager: TabManager) {
        cancellables.removeAll()

        keyEngine.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in self?.updateModeBadge(mode: mode) }
            .store(in: &cancellables)

        keyEngine.$pendingKeys
            .receive(on: RunLoop.main)
            .sink { [weak self] keys in self?.pendingKeysLabel.stringValue = keys }
            .store(in: &cancellables)

        tabManager.$tabs
            .receive(on: RunLoop.main)
            .sink { [weak self] tabs in
                self?.tabsCountLabel.stringValue = "\(tabs.count) tab\(tabs.count == 1 ? "" : "s")"
            }
            .store(in: &cancellables)

        // Watch for active tab identity changes and rebind observers
        tabManager.$activeTabId
            .receive(on: RunLoop.main)
            .sink { [weak self, weak tabManager] _ in
                guard let self = self, let tm = tabManager else { return }
                self.updateForActiveTab(tm.activeTab)
            }
            .store(in: &cancellables)

        updateForActiveTab(tabManager.activeTab)
    }

    public func updateForActiveTab(_ tab: Tab?) {
        activeTabCancellables.removeAll()

        guard let tab = tab else {
            titleLabel.stringValue = "Vimzen"
            urlLabel.stringValue = ""
            statusIndicator.stringValue = "Idle"
            progressIndicator.stopAnimation(nil)
            return
        }

        // Live Combine subscription to title & url changes
        Publishers.CombineLatest(tab.$title, tab.$url)
            .receive(on: RunLoop.main)
            .sink { [weak self] (title, url) in
                guard let self = self else { return }
                let displayTitle = title.isEmpty ? (url?.host ?? "Loading...") : title
                self.titleLabel.stringValue = displayTitle
                self.urlLabel.stringValue = self.formatURL(url)
            }
            .store(in: &activeTabCancellables)

        // Live Combine subscription to loading & progress changes
        Publishers.CombineLatest(tab.$isLoading, tab.$estimatedProgress)
            .receive(on: RunLoop.main)
            .sink { [weak self] (isLoading, progress) in
                guard let self = self else { return }
                if isLoading && progress < 1.0 {
                    let percent = max(10, Int(progress * 100))
                    self.statusIndicator.stringValue = "\(percent)%"
                    self.progressIndicator.startAnimation(nil)
                } else {
                    self.statusIndicator.stringValue = "Ready"
                    self.progressIndicator.stopAnimation(nil)
                }
            }
            .store(in: &activeTabCancellables)
    }

    /// Formats the URL so it never exceeds 20 characters, using "..." when truncated.
    private func formatURL(_ url: URL?) -> String {
        guard let url = url else { return "" }
        var str = url.absoluteString

        // Strip protocol prefix for clean display
        if str.hasPrefix("https://") {
            str = String(str.dropFirst(8))
        } else if str.hasPrefix("http://") {
            str = String(str.dropFirst(7))
        }

        // Strip single trailing slash on bare domains (e.g. "groww.in/" -> "groww.in")
        if str.hasSuffix("/") && str.filter({ $0 == "/" }).count == 1 {
            str = String(str.dropLast())
        }

        // Never exceed 20 characters
        if str.count > 20 {
            return String(str.prefix(17)) + "..."
        }
        return str
    }

    private func updateModeBadge(mode: Mode) {
        modeLabel.stringValue = mode.badgeText
        modeLabel.textColor = mode.badgeTextColor
        modeContainer.layer?.backgroundColor = mode.badgeBackgroundColor.cgColor
    }
}
