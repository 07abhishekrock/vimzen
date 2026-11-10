import AppKit

public final class OmnibarView: NSView, NSTextFieldDelegate {
    private let promptContainer = NSView()
    private let promptLabel = NSTextField(labelWithString: "OPEN")
    private let promptArrow = NSTextField(labelWithString: "❯")
    private let textField = NSTextField()
    private let hintLabel = NSTextField(labelWithString: "esc: cancel   ↵: open")

    public var onSubmit: ((String) -> Void)?
    public var onCancel: (() -> Void)?

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
        layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor

        // Top border line matching the status line
        let border = CALayer()
        border.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 1.0).cgColor
        border.frame = CGRect(x: 0, y: bounds.height - 1, width: 2000, height: 1)
        border.autoresizingMask = [.layerWidthSizable]
        layer?.addSublayer(border)

        // Mode badge container for "OPEN"
        promptContainer.wantsLayer = true
        promptContainer.layer?.backgroundColor = NSColor(calibratedRed: 0.61, green: 0.35, blue: 0.71, alpha: 1.0).cgColor
        promptContainer.layer?.cornerRadius = 3
        promptContainer.layer?.masksToBounds = true
        promptContainer.translatesAutoresizingMaskIntoConstraints = false

        promptLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .heavy)
        promptLabel.textColor = .white
        promptLabel.alignment = .center
        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        promptContainer.addSubview(promptLabel)

        // Arrow icon
        promptArrow.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        promptArrow.textColor = NSColor(calibratedRed: 0.20, green: 0.60, blue: 1.00, alpha: 1.0)
        promptArrow.translatesAutoresizingMaskIntoConstraints = false

        // Main input text field
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.isEditable = true
        textField.isSelectable = true
        textField.refusesFirstResponder = false
        textField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        textField.textColor = .white
        textField.placeholderString = "Enter URL or search query (e.g. groww.in, github.com)..."
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false

        // Hint label on right
        hintLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        hintLabel.textColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(promptContainer)
        addSubview(promptArrow)
        addSubview(textField)
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),

            // Badge constraints
            promptContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            promptContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            promptContainer.heightAnchor.constraint(equalToConstant: 18),
            promptLabel.leadingAnchor.constraint(equalTo: promptContainer.leadingAnchor, constant: 6),
            promptLabel.trailingAnchor.constraint(equalTo: promptContainer.trailingAnchor, constant: -6),
            promptLabel.centerYAnchor.constraint(equalTo: promptContainer.centerYAnchor),

            // Arrow
            promptArrow.leadingAnchor.constraint(equalTo: promptContainer.trailingAnchor, constant: 6),
            promptArrow.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Text input
            textField.leadingAnchor.constraint(equalTo: promptArrow.trailingAnchor, constant: 6),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: hintLabel.leadingAnchor, constant: -12),

            // Hint
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            hintLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    public func activate(prefilled: String = "") {
        textField.stringValue = prefilled
        isHidden = false
        window?.makeFirstResponder(textField)
        if !prefilled.isEmpty {
            textField.selectText(nil)
        }
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let input = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !input.isEmpty {
                onSubmit?(input)
            }
            isHidden = true
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            isHidden = true
            onCancel?()
            return true
        }
        return false
    }
}
