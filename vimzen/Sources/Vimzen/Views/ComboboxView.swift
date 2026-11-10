import AppKit

// MARK: - Combobox Row View

@MainActor
public final class ComboboxRowView: NSView {
    public let item: RankedResult
    public var isSelected: Bool = false {
        didSet {
            updateSelectionState()
        }
    }

    public var onSelect: (() -> Void)?

    private let badgeContainer = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private let primaryLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    public init(item: RankedResult) {
        self.item = item
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 3

        // Badge Container
        badgeContainer.wantsLayer = true
        badgeContainer.layer?.cornerRadius = 2
        badgeContainer.translatesAutoresizingMaskIntoConstraints = false

        if item.badge == "TAB" {
            badgeContainer.layer?.backgroundColor = NSColor(calibratedRed: 0.20, green: 0.60, blue: 1.00, alpha: 0.85).cgColor
        } else {
            badgeContainer.layer?.backgroundColor = NSColor(calibratedWhite: 0.25, alpha: 1.0).cgColor
        }

        badgeLabel.stringValue = item.badge
        badgeLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.alignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.addSubview(badgeLabel)

        // Primary text (Display title or query)
        primaryLabel.stringValue = item.display
        primaryLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        primaryLabel.textColor = .white
        primaryLabel.lineBreakMode = .byTruncatingTail
        primaryLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        primaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        primaryLabel.translatesAutoresizingMaskIntoConstraints = false

        // Secondary text (Detail e.g. domain or search provider)
        detailLabel.stringValue = item.detail ?? ""
        detailLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        detailLabel.textColor = NSColor(calibratedWhite: 0.50, alpha: 1.0)
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        detailLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(249), for: .horizontal)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(badgeContainer)
        addSubview(primaryLabel)
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),

            // Badge chip
            badgeContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            badgeContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeContainer.heightAnchor.constraint(equalToConstant: 14),
            badgeContainer.widthAnchor.constraint(equalToConstant: 34),

            badgeLabel.centerXAnchor.constraint(equalTo: badgeContainer.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor),

            // Primary display title (limited to 55% of row width to allow detail label room)
            primaryLabel.leadingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: 8),
            primaryLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            primaryLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.55),

            // Secondary detail info
            detailLabel.leadingAnchor.constraint(equalTo: primaryLabel.trailingAnchor, constant: 12),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateSelectionState()
    }

    private func updateSelectionState() {
        if isSelected {
            layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 1.0).cgColor
            primaryLabel.textColor = .white
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            primaryLabel.textColor = NSColor(calibratedWhite: 0.90, alpha: 1.0)
        }
    }

    public override func mouseDown(with event: NSEvent) {
        onSelect?()
    }
}

// MARK: - Upward-Opening Combobox View

@MainActor
public final class ComboboxView: NSView {
    public var onCommitSelection: ((RankedResult) -> Void)?

    private let stackView = NSStackView()
    private var rowViews: [ComboboxRowView] = []
    public private(set) var items: [RankedResult] = []
    public private(set) var selectedIndex: Int? = nil

    public var selectedItem: RankedResult? {
        guard let idx = selectedIndex, !items.isEmpty, idx >= 0 && idx < items.count else {
            return nil
        }
        return items[idx]
    }

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
        layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 0.98).cgColor
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(calibratedWhite: 0.20, alpha: 1.0).cgColor
        layer?.cornerRadius = 6
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.5
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: 4)

        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stackView.orientation = .vertical
        stackView.spacing = 2
        stackView.alignment = .width
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        ])

        isHidden = true
    }

    public func updateItems(_ newItems: [RankedResult]) {
        self.items = Array(newItems.prefix(8))
        selectedIndex = nil

        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()

        guard !items.isEmpty else {
            hide()
            return
        }

        for (index, item) in items.enumerated() {
            let rowView = ComboboxRowView(item: item)
            rowView.isSelected = false
            rowView.translatesAutoresizingMaskIntoConstraints = false

            rowView.onSelect = { [weak self] in
                self?.selectedIndex = index
                self?.updateSelectionUI()
                self?.onCommitSelection?(item)
            }

            stackView.addArrangedSubview(rowView)
            rowView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor).isActive = true
            rowView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor).isActive = true
            rowViews.append(rowView)
        }

        updateSelectionUI()
        isHidden = false
    }

    public func appendItems(_ newItems: [RankedResult]) {
        guard items.count < 8 else { return }

        let existingIds = Set(items.map(\.id))
        let fresh = newItems.filter { !existingIds.contains($0.id) }
        guard !fresh.isEmpty else { return }

        let allowedCount = 8 - items.count
        let toAdd = Array(fresh.prefix(allowedCount))
        let previouslySelectedId = selectedItem?.id

        for item in toAdd {
            let index = items.count
            items.append(item)

            let rowView = ComboboxRowView(item: item)
            rowView.isSelected = false
            rowView.translatesAutoresizingMaskIntoConstraints = false

            rowView.onSelect = { [weak self] in
                self?.selectedIndex = index
                self?.updateSelectionUI()
                self?.onCommitSelection?(item)
            }

            stackView.addArrangedSubview(rowView)
            rowView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor).isActive = true
            rowView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor).isActive = true
            rowViews.append(rowView)
        }

        if let prevId = previouslySelectedId,
           let newIndex = items.firstIndex(where: { $0.id == prevId }) {
            selectedIndex = newIndex
        }
        updateSelectionUI()
        isHidden = items.isEmpty
    }

    public func moveSelection(by delta: Int) {
        guard !rowViews.isEmpty else { return }

        if let current = selectedIndex {
            let next = current + delta
            if next < 0 || next >= rowViews.count {
                // Moving up from top row or down past bottom row deselects, returning focus to raw text
                selectedIndex = nil
            } else {
                selectedIndex = next
            }
        } else {
            // Nothing was selected yet
            if delta > 0 {
                selectedIndex = 0
            } else {
                selectedIndex = rowViews.count - 1
            }
        }

        updateSelectionUI()
    }

    private func updateSelectionUI() {
        for (index, rowView) in rowViews.enumerated() {
            rowView.isSelected = (selectedIndex == index)
        }
    }

    public func hide() {
        isHidden = true
        items.removeAll()
        rowViews.removeAll()
        selectedIndex = nil
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }
}
