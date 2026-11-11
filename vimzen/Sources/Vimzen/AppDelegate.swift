import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: KeyInterceptingWindow?
    private var mainViewController: MainViewController?
    private var windowBorderView: WindowBorderOverlayView?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupApplicationMenu()

        let defaultWidth: CGFloat = 1240
        let defaultHeight: CGFloat = 800

        let window = KeyInterceptingWindow(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: defaultHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Vimzen"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.hasShadow = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 640, height: 400)
        window.delegate = self

        // Restore user's saved window position and size; default to centered 1240x800 on first launch.
        // E2E test runs get a fixed deterministic frame and no autosave cross-talk.
        if !TestEnvironment.isEnabled {
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
        }

        let controller = MainViewController()
        window.contentViewController = controller
        window.keyEngine = controller.keyEngine

        self.window = window
        self.mainViewController = controller

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Applied after contentViewController assignment: installing the controller
        // sizes the window to MainViewController's initial 1240x800 view frame
        if TestEnvironment.isEnabled {
            window.setFrame(NSRect(x: 60, y: 60, width: 1100, height: 700), display: true)
        }

        // Clip window's root frame (NSThemeFrame) to standard macOS rounded corners
        if let themeFrame = window.contentView?.superview {
            themeFrame.wantsLayer = true
            themeFrame.layer?.cornerRadius = 16.0
            themeFrame.layer?.masksToBounds = true

            // 1px border drawn ABOVE everything including NSTitlebarContainerView
            // (the titlebar container renders a glass material on macOS 26 that would
            // otherwise hide any border placed inside the content view)
            let border = WindowBorderOverlayView(frame: themeFrame.bounds)
            border.autoresizingMask = [.width, .height]
            themeFrame.addSubview(border)
            self.windowBorderView = border
        }
        window.invalidateShadow()
        compactTrafficLights(in: window)
    }

    /// Shrinks the native traffic-light buttons (close/minimize/zoom) and centers
    /// them vertically in the 24px drag header. Stock widgets are 14pt, vertically
    /// centered on the 32px system titlebar — leaving ~9px above and ~1px below
    /// against the header seam. On macOS 26 each widget renders through a SwiftUI
    /// hosting subview (_NSCoreHostingView<ThemeWidgetView>), and AppKit resets
    /// layer transforms during layout — so the transform targets the hosting
    /// view's layer and is re-applied after first layout and on window key events.
    /// The view frames (hit targets) are untouched — only the artwork is scaled.
    private func compactTrafficLights(in window: NSWindow) {
        // 14pt artwork at scale ~0.714 → 10pt. The hosting layer top-aligns scaled
        // artwork in the widget cell and responds to translation as offset/2, so
        // yShift −4 lands it dead-center in the 24px header (~7px padding). The
        // horizontal shifts tighten the 23pt system pitch to 19pt (stock-look gap).
        let scale: CGFloat = 10.0 / 14.0
        let yShift: CGFloat = -2.8
        let xShifts: [NSWindow.ButtonType: CGFloat] = [
            .closeButton: 0,
            .miniaturizeButton: -5.6,
            .zoomButton: -11.2
        ]

        func apply() {
            for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                guard let button = window.standardWindowButton(buttonType) else { continue }
                // macOS 26 renders each widget through a SwiftUI hosting subview —
                // transform that layer exactly once (transforms compound down the tree)
                let targets = button.subviews.isEmpty ? [button] : button.subviews
                for target in targets {
                    target.wantsLayer = true
                    target.layer?.transform = CATransform3DTranslate(
                        CATransform3DMakeScale(scale, scale, 1), xShifts[buttonType] ?? 0, yShift, 0)
                }
            }
        }

        apply()
        // AppKit resets the widget layers during the first layout pass — re-apply after it
        DispatchQueue.main.async { apply() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { apply() }
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

    // MARK: - NSWindowDelegate

    public func windowWillEnterFullScreen(_ notification: Notification) {
        window?.contentView?.superview?.layer?.cornerRadius = 0.0
        mainViewController?.view.layer?.cornerRadius = 0.0
        windowBorderView?.isHidden = true
    }

    public func windowDidExitFullScreen(_ notification: Notification) {
        window?.contentView?.superview?.layer?.cornerRadius = 16.0
        mainViewController?.view.layer?.cornerRadius = 16.0
        windowBorderView?.isHidden = false
        window?.invalidateShadow()
        // Fullscreen transitions can remount the titlebar widgets, dropping the
        // compact transform — re-apply it
        if let window = notification.object as? NSWindow {
            compactTrafficLights(in: window)
        }
    }

    /// Titlebar relayouts on resize can reset the widget layers — re-apply the
    /// compact transform (idempotent, three layer writes).
    public func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            compactTrafficLights(in: window)
        }
    }
}
