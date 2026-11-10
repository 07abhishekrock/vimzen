import AppKit

public final class KeyInterceptingWindow: NSWindow {
    public var keyEngine: KeyEngine?

    public override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if let engine = keyEngine, engine.processKeyEvent(event) {
                // Key was intercepted and handled by Vimzen modal engine — swallow it!
                return
            }
        }
        super.sendEvent(event)
    }
}
