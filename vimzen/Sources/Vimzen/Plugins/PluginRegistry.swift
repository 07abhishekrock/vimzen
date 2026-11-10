import AppKit
import Combine

@MainActor
public final class PluginRegistry: ObservableObject {
    public static let shared = PluginRegistry()

    public let leftSlot = StatusSlot(kind: .left)
    public let centerSlot = StatusSlot(kind: .center)
    public let rightSlot = StatusSlot(kind: .right)

    @Published public private(set) var inputPlugins: [String: InputPlugin] = [:]
    @Published public private(set) var activeInputPlugin: InputPlugin?
    @Published public private(set) var activeToast: NotificationToast?
    @Published public private(set) var activeConfirmPrompt: ConfirmPrompt?

    private var toastTimer: Timer?

    public init() {}

    public func slot(for kind: StatusSlotKind) -> StatusSlot {
        switch kind {
        case .left: return leftSlot
        case .center: return centerSlot
        case .right: return rightSlot
        }
    }

    /// Registers a view plugin into a specific status bar slot.
    /// The plugin is automatically bound to the centralized PluginDataBus.
    public func registerViewPlugin(_ plugin: ViewPlugin, into slotKind: StatusSlotKind) {
        plugin.bind(bus: PluginDataBus.shared)
        slot(for: slotKind).add(plugin)
    }

    public func registerInputPlugin(_ plugin: InputPlugin) {
        inputPlugins[plugin.id] = plugin
        for alias in plugin.commandAliases {
            inputPlugins[alias] = plugin
        }
    }

    public func activateInputPlugin(id: String) -> InputPlugin? {
        guard let plugin = inputPlugins[id] else { return nil }
        activeInputPlugin = plugin
        return plugin
    }

    public func deactivateInputPlugin() {
        activeInputPlugin = nil
    }

    public func showToast(_ toast: NotificationToast) {
        toastTimer?.invalidate()
        activeToast = toast
        toastTimer = Timer.scheduledTimer(withTimeInterval: toast.duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.clearToast()
            }
        }
    }

    public func clearToast() {
        toastTimer?.invalidate()
        toastTimer = nil
        activeToast = nil
    }

    public func confirm(
        prompt: String = "CONFIRM",
        promptIcon: String? = "questionmark.circle.fill",
        message: String,
        defaultYes: Bool = true
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let cp = ConfirmPrompt(
                prompt: prompt,
                promptIconName: promptIcon,
                message: message,
                defaultYes: defaultYes
            ) { [weak self] result in
                self?.activeConfirmPrompt = nil
                continuation.resume(returning: result)
            }
            self.activeConfirmPrompt = cp
        }
    }

    public func resolveConfirm(with answer: Bool) {
        guard let prompt = activeConfirmPrompt else { return }
        prompt.onResolve(answer)
    }

    public func dismissConfirm() {
        guard let prompt = activeConfirmPrompt else { return }
        prompt.onResolve(false)
    }
}
