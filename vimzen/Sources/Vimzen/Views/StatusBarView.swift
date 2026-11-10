import AppKit
import Combine

@MainActor
public final class StatusBarView: NSView {
    private let modeLabel = NSTextField(labelWithString: "NORMAL")
    private let pendingKeysLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "Vimzen")
    private let urlLabel = NSTextField(labelWithString: "")
    private let statusIndicator = NSTextField(labelWithString: "Ready")
    private let progressIndicator = NSProgressIndicator()
    private let tabsCountLabel = NSTextField(labelWithString: "0 tabs")

    private var cancellables = Set<AnyCancellable>()

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

        // Mode Badge
        modeLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        modeLabel.alignment = .center
        modeLabel.wantsLayer = true
        modeLabel.layer?.cornerRadius = 3
        modeLabel.layer?.masksToBounds = true
        modeLabel.translatesAutoresizingMaskIntoConstraints = false

        // Pending Keys (showcmd)
        pendingKeysLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        pendingKeysLabel.textColor = NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.06, alpha: 1.0)
        pendingKeysLabel.translatesAutoresizingMaskIntoConstraints = false

        // Title Label
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = NSColor(calibratedWhite: 0.90, alpha: 1.0)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // URL Label
        urlLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        urlLabel.textColor = NSColor(calibratedWhite: 0.55, alpha: 1.0)
        urlLabel.lineBreakMode = .byTruncatingTail
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
        let leftStack = NSStackView(views: [modeLabel, pendingKeysLabel, titleLabel, urlLabel])
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

            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftStack.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -16),

            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            modeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 58),
            modeLabel.heightAnchor.constraint(equalToConstant: 16)
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

        tabManager.$activeTabId
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateForActiveTab(tabManager.activeTab)
            }
            .store(in: &cancellables)
    }

    public func updateForActiveTab(_ tab: Tab?) {
        guard let tab = tab else {
            titleLabel.stringValue = "Vimzen"
            urlLabel.stringValue = "Zen workspace — press 'o' to open URL"
            statusIndicator.stringValue = "Idle"
            progressIndicator.stopAnimation(nil)
            return
        }

        titleLabel.stringValue = tab.title.isEmpty ? (tab.url?.host ?? "New Tab") : tab.title
        urlLabel.stringValue = tab.url?.absoluteString ?? ""

        if tab.isLoading {
            statusIndicator.stringValue = "\(Int(tab.estimatedProgress * 100))%"
            progressIndicator.startAnimation(nil)
        } else {
            statusIndicator.stringValue = "Ready"
            progressIndicator.stopAnimation(nil)
        }
    }

    private func updateModeBadge(mode: Mode) {
        modeLabel.stringValue = " \(mode.badgeText) "
        modeLabel.textColor = mode.badgeTextColor
        modeLabel.layer?.backgroundColor = mode.badgeBackgroundColor.cgColor
    }
}
