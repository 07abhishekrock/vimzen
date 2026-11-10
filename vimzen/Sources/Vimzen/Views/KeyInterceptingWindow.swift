import AppKit

public final class KeyInterceptingWindow: NSWindow {
    public var keyEngine: KeyEngine?

    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // Allow parking the window anywhere the user drops it (no system-imposed clamping)
        return frameRect
    }

    public override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if let engine = keyEngine, engine.processKeyEvent(event) {
                // Key was intercepted and handled by Vimzen modal engine — swallow it!
                return
            }
        } else if event.type == .leftMouseDown {
            if let engine = keyEngine, engine.mode == .normal {
                let location = event.locationInWindow
                let windowHeight = contentView?.bounds.height ?? frame.height
                // Clicking anywhere in the webview frame window toggles from NORMAL to INSERT mode
                if location.y >= 26 && location.y <= (windowHeight - 24) {
                    engine.setMode(.insert)
                }
            }
        }
        super.sendEvent(event)
    }
}
