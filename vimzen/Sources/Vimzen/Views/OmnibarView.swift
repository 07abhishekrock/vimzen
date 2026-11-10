import AppKit

public final class OmnibarView: NSView, NSTextFieldDelegate {
    private let textField = NSTextField()
    private let promptIcon = NSTextField(labelWithString: "❯")

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
        layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 0.98).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(calibratedRed: 0.20, green: 0.60, blue: 1.00, alpha: 0.6).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.5
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -4)

        promptIcon.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        promptIcon.textColor = NSColor(calibratedRed: 0.20, green: 0.60, blue: 1.00, alpha: 1.0)
        promptIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(promptIcon)

        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.isEditable = true
        textField.isSelectable = true
        textField.refusesFirstResponder = false
        textField.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        textField.textColor = NSColor.white
        textField.placeholderString = "Search or enter address (e.g. groww.in, github.com)..."
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),

            promptIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            promptIcon.centerYAnchor.constraint(equalTo: centerYAnchor),

            textField.leadingAnchor.constraint(equalTo: promptIcon.trailingAnchor, constant: 10),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor)
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
