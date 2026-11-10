import AppKit
import Combine

@MainActor
public final class KeyEngine: ObservableObject {
    @Published public private(set) var mode: Mode = .normal
    @Published public private(set) var pendingKeys: String = ""

    private var countBuffer: String = ""
    private var sequenceBuffer: String = ""
    private var lastKeyTime: Date?

    private weak var tabManager: TabManager?
    public var onTriggerInputPlugin: ((String) -> Void)?
    public var onCancelInputPlugin: (() -> Void)?

    public init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    public func setMode(_ newMode: Mode) {
        mode = newMode
        clearBuffer()
    }

    public func clearBuffer() {
        countBuffer = ""
        sequenceBuffer = ""
        pendingKeys = ""
    }

    /// Returns true if the key event was consumed / swallowed.
    public func processKeyEvent(_ event: NSEvent) -> Bool {
        let isCtrl = event.modifierFlags.contains(.control)

        // COMMAND mode (Input plugin takeover active)
        if mode == .command {
            if event.keyCode == 53 || (isCtrl && event.charactersIgnoringModifiers == "[") {
                // Escape or Ctrl-[ cancels the active input plugin
                setMode(.normal)
                onCancelInputPlugin?()
                return true
            }
            // Pass all keystrokes through to the active input plugin's text field
            return false
        }

        // INSERT mode handling
        if mode == .insert {
            if event.keyCode == 53 || (isCtrl && event.charactersIgnoringModifiers == "[") {
                // Escape or Ctrl-[ exits INSERT mode to NORMAL
                setMode(.normal)
                return true
            }
            // Pass all typing through to the webpage DOM
            return false
        }

        // NORMAL mode: all keys are evaluated or swallowed from the webpage!
        if event.keyCode == 53 { // Escape
            clearBuffer()
            PluginRegistry.shared.clearToast()
            return true
        }

        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
            return false
        }

        let chord: String
        if isCtrl {
            chord = "<C-\(characters.lowercased())>"
        } else {
            chord = characters
        }

        // Check interactive undo toast action hook (e.g. 'u' within 4s restores closed tab)
        if chord == "u", let toast = PluginRegistry.shared.activeToast, toast.actionKey == "u" {
            toast.onAction?()
            PluginRegistry.shared.clearToast()
            clearBuffer()
            return true
        }

        // Check 1000ms chord timeout
        if let last = lastKeyTime, Date().timeIntervalSince(last) > 1.0 {
            sequenceBuffer = ""
        }
        lastKeyTime = Date()

        // Buffer digits for count prefix (e.g. 10j, 3gt) if no sequence started
        if sequenceBuffer.isEmpty, chord.allSatisfy(\.isNumber), !(chord == "0" && countBuffer.isEmpty) {
            countBuffer += chord
            pendingKeys = countBuffer
            return true
        }

        sequenceBuffer += chord
        let count = Int(countBuffer) ?? 1
        pendingKeys = "\(countBuffer)\(sequenceBuffer)"

        return executeCommand(sequenceBuffer, count: count)
    }

    private func executeCommand(_ sequence: String, count: Int) -> Bool {
        guard let tabManager = tabManager else { return true }
        let activeTab = tabManager.activeTab

        switch sequence {
        // Scrolling
        case "j":
            activeTab?.scrollBy(dx: 0, dy: CGFloat(count) * 60)
            clearBuffer()
            return true
        case "k":
            activeTab?.scrollBy(dx: 0, dy: -CGFloat(count) * 60)
            clearBuffer()
            return true
        case "h":
            activeTab?.scrollBy(dx: -CGFloat(count) * 60, dy: 0)
            clearBuffer()
            return true
        case "l":
            activeTab?.scrollBy(dx: CGFloat(count) * 60, dy: 0)
            clearBuffer()
            return true
        case "gg":
            activeTab?.scrollToTop()
            clearBuffer()
            return true
        case "G":
            activeTab?.scrollToBottom()
            clearBuffer()
            return true
        case "<C-d>":
            activeTab?.scrollBy(dx: 0, dy: 300)
            clearBuffer()
            return true
        case "<C-u>":
            activeTab?.scrollBy(dx: 0, dy: -300)
            clearBuffer()
            return true
        case "<C-f>":
            activeTab?.scrollBy(dx: 0, dy: 600)
            clearBuffer()
            return true
        case "<C-b>":
            activeTab?.scrollBy(dx: 0, dy: -600)
            clearBuffer()
            return true

        // Navigation
        case "r":
            activeTab?.reload()
            clearBuffer()
            return true
        case "H":
            activeTab?.goBack()
            clearBuffer()
            return true
        case "L":
            activeTab?.goForward()
            clearBuffer()
            return true

        // Modes
        case "i":
            setMode(.insert)
            return true

        // Tabs
        case "gt":
            tabManager.nextTab()
            clearBuffer()
            return true
        case "gT":
            tabManager.previousTab()
            clearBuffer()
            return true
        case "x", ":q":
            // Close tab and display 4s interactive undo toast (§10.4)
            if let closing = activeTab {
                let savedURL = closing.url
                let savedTitle = closing.title
                tabManager.closeActiveTab()

                let toast = NotificationToast(
                    message: "Closed: \(savedTitle.isEmpty ? (savedURL?.host ?? "Tab") : savedTitle)",
                    actionKey: "u",
                    actionLabel: "undo (4s)",
                    duration: 4.0,
                    onAction: { [weak tabManager] in
                        if let url = savedURL {
                            tabManager?.createTab(url: url, activate: true)
                        }
                    }
                )
                PluginRegistry.shared.showToast(toast)
            }
            clearBuffer()
            return true
        case ":qa":
            NSApp.terminate(nil)
            return true

        // Input Plugins (Takeover Bottom Bar)
        case "o":
            clearBuffer()
            onTriggerInputPlugin?("input.open")
            return true
        case "O":
            clearBuffer()
            onTriggerInputPlugin?("input.open-new-tab")
            return true
        case ":":
            clearBuffer()
            onTriggerInputPlugin?("input.command")
            return true

        default:
            let validPrefixes = ["g", ":"]
            if !validPrefixes.contains(sequence) {
                clearBuffer()
            }
            return true
        }
    }
}
