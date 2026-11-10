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
    public var onComboboxMove: ((Int) -> Void)?
    public var onComboboxSubmitNewTab: (() -> Void)?

    public init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    public func setMode(_ newMode: Mode) {
        mode = newMode
        clearBuffer()
        if newMode == .insert {
            tabManager?.activeTab?.focusEditorIfNewTab()
        } else if newMode == .normal {
            tabManager?.activeTab?.blurEditorIfNewTab()
        }
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

            // Route Ctrl-j / Ctrl-k to combobox row selection
            if isCtrl && event.charactersIgnoringModifiers == "j" {
                onComboboxMove?(1)
                return true
            }
            if isCtrl && event.charactersIgnoringModifiers == "k" {
                onComboboxMove?(-1)
                return true
            }

            // Route Ctrl-Return / Cmd-Return / Shift-Return to submit custom query in a new tab
            if event.keyCode == 36 {
                let isCmd = event.modifierFlags.contains(.command)
                let isShift = event.modifierFlags.contains(.shift)
                if isCtrl || isCmd || isShift {
                    onComboboxSubmitNewTab?()
                    return true
                }
            }

            // Pass all other keystrokes through to the active input plugin's text field
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

        let chord: String
        if isCtrl {
            guard let base = event.charactersIgnoringModifiers?.lowercased(), !base.isEmpty else {
                return false
            }
            if event.keyCode == 48 {
                chord = "<C-Tab>"
            } else {
                chord = "<C-\(base)>"
            }
        } else {
            // Use event.characters so Shift produces uppercase 'H', 'L', 'G', 'O', 'R'
            guard let chars = event.characters, !chars.isEmpty else {
                return false
            }
            if event.keyCode == 48 {
                chord = "<Tab>"
            } else {
                chord = chars
            }
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
        case "R":
            activeTab?.reloadFromOrigin()
            clearBuffer()
            return true
        case "H":
            activeTab?.goBack(count: count)
            clearBuffer()
            return true
        case "L":
            activeTab?.goForward(count: count)
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
        case "gd":
            tabManager.nextSameDomainTab(count: count)
            clearBuffer()
            return true
        case "gD":
            tabManager.previousSameDomainTab(count: count)
            clearBuffer()
            return true
        case "<C-6>", "<C-^>", "g<Tab>", "<C-Tab>":
            tabManager.switchToLastActiveTab()
            clearBuffer()
            return true
        case "<C-p>":
            tabManager.switchToLastActiveProfile()
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
        case "gh", ",h":
            clearBuffer()
            onTriggerInputPlugin?("input.history-picker")
            return true
        case "gp":
            clearBuffer()
            onTriggerInputPlugin?("input.profile-picker")
            return true
        case "gP":
            clearBuffer()
            onTriggerInputPlugin?("input.move-tab-profile")
            return true
        case "b", "T":
            clearBuffer()
            onTriggerInputPlugin?("input.tab-picker")
            return true
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
            let validPrefixes = ["g", ":", ","]
            if !validPrefixes.contains(sequence) {
                clearBuffer()
            }
            return true
        }
    }
}
