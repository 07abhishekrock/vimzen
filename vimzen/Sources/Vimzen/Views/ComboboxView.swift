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
        primaryLabel.translatesAutoresizingMaskIntoConstraints = false

        // Secondary text (Detail e.g. domain or search provider)
        detailLabel.stringValue = item.detail ?? ""
        detailLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        detailLabel.textColor = NSColor(calibratedWhite: 0.50, alpha: 1.0)
        detailLabel.lineBreakMode = .byTruncatingTail
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

            // Primary display title
            primaryLabel.leadingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: 8),
            primaryLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            primaryLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 400),

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
    public private(set) var selectedIndex: Int = 0

    public var selectedItem: RankedResult? {
        guard !items.isEmpty, selectedIndex >= 0 && selectedIndex < items.count else {
            return nil
        }
        return items[selectedIndex]
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
        selectedIndex = 0

        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()

        guard !items.isEmpty else {
            hide()
            return
        }

        for (index, item) in items.enumerated() {
            let rowView = ComboboxRowView(item: item)
            rowView.isSelected = (index == selectedIndex)
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
        selectedIndex = (selectedIndex + delta + rowViews.count) % rowViews.count
        updateSelectionUI()
    }

    private func updateSelectionUI() {
        for (index, rowView) in rowViews.enumerated() {
            rowView.isSelected = (index == selectedIndex)
        }
    }

    public func hide() {
        isHidden = true
        items.removeAll()
        rowViews.removeAll()
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }
}
