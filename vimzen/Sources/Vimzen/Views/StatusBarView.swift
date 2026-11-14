import AppKit
import Combine

extension NSTextView {
    /// Disables native text assists (spellcheck, completion popup, smart quotes,
    /// autocorrection…) — the vim command bar is raw input, none of these apply.
    func disableTextAssists() {
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticTextCompletionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
    }
}

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
    private let promptIconView = NSImageView()
    private let promptArrow = NSTextField(labelWithString: "❯")
    public let inputTextField = NSTextField()
    private let inputHintLabel = NSTextField(labelWithString: "esc: cancel   ↵: confirm")

    // Confirm Prompt Takeover View (Category 4)
    private let confirmTakeoverView = NSView()
    private let confirmPromptContainer = NSView()
    private let confirmPromptIconView = NSImageView()
    private let confirmPromptArrow = NSTextField(labelWithString: "❯")
    private let confirmMessageLabel = NSTextField(labelWithString: "")
    private let confirmChoiceLabel = NSTextField(labelWithString: "[Y/n]")
    private let confirmHintLabel = NSTextField(labelWithString: "↵/y: yes   n/esc: cancel")

    public weak var combobox: ComboboxView?
    private var queryTask: Task<Void, Never>?

    public var onInputSubmit: ((String, _ openInNewTab: Bool) -> Void)?
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

        // Slot Stacks - Zero horizontal padding, filling the 26px height
        leftStack.orientation = .horizontal
        leftStack.spacing = 8
        leftStack.alignment = .centerY
        leftStack.distribution = .fill
        leftStack.setHuggingPriority(.defaultLow, for: .horizontal)
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leftStack)

        centerStack.orientation = .horizontal
        centerStack.spacing = 8
        centerStack.alignment = .centerY
        centerStack.distribution = .fill
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(centerStack)

        rightStack.orientation = .horizontal
        rightStack.spacing = 8
        rightStack.alignment = .centerY
        rightStack.distribution = .fill
        rightStack.setHuggingPriority(.required, for: .horizontal)
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rightStack)

        setupToastView()
        setupInputTakeoverView()

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),

            // Left slot spans from x = 0 (flush against left window frame)
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftStack.topAnchor.constraint(equalTo: topAnchor),
            leftStack.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Right slot hugs its content tightly and stays at the extreme right
            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightStack.topAnchor.constraint(equalTo: topAnchor),
            rightStack.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Left stack (and flexible title inside) expands across full bar, pushing right items to the extreme right
            leftStack.trailingAnchor.constraint(equalTo: rightStack.leadingAnchor, constant: -16)
        ])

        setupSlotSubscriptions()
    }

    private func setupToastView() {
        toastView.wantsLayer = true
        toastView.layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1.0).cgColor
        toastView.isHidden = true
        toastView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toastView)

        toastMessageLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
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

            toastStack.leadingAnchor.constraint(equalTo: toastView.leadingAnchor, constant: 8),
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
        promptContainer.layer?.cornerRadius = 0
        promptContainer.translatesAutoresizingMaskIntoConstraints = false

        promptIconView.imageScaling = .scaleProportionallyDown
        promptIconView.contentTintColor = .white
        promptIconView.translatesAutoresizingMaskIntoConstraints = false
        promptContainer.addSubview(promptIconView)

        promptArrow.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        promptArrow.textColor = NSColor(calibratedRed: 0.20, green: 0.60, blue: 1.00, alpha: 1.0)
        promptArrow.translatesAutoresizingMaskIntoConstraints = false

        inputTextField.isBordered = false
        inputTextField.drawsBackground = false
        inputTextField.focusRingType = .none
        inputTextField.isEditable = true
        inputTextField.isSelectable = true
        inputTextField.refusesFirstResponder = false
        inputTextField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        inputTextField.textColor = .white
        inputTextField.delegate = self
        inputTextField.translatesAutoresizingMaskIntoConstraints = false

        inputHintLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
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

            // Flush against left edge with 32px width and full 26px height
            promptContainer.leadingAnchor.constraint(equalTo: inputTakeoverView.leadingAnchor),
            promptContainer.topAnchor.constraint(equalTo: inputTakeoverView.topAnchor),
            promptContainer.bottomAnchor.constraint(equalTo: inputTakeoverView.bottomAnchor),
            promptContainer.widthAnchor.constraint(equalToConstant: 32),

            promptIconView.centerXAnchor.constraint(equalTo: promptContainer.centerXAnchor),
            promptIconView.centerYAnchor.constraint(equalTo: promptContainer.centerYAnchor),
            promptIconView.widthAnchor.constraint(equalToConstant: 14),
            promptIconView.heightAnchor.constraint(equalToConstant: 14),

            promptArrow.leadingAnchor.constraint(equalTo: promptContainer.trailingAnchor, constant: 6),
            promptArrow.centerYAnchor.constraint(equalTo: inputTakeoverView.centerYAnchor),

            inputTextField.leadingAnchor.constraint(equalTo: promptArrow.trailingAnchor, constant: 6),
            inputTextField.centerYAnchor.constraint(equalTo: inputTakeoverView.centerYAnchor),
            inputTextField.trailingAnchor.constraint(equalTo: inputHintLabel.leadingAnchor, constant: -12),

            inputHintLabel.trailingAnchor.constraint(equalTo: inputTakeoverView.trailingAnchor, constant: -8),
            inputHintLabel.centerYAnchor.constraint(equalTo: inputTakeoverView.centerYAnchor)
        ])

        // Setup Confirm Prompt Takeover View (Category 4)
        confirmTakeoverView.wantsLayer = true
        confirmTakeoverView.layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1.0).cgColor
        confirmTakeoverView.translatesAutoresizingMaskIntoConstraints = false
        confirmTakeoverView.isHidden = true
        addSubview(confirmTakeoverView)

        confirmPromptContainer.wantsLayer = true
        confirmPromptContainer.layer?.backgroundColor = NSColor(calibratedRed: 0.95, green: 0.65, blue: 0.15, alpha: 1.0).cgColor
        confirmPromptContainer.translatesAutoresizingMaskIntoConstraints = false

        confirmPromptIconView.imageScaling = .scaleProportionallyDown
        confirmPromptIconView.contentTintColor = .white
        confirmPromptIconView.translatesAutoresizingMaskIntoConstraints = false
        confirmPromptContainer.addSubview(confirmPromptIconView)

        confirmPromptArrow.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        confirmPromptArrow.textColor = NSColor(calibratedRed: 0.95, green: 0.65, blue: 0.15, alpha: 1.0)
        confirmPromptArrow.translatesAutoresizingMaskIntoConstraints = false

        confirmMessageLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        confirmMessageLabel.textColor = .white
        confirmMessageLabel.translatesAutoresizingMaskIntoConstraints = false

        confirmChoiceLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        confirmChoiceLabel.textColor = NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.06, alpha: 1.0)
        confirmChoiceLabel.translatesAutoresizingMaskIntoConstraints = false

        confirmHintLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        confirmHintLabel.textColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
        confirmHintLabel.translatesAutoresizingMaskIntoConstraints = false

        confirmTakeoverView.addSubview(confirmPromptContainer)
        confirmTakeoverView.addSubview(confirmPromptArrow)
        confirmTakeoverView.addSubview(confirmMessageLabel)
        confirmTakeoverView.addSubview(confirmChoiceLabel)
        confirmTakeoverView.addSubview(confirmHintLabel)

        NSLayoutConstraint.activate([
            confirmTakeoverView.topAnchor.constraint(equalTo: topAnchor),
            confirmTakeoverView.bottomAnchor.constraint(equalTo: bottomAnchor),
            confirmTakeoverView.leadingAnchor.constraint(equalTo: leadingAnchor),
            confirmTakeoverView.trailingAnchor.constraint(equalTo: trailingAnchor),

            confirmPromptContainer.leadingAnchor.constraint(equalTo: confirmTakeoverView.leadingAnchor),
            confirmPromptContainer.topAnchor.constraint(equalTo: confirmTakeoverView.topAnchor),
            confirmPromptContainer.bottomAnchor.constraint(equalTo: confirmTakeoverView.bottomAnchor),
            confirmPromptContainer.widthAnchor.constraint(equalToConstant: 32),

            confirmPromptIconView.centerXAnchor.constraint(equalTo: confirmPromptContainer.centerXAnchor),
            confirmPromptIconView.centerYAnchor.constraint(equalTo: confirmPromptContainer.centerYAnchor),
            confirmPromptIconView.widthAnchor.constraint(equalToConstant: 14),
            confirmPromptIconView.heightAnchor.constraint(equalToConstant: 14),

            confirmPromptArrow.leadingAnchor.constraint(equalTo: confirmPromptContainer.trailingAnchor, constant: 6),
            confirmPromptArrow.centerYAnchor.constraint(equalTo: confirmTakeoverView.centerYAnchor),

            confirmMessageLabel.leadingAnchor.constraint(equalTo: confirmPromptArrow.trailingAnchor, constant: 6),
            confirmMessageLabel.centerYAnchor.constraint(equalTo: confirmTakeoverView.centerYAnchor),

            confirmChoiceLabel.leadingAnchor.constraint(equalTo: confirmMessageLabel.trailingAnchor, constant: 8),
            confirmChoiceLabel.centerYAnchor.constraint(equalTo: confirmTakeoverView.centerYAnchor),

            confirmHintLabel.trailingAnchor.constraint(equalTo: confirmTakeoverView.trailingAnchor, constant: -8),
            confirmHintLabel.centerYAnchor.constraint(equalTo: confirmTakeoverView.centerYAnchor)
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

        // Active Confirm Prompt binding (Category 4)
        registry.$activeConfirmPrompt
            .receive(on: RunLoop.main)
            .sink { [weak self] prompt in
                guard let self = self else { return }
                if let p = prompt {
                    self.showConfirmTakeover(p)
                } else {
                    self.hideConfirmTakeover()
                }
            }
            .store(in: &cancellables)
    }

    private func rebuildStack(_ stack: NSStackView?, with plugins: [ViewPlugin]) {
        guard let stack = stack else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for plugin in plugins {
            if plugin.isFlexible {
                plugin.view.setContentHuggingPriority(.init(1), for: .horizontal)
                plugin.view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            } else {
                plugin.view.setContentHuggingPriority(.required, for: .horizontal)
                plugin.view.setContentCompressionResistancePriority(.required, for: .horizontal)
            }
            stack.addArrangedSubview(plugin.view)
        }
    }

    public func bind(keyEngine: KeyEngine, tabManager: TabManager) {
        // Connect the centralized reactive telemetry bus
        PluginDataBus.shared.attach(keyEngine: keyEngine, tabManager: tabManager)
    }

    private func showInputTakeover(plugin: InputPlugin) {
        let iconName = plugin.promptIconName ?? "terminal"
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        promptIconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: plugin.prompt)?.withSymbolConfiguration(config)
        promptIconView.contentTintColor = .white

        inputTextField.placeholderString = plugin.placeholder
        inputTakeoverView.isHidden = false
        window?.makeFirstResponder(inputTextField)

        if plugin.id == "input.find" {
            inputHintLabel.stringValue = "[0/0]"
            inputHintLabel.textColor = NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.06, alpha: 1.0)
        } else {
            inputHintLabel.stringValue = "esc: cancel   ↵: confirm"
            inputHintLabel.textColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
        }

        if plugin.isComboboxEnabled {
            combobox?.isInteractive = plugin.isComboboxInteractive
            runComboboxQuery(inputTextField.stringValue, debounce: false)
        } else {
            combobox?.hide()
        }
    }

    private func hideInputTakeover() {
        inputTakeoverView.isHidden = true
        queryTask?.cancel()
        combobox?.hide()
    }

    private func showConfirmTakeover(_ prompt: ConfirmPrompt) {
        let iconName = prompt.promptIconName ?? "questionmark.circle.fill"
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        confirmPromptIconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: prompt.prompt)?.withSymbolConfiguration(config)
        confirmPromptIconView.contentTintColor = .white

        confirmMessageLabel.stringValue = prompt.message
        confirmChoiceLabel.stringValue = prompt.defaultYes ? "[Y/n]" : "[y/N]"
        confirmTakeoverView.isHidden = false
    }

    private func hideConfirmTakeover() {
        confirmTakeoverView.isHidden = true
    }

    public func activateInput(prefill: String = "") {
        inputTextField.stringValue = prefill
        window?.makeFirstResponder(inputTextField)
        if !prefill.isEmpty {
            inputTextField.selectText(nil)
        }
        if let plugin = PluginRegistry.shared.activeInputPlugin, plugin.isComboboxEnabled {
            runComboboxQuery(prefill, debounce: false)
        }
    }

    public func submitCurrentInput(openInNewTab: Bool = false, forceRawInput: Bool = false) {
        let input: String
        if !forceRawInput, let item = combobox?.selectedItem, !(combobox?.isHidden ?? true) {
            input = item.id.hasPrefix("tab:") ? item.id : (item.url?.absoluteString ?? item.display)
        } else {
            input = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        combobox?.hide()
        onInputSubmit?(input, openInNewTab)
    }

    private func runComboboxQuery(_ query: String, debounce: Bool = true) {
        queryTask?.cancel()
        queryTask = Task { @MainActor [weak self] in
            if debounce {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            guard !Task.isCancelled, let self = self else { return }
            guard let plugin = PluginRegistry.shared.activeInputPlugin, plugin.isComboboxEnabled else {
                self.combobox?.hide()
                return
            }

            var firstUpdate = true
            await plugin.queryItemsStreaming(query: query) { [weak self] results in
                guard let self = self, !Task.isCancelled else { return }
                if firstUpdate {
                    self.combobox?.updateItems(results)
                    firstUpdate = false
                } else {
                    self.combobox?.appendItems(results)
                }
            }
        }
    }

    // MARK: - NSTextFieldDelegate

    public func controlTextDidBeginEditing(_ obj: Notification) {
        (obj.userInfo?["NSFieldEditor"] as? NSTextView)?.disableTextAssists()
    }

    /// Kills the manual completion popup (F5 / Option-Esc) in the command bar.
    public func control(
        _ control: NSControl,
        textView: NSTextView,
        completions words: [String],
        forPartialWordRange charRange: NSRange,
        indexOfSelectedItem index: UnsafeMutablePointer<Int>
    ) -> [String] {
        index.pointee = -1
        return []
    }

    public func controlTextDidChange(_ obj: Notification) {
        if let plugin = PluginRegistry.shared.activeInputPlugin {
            if plugin.id == "input.find" {
                let query = inputTextField.stringValue
                if !query.isEmpty {
                    (NSApp.keyWindow?.contentViewController as? MainViewController)?.tabManager.activeTab?.findInPage(query, forward: true, notifyIfNotFound: false) { [weak self] current, total in
                        self?.inputHintLabel.stringValue = "[\(current)/\(total)]"
                        self?.inputHintLabel.textColor = (total > 0)
                            ? NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.06, alpha: 1.0)
                            : NSColor(calibratedRed: 0.95, green: 0.40, blue: 0.40, alpha: 1.0)
                    }
                } else {
                    inputHintLabel.stringValue = "[0/0]"
                }
            } else if plugin.isComboboxEnabled {
                runComboboxQuery(inputTextField.stringValue, debounce: true)
            }
        }
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) ||
           commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) ||
           commandSelector == #selector(NSResponder.insertLineBreak(_:)) {
            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
            let isNewTab = modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.shift)
            submitCurrentInput(openInNewTab: isNewTab, forceRawInput: isNewTab)
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            combobox?.hide()
            onInputCancel?()
            return true
        } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
            combobox?.moveSelection(by: 1)
            return true
        } else if commandSelector == #selector(NSResponder.moveUp(_:)) {
            combobox?.moveSelection(by: -1)
            return true
        } else if commandSelector == #selector(NSResponder.insertTab(_:)) {
            if let selected = combobox?.selectedItem {
                inputTextField.stringValue = selected.display
            }
            return true
        }
        return false
    }
}
