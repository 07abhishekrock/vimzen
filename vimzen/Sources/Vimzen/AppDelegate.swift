import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: KeyInterceptingWindow?
    private var mainViewController: MainViewController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupApplicationMenu()

        let defaultWidth: CGFloat = 1240
        let defaultHeight: CGFloat = 800

        let window = KeyInterceptingWindow(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: defaultHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .fullScreen],
            backing: .buffered,
            defer: false
        )

        window.title = "Vimzen"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1.0)
        window.minSize = NSSize(width: 640, height: 400)

        // Restore user's saved window position and size; default to centered 1240x800 on first launch
        window.setFrameAutosaveName("VimzenMainWindow")
        if !window.setFrameUsingName("VimzenMainWindow") {
            if let screen = NSScreen.main {
                let x = (screen.visibleFrame.width - defaultWidth) / 2 + screen.visibleFrame.minX
                let y = (screen.visibleFrame.height - defaultHeight) / 2 + screen.visibleFrame.minY
                window.setFrame(NSRect(x: x, y: y, width: defaultWidth, height: defaultHeight), display: true)
            } else {
                window.center()
            }
        }

        let controller = MainViewController()
        window.contentViewController = controller
        window.keyEngine = controller.keyEngine

        self.window = window
        self.mainViewController = controller

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            mainViewController?.tabManager.createTab(url: url, activate: true)
        }
    }

    private func setupApplicationMenu() {
        let mainMenu = NSMenu()

        // App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Vimzen", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Vimzen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(newTabMenuAction), keyEquivalent: "t")
        newTabItem.target = self
        fileMenu.addItem(newTabItem)

        let closeTabItem = NSMenuItem(title: "Close Tab", action: #selector(closeTabMenuAction), keyEquivalent: "w")
        closeTabItem.target = self
        fileMenu.addItem(closeTabItem)

        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit Menu (needed for clipboard Cmd+C, Cmd+V, Cmd+A inside inputs)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View Menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let fullScreenItem = NSMenuItem(title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fullScreenItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // History Menu
        let historyMenuItem = NSMenuItem()
        let historyMenu = NSMenu(title: "History")
        let backItem = NSMenuItem(title: "Back", action: #selector(backMenuAction), keyEquivalent: "[")
        backItem.target = self
        historyMenu.addItem(backItem)

        let forwardItem = NSMenuItem(title: "Forward", action: #selector(forwardMenuAction), keyEquivalent: "]")
        forwardItem.target = self
        historyMenu.addItem(forwardItem)

        historyMenuItem.submenu = historyMenu
        mainMenu.addItem(historyMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func backMenuAction() {
        mainViewController?.tabManager.activeTab?.goBack()
    }

    @objc private func forwardMenuAction() {
        mainViewController?.tabManager.activeTab?.goForward()
    }

    @objc private func newTabMenuAction() {
        mainViewController?.keyEngine.onTriggerInputPlugin?("input.open-new-tab")
    }

    @objc private func closeTabMenuAction() {
        mainViewController?.tabManager.closeActiveTab()
    }
}
