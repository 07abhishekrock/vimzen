import AppKit
import Combine

public enum PluginSlot: Sendable {
    case left
    case center
    case right
}

@MainActor
public struct PluginContext {
    public let mode: Mode
    public let pendingKeys: String
    public let activeTab: Tab?
    public let tabsCount: Int

    public init(mode: Mode, pendingKeys: String, activeTab: Tab?, tabsCount: Int) {
        self.mode = mode
        self.pendingKeys = pendingKeys
        self.activeTab = activeTab
        self.tabsCount = tabsCount
    }
}

@MainActor
public protocol ViewPlugin: AnyObject {
    var id: String { get }
    var position: PluginSlot { get }
    var order: Int { get }
    var view: NSView { get }
    func update(with context: PluginContext)
}

@MainActor
public protocol InputPlugin: AnyObject {
    var id: String { get }
    var prompt: String { get }
    var commandAliases: [String] { get }
    var placeholder: String { get }
    func onSubmit(input: String, controller: AnyObject?)
    func onCancel(controller: AnyObject?)
}

@MainActor
public struct NotificationToast: Identifiable {
    public let id: String
    public let message: String
    public let actionKey: String?
    public let actionLabel: String?
    public let duration: TimeInterval
    public let onAction: (@MainActor () -> Void)?

    public init(
        id: String = UUID().uuidString,
        message: String,
        actionKey: String? = nil,
        actionLabel: String? = nil,
        duration: TimeInterval = 4.0,
        onAction: (@MainActor () -> Void)? = nil
    ) {
        self.id = id
        self.message = message
        self.actionKey = actionKey
        self.actionLabel = actionLabel
        self.duration = duration
        self.onAction = onAction
    }
}
