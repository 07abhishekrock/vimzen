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
    public var onOpenPrompt: ((Bool) -> Void)? // bool: open in new tab
    public var onCancelPrompt: (() -> Void)?

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

        // COMMAND mode (Omnibar is active): Pass all keystrokes to the NSTextField
        if mode == .command {
            if event.keyCode == 53 || (isCtrl && event.charactersIgnoringModifiers == "[") {
                // Escape or Ctrl-[ cancels Omnibar
                setMode(.normal)
                onCancelPrompt?()
                return true
            }
            // Pass all letters, numbers, spaces, enter, etc. through to the Omnibar
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

        // We are in NORMAL mode: all keys are evaluated or swallowed from the web page!
        if event.keyCode == 53 { // Escape
            clearBuffer()
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
            tabManager.closeActiveTab()
            clearBuffer()
            return true
        case ":qa":
            NSApp.terminate(nil)
            return true

        // Omnibar inputs
        case "o":
            clearBuffer()
            onOpenPrompt?(false)
            return true
        case "O":
            clearBuffer()
            onOpenPrompt?(true)
            return true

        default:
            // Check if sequence is a prefix for any valid sequence (e.g. 'g' for 'gg' or 'gt', ':' for ':q')
            let validPrefixes = ["g", ":"]
            if !validPrefixes.contains(sequence) {
                clearBuffer()
            }
            return true
        }
    }
}
