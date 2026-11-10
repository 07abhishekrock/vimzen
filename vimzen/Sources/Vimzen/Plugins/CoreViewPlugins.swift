import AppKit
import Combine

// MARK: - Mode Badge Plugin

@MainActor
public final class ModeBadgePlugin: ViewPlugin {
    public let id = "core.mode-badge"
    public let order: Int

    public let view = NSView()
    private let label = NSTextField(labelWithString: "NORMAL")
    private var cancellables = Set<AnyCancellable>()

    public init(order: Int = 1) {
        self.order = order

        view.wantsLayer = true
        view.layer?.cornerRadius = 3
        view.layer?.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .heavy)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    public func bind(bus: PluginDataBus) {
        cancellables.removeAll()
        bus.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                self?.label.stringValue = mode.badgeText
                self?.label.textColor = mode.badgeTextColor
                self?.view.layer?.backgroundColor = mode.badgeBackgroundColor.cgColor
            }
            .store(in: &cancellables)
    }
}

// MARK: - Pending Keys Plugin (showcmd)

@MainActor
public final class PendingKeysPlugin: ViewPlugin {
    public let id = "core.pending-keys"
    public let order: Int

    public let view = NSView()
    private let label = NSTextField(labelWithString: "")
    private var cancellables = Set<AnyCancellable>()

    public init(order: Int = 2) {
        self.order = order

        view.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.06, alpha: 1.0)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    public func bind(bus: PluginDataBus) {
        cancellables.removeAll()
        bus.$pendingKeys
            .receive(on: RunLoop.main)
            .sink { [weak self] keys in
                self?.label.stringValue = keys
                self?.view.isHidden = keys.isEmpty
            }
            .store(in: &cancellables)
    }
}

// MARK: - Page Identity Plugin (<title> — <url>)

@MainActor
public final class PageIdentityPlugin: ViewPlugin {
    public let id = "core.page-identity"
    public let order: Int

    public let view = NSView()
    private let titleLabel = NSTextField(labelWithString: "Vimzen")
    private let urlLabel = NSTextField(labelWithString: "")
    private var cancellables = Set<AnyCancellable>()

    public init(order: Int = 3) {
        self.order = order

        view.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = NSColor(calibratedWhite: 0.90, alpha: 1.0)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        urlLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        urlLabel.textColor = NSColor(calibratedWhite: 0.50, alpha: 1.0)
        urlLabel.lineBreakMode = .byClipping
        urlLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, urlLabel])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    public func bind(bus: PluginDataBus) {
        cancellables.removeAll()
        Publishers.CombineLatest(bus.$activeTabTitle, bus.$activeTabURL)
            .receive(on: RunLoop.main)
            .sink { [weak self] title, url in
                guard let self = self else { return }
                if title.isEmpty && url == nil {
                    self.titleLabel.stringValue = "Vimzen"
                    self.urlLabel.stringValue = ""
                } else {
                    let displayTitle = title.isEmpty ? (url?.host ?? "Loading...") : title
                    self.titleLabel.stringValue = displayTitle
                    self.urlLabel.stringValue = self.formatURL(url)
                }
            }
            .store(in: &cancellables)
    }

    /// Strict <= 20 character capping with "..."
    private func formatURL(_ url: URL?) -> String {
        guard let url = url else { return "" }
        var str = url.absoluteString

        if str.hasPrefix("https://") {
            str = String(str.dropFirst(8))
        } else if str.hasPrefix("http://") {
            str = String(str.dropFirst(7))
        }

        if str.hasSuffix("/") && str.filter({ $0 == "/" }).count == 1 {
            str = String(str.dropLast())
        }

        if str.count > 20 {
            return String(str.prefix(17)) + "..."
        }
        return str
    }
}

// MARK: - Loading Status Plugin

@MainActor
public final class LoadingStatusPlugin: ViewPlugin {
    public let id = "core.load-status"
    public let order: Int

    public let view = NSView()
    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private var cancellables = Set<AnyCancellable>()

    public init(order: Int = 10) {
        self.order = order

        view.translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = NSColor(calibratedWhite: 0.60, alpha: 1.0)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [spinner, statusLabel])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    public func bind(bus: PluginDataBus) {
        cancellables.removeAll()
        Publishers.CombineLatest(bus.$isLoading, bus.$estimatedProgress)
            .receive(on: RunLoop.main)
            .sink { [weak self] isLoading, progress in
                guard let self = self else { return }
                if isLoading && progress < 1.0 {
                    let percent = max(10, Int(progress * 100))
                    self.statusLabel.stringValue = "\(percent)%"
                    self.spinner.startAnimation(nil)
                } else {
                    self.statusLabel.stringValue = "Ready"
                    self.spinner.stopAnimation(nil)
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Tabs Count Plugin

@MainActor
public final class TabsCountPlugin: ViewPlugin {
    public let id = "core.tabs-count"
    public let order: Int

    public let view = NSView()
    private let label = NSTextField(labelWithString: "0 tabs")
    private var cancellables = Set<AnyCancellable>()

    public init(order: Int = 20) {
        self.order = order

        view.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = NSColor(calibratedWhite: 0.50, alpha: 1.0)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    public func bind(bus: PluginDataBus) {
        cancellables.removeAll()
        bus.$tabsCount
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                self?.label.stringValue = "\(count) tab\(count == 1 ? "" : "s")"
            }
            .store(in: &cancellables)
    }
}
