import AppKit
import WebKit

@MainActor
public final class VimzenScriptBridge: NSObject, WKScriptMessageHandler {
    public weak var tab: Tab?

    public static let injectedScriptSource: String = """
    (function() {
        if (window.vimzen) return;
        window.vimzen = {
            setTopColor: function(color) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vimzen) {
                    window.webkit.messageHandlers.vimzen.postMessage({
                        action: 'setTopColor',
                        color: String(color)
                    });
                }
            },
            resetTopColor: function() {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vimzen) {
                    window.webkit.messageHandlers.vimzen.postMessage({
                        action: 'resetTopColor'
                    });
                }
            },
            showToast: function(message, duration) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vimzen) {
                    window.webkit.messageHandlers.vimzen.postMessage({
                        action: 'showToast',
                        message: String(message),
                        duration: Number(duration) || 3.0
                    });
                }
            },
            exec: function(command) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vimzen) {
                    window.webkit.messageHandlers.vimzen.postMessage({
                        action: 'exec',
                        command: String(command)
                    });
                }
            }
        };
    })();
    """

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "vimzen",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }

        switch action {
        case "setTopColor":
            if let colorStr = body["color"] as? String,
               let parsed = ColorParser.parse(colorStr) {
                tab?.setCustomTopColor(parsed)
            }

        case "resetTopColor":
            tab?.setCustomTopColor(nil)

        case "showToast":
            let msg = body["message"] as? String ?? ""
            let dur = body["duration"] as? Double ?? 3.0
            PluginRegistry.shared.showToast(NotificationToast(message: msg, duration: dur))

        case "exec":
            if let cmd = body["command"] as? String,
               let mainVC = NSApp.keyWindow?.contentViewController as? MainViewController {
                CommandInputPlugin().onSubmit(input: cmd, controller: mainVC)
            }

        case "saveScratchpad":
            if let text = body["text"] as? String, let profileId = tab?.profileId {
                ScratchpadStore.saveNotes(text, for: profileId)
            }

        default:
            break
        }
    }
}
