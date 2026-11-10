import AppKit

public final class WindowDragHeaderView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Vimzen")

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
        layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1.0).cgColor

        // Subtle bottom border separating header from webpage content
        let border = CALayer()
        border.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1.0).cgColor
        border.frame = CGRect(x: 0, y: 0, width: 2000, height: 1)
        border.autoresizingMask = [.layerWidthSizable]
        layer?.addSublayer(border)

        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = NSColor(calibratedWhite: 0.35, alpha: 1.0)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    public override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
