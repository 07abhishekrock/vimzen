import AppKit
import Combine

// MARK: - Mode Badge Plugin

@MainActor
public final class ModeBadgePlugin: ViewPlugin {
    public let id = "core.mode-badge"
    public let order: Int

    public let view = NSView()
    private let iconView = NSImageView()
    private var cancellables = Set<AnyCancellable>()

    public init(order: Int = 1) {
        self.order = order

        view.wantsLayer = true
        view.layer?.cornerRadius = 0
        view.layer?.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(iconView)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 26),
            view.widthAnchor.constraint(equalToConstant: 32),

            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    public func bind(bus: PluginDataBus) {
        cancellables.removeAll()
        bus.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
                self?.iconView.image = NSImage(systemSymbolName: mode.symbolIconName, accessibilityDescription: mode.rawValue)?.withSymbolConfiguration(config)
                self?.iconView.contentTintColor = mode.badgeTextColor
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

// MARK: - Page Title Plugin (Flexible width web title)

@MainActor
public final class PageIdentityPlugin: ViewPlugin {
    public let id = "core.page-identity"
    public let order: Int
    public let isFlexible: Bool = true

    public let view = NSView()
    private let titleLabel = NSTextField(labelWithString: "Vimzen")
    private var cancellables = Set<AnyCancellable>()

    public init(order: Int = 3) {
        self.order = order

        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        titleLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = NSColor(calibratedWhite: 0.90, alpha: 1.0)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
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
                } else if !title.isEmpty {
                    self.titleLabel.stringValue = title
                } else {
                    self.titleLabel.stringValue = url?.host ?? "Loading..."
                }
            }
            .store(in: &cancellables)
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

        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
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
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor(calibratedWhite: 0.50, alpha: 1.0)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
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

// MARK: - Profile Badge Plugin (Extreme Right of Status Bar)

@MainActor
public final class ProfileBadgePlugin: ViewPlugin {
    public let id = "core.profile-badge"
    public let order: Int

    public let view = NSView()
    private let badgeLabel = NSTextField(labelWithString: "[pers]")
    private var cancellables = Set<AnyCancellable>()

    public init(order: Int = 100) {
        self.order = order

        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = false

        badgeLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        badgeLabel.textColor = NSColor(calibratedRed: 0.35, green: 0.78, blue: 0.98, alpha: 1.0)
        badgeLabel.alignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 18),
            badgeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            badgeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            badgeLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    public func bind(bus: PluginDataBus) {
        cancellables.removeAll()
        bus.$activeProfile
            .receive(on: RunLoop.main)
            .sink { [weak self] profile in
                guard let self = self else { return }
                self.badgeLabel.stringValue = "[\(profile.badge)]"
                if profile.badge == "work" {
                    self.badgeLabel.textColor = NSColor(calibratedRed: 1.00, green: 0.58, blue: 0.00, alpha: 1.0)
                } else if profile.badge == "anon" {
                    self.badgeLabel.textColor = NSColor(calibratedRed: 0.69, green: 0.32, blue: 0.87, alpha: 1.0)
                } else {
                    self.badgeLabel.textColor = NSColor(calibratedRed: 0.35, green: 0.78, blue: 0.98, alpha: 1.0)
                }
            }
            .store(in: &cancellables)
    }
}
