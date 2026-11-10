import AppKit

// MARK: - Mode Badge Plugin

@MainActor
public final class ModeBadgePlugin: ViewPlugin {
    public let id = "core.mode-badge"
    public let position = PluginSlot.left
    public let order = 1

    public let view = NSView()
    private let label = NSTextField(labelWithString: "NORMAL")

    public init() {
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

    public func update(with context: PluginContext) {
        label.stringValue = context.mode.badgeText
        label.textColor = context.mode.badgeTextColor
        view.layer?.backgroundColor = context.mode.badgeBackgroundColor.cgColor
    }
}

// MARK: - Pending Keys Plugin (showcmd)

@MainActor
public final class PendingKeysPlugin: ViewPlugin {
    public let id = "core.pending-keys"
    public let position = PluginSlot.left
    public let order = 2

    public let view = NSView()
    private let label = NSTextField(labelWithString: "")

    public init() {
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

    public func update(with context: PluginContext) {
        label.stringValue = context.pendingKeys
        view.isHidden = context.pendingKeys.isEmpty
    }
}

// MARK: - Page Identity Plugin (<title> — <url>)

@MainActor
public final class PageIdentityPlugin: ViewPlugin {
    public let id = "core.page-identity"
    public let position = PluginSlot.left
    public let order = 3

    public let view = NSView()
    private let titleLabel = NSTextField(labelWithString: "Vimzen")
    private let urlLabel = NSTextField(labelWithString: "")

    public init() {
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

    public func update(with context: PluginContext) {
        guard let tab = context.activeTab else {
            titleLabel.stringValue = "Vimzen"
            urlLabel.stringValue = ""
            return
        }

        let displayTitle = tab.title.isEmpty ? (tab.url?.host ?? "Loading...") : tab.title
        titleLabel.stringValue = displayTitle
        urlLabel.stringValue = formatURL(tab.url)
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
    public let position = PluginSlot.right
    public let order = 10

    public let view = NSView()
    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "Ready")

    public init() {
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

    public func update(with context: PluginContext) {
        guard let tab = context.activeTab else {
            statusLabel.stringValue = "Idle"
            spinner.stopAnimation(nil)
            return
        }

        if tab.isLoading && tab.estimatedProgress < 1.0 {
            let percent = max(10, Int(tab.estimatedProgress * 100))
            statusLabel.stringValue = "\(percent)%"
            spinner.startAnimation(nil)
        } else {
            statusLabel.stringValue = "Ready"
            spinner.stopAnimation(nil)
        }
    }
}

// MARK: - Tabs Count Plugin

@MainActor
public final class TabsCountPlugin: ViewPlugin {
    public let id = "core.tabs-count"
    public let position = PluginSlot.right
    public let order = 20

    public let view = NSView()
    private let label = NSTextField(labelWithString: "0 tabs")

    public init() {
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

    public func update(with context: PluginContext) {
        label.stringValue = "\(context.tabsCount) tab\(context.tabsCount == 1 ? "" : "s")"
    }
}
