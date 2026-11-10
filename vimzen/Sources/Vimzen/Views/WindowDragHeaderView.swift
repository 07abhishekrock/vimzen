import AppKit
import Combine

public final class WindowDragHeaderView: NSView {
    private let defaultBg = NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.08, alpha: 1.0)
    private var cancellables = Set<AnyCancellable>()

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
            heightAnchor.constraint(equalToConstant: 28)
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
        window?.performDrag(with: event)
    }
}
