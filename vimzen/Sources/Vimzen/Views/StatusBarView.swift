import AppKit
import Combine

@MainActor
public final class StatusBarView: NSView, NSTextFieldDelegate {
    private let leftStack = NSStackView()
    private let centerStack = NSStackView()
    private let rightStack = NSStackView()

    // Interactive Toast Container
    private let toastView = NSView()
    private let toastMessageLabel = NSTextField(labelWithString: "")
    private let toastActionBadge = NSView()
    private let toastActionLabel = NSTextField(labelWithString: "u : undo")

    // Input Plugin Takeover View
    private let inputTakeoverView = NSView()
    private let promptContainer = NSView()
    private let promptLabel = NSTextField(labelWithString: "OPEN")
    private let promptArrow = NSTextField(labelWithString: "❯")
    public let inputTextField = NSTextField()
    private let inputHintLabel = NSTextField(labelWithString: "esc: cancel   ↵: confirm")

    public var onInputSubmit: ((String) -> Void)?
    public var onInputCancel: (() -> Void)?

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
        layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1.0).cgColor

        // Top border line
        let border = CALayer()
        border.backgroundColor = NSColor(calibratedWhite: 0.20, alpha: 1.0).cgColor
        border.frame = CGRect(x: 0, y: bounds.height - 1, width: 2000, height: 1)
        border.autoresizingMask = [.layerWidthSizable]
        layer?.addSublayer(border)

        // Slot Stacks
        leftStack.orientation = .horizontal
        leftStack.spacing = 8
        leftStack.alignment = .centerY
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leftStack)

        centerStack.orientation = .horizontal
        centerStack.spacing = 8
        centerStack.alignment = .centerY
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(centerStack)

        rightStack.orientation = .horizontal
        rightStack.spacing = 8
        rightStack.alignment = .centerY
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rightStack)

        setupToastView()
        setupInputTakeoverView()

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),

            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftStack.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -16),

            centerStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        setupSlotSubscriptions()
    }

    private func setupToastView() {
        toastView.wantsLayer = true
        toastView.layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1.0).cgColor
        toastView.isHidden = true
        toastView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toastView)

        toastMessageLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        toastMessageLabel.textColor = NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.06, alpha: 1.0)
        toastMessageLabel.translatesAutoresizingMaskIntoConstraints = false

        toastActionBadge.wantsLayer = true
        toastActionBadge.layer?.backgroundColor = NSColor(calibratedWhite: 0.25, alpha: 1.0).cgColor
        toastActionBadge.layer?.cornerRadius = 3
        toastActionBadge.translatesAutoresizingMaskIntoConstraints = false

        toastActionLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        toastActionLabel.textColor = .white
        toastActionLabel.translatesAutoresizingMaskIntoConstraints = false
        toastActionBadge.addSubview(toastActionLabel)

        let toastStack = NSStackView(views: [toastMessageLabel, toastActionBadge])
        toastStack.orientation = .horizontal
        toastStack.spacing = 8
        toastStack.alignment = .centerY
        toastStack.translatesAutoresizingMaskIntoConstraints = false
        toastView.addSubview(toastStack)

        NSLayoutConstraint.activate([
            toastView.leadingAnchor.constraint(equalTo: leadingAnchor),
            toastView.trailingAnchor.constraint(equalTo: trailingAnchor),
            toastView.topAnchor.constraint(equalTo: topAnchor),
            toastView.bottomAnchor.constraint(equalTo: bottomAnchor),

            toastStack.leadingAnchor.constraint(equalTo: toastView.leadingAnchor, constant: 12),
            toastStack.centerYAnchor.constraint(equalTo: toastView.centerYAnchor),

            toastActionBadge.heightAnchor.constraint(equalToConstant: 16),
            toastActionLabel.leadingAnchor.constraint(equalTo: toastActionBadge.leadingAnchor, constant: 5),
            toastActionLabel.trailingAnchor.constraint(equalTo: toastActionBadge.trailingAnchor, constant: -5),
            toastActionLabel.centerYAnchor.constraint(equalTo: toastActionBadge.centerYAnchor)
        ])
    }

    private func setupInputTakeoverView() {
        inputTakeoverView.wantsLayer = true
        inputTakeoverView.layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1.0).cgColor
        inputTakeoverView.isHidden = true
        inputTakeoverView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(inputTakeoverView)

        promptContainer.wantsLayer = true
        promptContainer.layer?.backgroundColor = NSColor(calibratedRed: 0.61, green: 0.35, blue: 0.71, alpha: 1.0).cgColor
        promptContainer.layer?.cornerRadius = 3
        promptContainer.translatesAutoresizingMaskIntoConstraints = false

        promptLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .heavy)
        promptLabel.textColor = .white
        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        promptContainer.addSubview(promptLabel)

        promptArrow.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        promptArrow.textColor = NSColor(calibratedRed: 0.20, green: 0.60, blue: 1.00, alpha: 1.0)
        promptArrow.translatesAutoresizingMaskIntoConstraints = false

        inputTextField.isBordered = false
        inputTextField.drawsBackground = false
        inputTextField.focusRingType = .none
        inputTextField.isEditable = true
        inputTextField.isSelectable = true
        inputTextField.refusesFirstResponder = false
        inputTextField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        inputTextField.textColor = .white
        inputTextField.delegate = self
        inputTextField.translatesAutoresizingMaskIntoConstraints = false

        inputHintLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        inputHintLabel.textColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
        inputHintLabel.translatesAutoresizingMaskIntoConstraints = false

        inputTakeoverView.addSubview(promptContainer)
        inputTakeoverView.addSubview(promptArrow)
        inputTakeoverView.addSubview(inputTextField)
        inputTakeoverView.addSubview(inputHintLabel)

        NSLayoutConstraint.activate([
            inputTakeoverView.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputTakeoverView.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputTakeoverView.topAnchor.constraint(equalTo: topAnchor),
            inputTakeoverView.bottomAnchor.constraint(equalTo: bottomAnchor),

            promptContainer.leadingAnchor.constraint(equalTo: inputTakeoverView.leadingAnchor, constant: 10),
            promptContainer.centerYAnchor.constraint(equalTo: inputTakeoverView.centerYAnchor),
            promptContainer.heightAnchor.constraint(equalToConstant: 18),
            promptLabel.leadingAnchor.constraint(equalTo: promptContainer.leadingAnchor, constant: 6),
            promptLabel.trailingAnchor.constraint(equalTo: promptContainer.trailingAnchor, constant: -6),
            promptLabel.centerYAnchor.constraint(equalTo: promptContainer.centerYAnchor),

            promptArrow.leadingAnchor.constraint(equalTo: promptContainer.trailingAnchor, constant: 6),
            promptArrow.centerYAnchor.constraint(equalTo: inputTakeoverView.centerYAnchor),

            inputTextField.leadingAnchor.constraint(equalTo: promptArrow.trailingAnchor, constant: 6),
            inputTextField.centerYAnchor.constraint(equalTo: inputTakeoverView.centerYAnchor),
            inputTextField.trailingAnchor.constraint(equalTo: inputHintLabel.leadingAnchor, constant: -12),

            inputHintLabel.trailingAnchor.constraint(equalTo: inputTakeoverView.trailingAnchor, constant: -10),
            inputHintLabel.centerYAnchor.constraint(equalTo: inputTakeoverView.centerYAnchor)
        ])
    }

    private func setupSlotSubscriptions() {
        let registry = PluginRegistry.shared

        // Left Slot binding
        registry.leftSlot.$plugins
            .receive(on: RunLoop.main)
            .sink { [weak self] plugins in
                self?.rebuildStack(self?.leftStack, with: plugins)
            }
            .store(in: &cancellables)

        // Center Slot binding
        registry.centerSlot.$plugins
            .receive(on: RunLoop.main)
            .sink { [weak self] plugins in
                self?.rebuildStack(self?.centerStack, with: plugins)
            }
            .store(in: &cancellables)

        // Right Slot binding
        registry.rightSlot.$plugins
            .receive(on: RunLoop.main)
            .sink { [weak self] plugins in
                self?.rebuildStack(self?.rightStack, with: plugins)
            }
            .store(in: &cancellables)

        // Active Input Plugin Takeover binding
        registry.$activeInputPlugin
            .receive(on: RunLoop.main)
            .sink { [weak self] activePlugin in
                guard let self = self else { return }
                if let plugin = activePlugin {
                    self.showInputTakeover(plugin: plugin)
                } else {
                    self.hideInputTakeover()
                }
            }
            .store(in: &cancellables)

        // Active Notification Toast binding
        registry.$activeToast
            .receive(on: RunLoop.main)
            .sink { [weak self] toast in
                guard let self = self else { return }
                if let toast = toast {
                    self.toastMessageLabel.stringValue = toast.message
                    if let key = toast.actionKey, let label = toast.actionLabel {
                        self.toastActionLabel.stringValue = "\(key) : \(label)"
                        self.toastActionBadge.isHidden = false
                    } else {
                        self.toastActionBadge.isHidden = true
                    }
                    self.toastView.isHidden = false
                } else {
                    self.toastView.isHidden = true
                }
            }
            .store(in: &cancellables)
    }

    private func rebuildStack(_ stack: NSStackView?, with plugins: [ViewPlugin]) {
        guard let stack = stack else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for plugin in plugins {
            stack.addArrangedSubview(plugin.view)
        }
    }

    public func bind(keyEngine: KeyEngine, tabManager: TabManager) {
        // Connect the centralized reactive telemetry bus
        PluginDataBus.shared.attach(keyEngine: keyEngine, tabManager: tabManager)
    }

    private func showInputTakeover(plugin: InputPlugin) {
        promptLabel.stringValue = plugin.prompt
        inputTextField.placeholderString = plugin.placeholder
        inputTakeoverView.isHidden = false
        window?.makeFirstResponder(inputTextField)
    }

    private func hideInputTakeover() {
        inputTakeoverView.isHidden = true
    }

    public func activateInput(prefill: String = "") {
        inputTextField.stringValue = prefill
        window?.makeFirstResponder(inputTextField)
        if !prefill.isEmpty {
            inputTextField.selectText(nil)
        }
    }

    // MARK: - NSTextFieldDelegate

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let input = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            onInputSubmit?(input)
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onInputCancel?()
            return true
        }
        return false
    }
}
