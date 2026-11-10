import AppKit
import Combine

@MainActor
public final class PluginRegistry: ObservableObject {
    public static let shared = PluginRegistry()

    @Published public private(set) var viewPlugins: [ViewPlugin] = []
    @Published public private(set) var inputPlugins: [String: InputPlugin] = [:]
    @Published public private(set) var activeInputPlugin: InputPlugin?
    @Published public private(set) var activeToast: NotificationToast?

    private var toastTimer: Timer?

    public init() {}

    public func registerViewPlugin(_ plugin: ViewPlugin) {
        viewPlugins.removeAll(where: { $0.id == plugin.id })
        viewPlugins.append(plugin)
        viewPlugins.sort { $0.order < $1.order }
    }

    public func registerInputPlugin(_ plugin: InputPlugin) {
        inputPlugins[plugin.id] = plugin
        for alias in plugin.commandAliases {
            inputPlugins[alias] = plugin
        }
    }

    public func plugins(for slot: PluginSlot) -> [ViewPlugin] {
        return viewPlugins.filter { $0.position == slot }
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
}
