import AppKit
import Combine

public final class WindowDragHeaderView: NSView {
    public override var mouseDownCanMoveWindow: Bool {
        return true
    }

    private let defaultBg = NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.08, alpha: 1.0)
    private var cancellables = Set<AnyCancellable>()
    private var savedFloatingFrame: NSRect?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = defaultBg.cgColor

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    public func bind(bus: PluginDataBus) {
        cancellables.removeAll()
        bus.$activeTabTopColor
            .receive(on: RunLoop.main)
            .sink { [weak self] color in
                guard let self = self else { return }
                let target = color ?? self.defaultBg
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    ctx.allowsImplicitAnimation = true
                    self.layer?.backgroundColor = target.cgColor
                }
            }
            .store(in: &cancellables)
    }

    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            if let win = window {
                guard let targetScreen = win.screen ?? NSScreen.main else { return }
                let visible = targetScreen.visibleFrame
                let isFull = abs(win.frame.width - visible.width) < 10 && abs(win.frame.height - visible.height) < 10

                if isFull {
                    let target = savedFloatingFrame ?? NSRect(
                        x: visible.minX + (visible.width - 1240) / 2,
                        y: visible.minY + (visible.height - 800) / 2,
                        width: 1240,
                        height: 800
                    )
                    win.setFrame(target, display: true, animate: true)
                } else {
                    savedFloatingFrame = win.frame
                    win.setFrame(visible, display: true, animate: true)
                }
            }
            return
        }
        super.mouseDown(with: event)
    }
}
