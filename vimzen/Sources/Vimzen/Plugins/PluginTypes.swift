import AppKit
import Combine

public enum StatusSlotKind: String, Sendable, CaseIterable {
    case left
    case center
    case right
}

/// A layout container in the status bar that hosts ordered ViewPlugins.
@MainActor
public final class StatusSlot: ObservableObject {
    public let kind: StatusSlotKind
    @Published public private(set) var plugins: [ViewPlugin] = []

    public init(kind: StatusSlotKind) {
        self.kind = kind
    }

    public func add(_ plugin: ViewPlugin) {
        plugins.removeAll(where: { $0.id == plugin.id })
        plugins.append(plugin)
        plugins.sort { $0.order < $1.order }
    }

    public func remove(id: String) {
        plugins.removeAll(where: { $0.id == id })
    }

    public func clear() {
        plugins.removeAll()
    }
}

/// Passive status line view element. Does not determine its own slot position.
/// Receives the centralized `PluginDataBus` to selectively subscribe to needed state.
@MainActor
public protocol ViewPlugin: AnyObject {
    var id: String { get }
    var order: Int { get }
    var isFlexible: Bool { get }
    var view: NSView { get }
    func bind(bus: PluginDataBus)
}

extension ViewPlugin {
    public var isFlexible: Bool { false }
}

/// Modal command bar takeover element (e.g. :open, :find, :command).
@MainActor
public protocol InputPlugin: AnyObject {
    var id: String { get }
    var prompt: String { get }
    var promptIconName: String? { get }
    var commandAliases: [String] { get }
    var placeholder: String { get }
    var isComboboxEnabled: Bool { get }
    func queryItems(query: String) async -> [RankedResult]
    func queryItemsStreaming(
        query: String,
        onUpdate: @escaping @MainActor ([RankedResult]) -> Void
    ) async
    func onSubmit(input: String, controller: AnyObject?)
    func onCancel(controller: AnyObject?)
}

extension InputPlugin {
    public var promptIconName: String? { nil }
    public var isComboboxEnabled: Bool { false }
    public func queryItems(query: String) async -> [RankedResult] { [] }
    public func queryItemsStreaming(
        query: String,
        onUpdate: @escaping @MainActor ([RankedResult]) -> Void
    ) async {
        let results = await queryItems(query: query)
        onUpdate(results)
    }
}

/// Transient status bar toast notification with optional interactive shortcut key.
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
        duration: TimeInterval = 1.0,
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

/// Interactive confirmation prompt modal (Category 4: Y/n bar takeover).
@MainActor
public struct ConfirmPrompt: Identifiable {
    public let id: String
    public let prompt: String
    public let promptIconName: String?
    public let message: String
    public let defaultYes: Bool
    public let onResolve: @MainActor (Bool) -> Void

    public init(
        id: String = UUID().uuidString,
        prompt: String = "CONFIRM",
        promptIconName: String? = "questionmark.circle.fill",
        message: String,
        defaultYes: Bool = true,
        onResolve: @escaping @MainActor (Bool) -> Void
    ) {
        self.id = id
        self.prompt = prompt
        self.promptIconName = promptIconName
        self.message = message
        self.defaultYes = defaultYes
        self.onResolve = onResolve
    }
}
