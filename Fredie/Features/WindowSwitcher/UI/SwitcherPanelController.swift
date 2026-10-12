import AppKit

struct SwitcherPanelShowMetrics {
    let pointerMilliseconds: Double
    let updateMilliseconds: Double
    let centerMilliseconds: Double
    let orderMilliseconds: Double

    var benchmarkDetails: String {
        "pointer_ms=\(number(pointerMilliseconds)) update_ms=\(number(updateMilliseconds)) center_ms=\(number(centerMilliseconds)) order_ms=\(number(orderMilliseconds))"
    }

    private func number(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

@MainActor
final class SwitcherPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private static let panelWidth: CGFloat = 620
    private static let rowHeight: CGFloat = 34
    private static let verticalChromeInset: CGFloat = 6
    private static let emptyPanelHeight: CGFloat = 92

    var onConfirm: ((SwitcherItem) -> Void)?
    var onSelectionChanged: ((SwitcherItem) -> Void)?

    private let panel: SwitcherPanel
    private let contentContainer = NSView()
    private let tableView = HoverTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No windows found")
    private let visualEffectView = NSVisualEffectView()
    private let tintView = MousePassthroughView()
    private let borderView = MousePassthroughView()
    private var items: [SwitcherItem] = []
    private var selectedIndex = 0
    private(set) var isVisible = false
    private var pendingVisibilityRestore: Task<Void, Never>?
    private var pendingSpaceChange = false
    private var visibilityRestoreRequests = 0

    override init() {
        panel = SwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.emptyPanelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]

        visualEffectView.blendingMode = .withinWindow
        visualEffectView.material = effectiveMaterial
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.layer?.cornerRadius = 16
        visualEffectView.layer?.masksToBounds = true

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.wantsLayer = true
        contentContainer.layer?.cornerRadius = 16
        contentContainer.layer?.masksToBounds = true
        panel.contentView = contentContainer
        contentContainer.addSubview(visualEffectView)

        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.wantsLayer = true
        tintView.layer?.cornerRadius = 16
        tintView.layer?.masksToBounds = true
        contentContainer.addSubview(tintView)

        borderView.translatesAutoresizingMaskIntoConstraints = false
        borderView.wantsLayer = true
        borderView.layer?.cornerRadius = 16
        borderView.layer?.borderWidth = 1
        borderView.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        borderView.layer?.backgroundColor = NSColor.clear.cgColor
        contentContainer.addSubview(borderView)

        NSLayoutConstraint.activate([
            visualEffectView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            tintView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            borderView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            borderView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            borderView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])

        applyPanelAppearance()

        configureTable()
        configureEmptyState()
    }

    func show(items: [SwitcherItem], selectedIndex: Int = 0) -> SwitcherPanelShowMetrics {
        let pointerStart = ContinuousClock.now
        tableView.beginPointerTracking(at: NSEvent.mouseLocation)
        let pointerMilliseconds = SwitcherDiagnostics.elapsedMilliseconds(since: pointerStart)

        let updateStart = ContinuousClock.now
        updateItems(items, selectedIndex: selectedIndex)
        let updateMilliseconds = SwitcherDiagnostics.elapsedMilliseconds(since: updateStart)

        let centerStart = ContinuousClock.now
        centerOnActiveScreen(preferredDisplayID: items.first?.displayID)
        let centerMilliseconds = SwitcherDiagnostics.elapsedMilliseconds(since: centerStart)

        let orderStart = ContinuousClock.now
        isVisible = true
        panel.orderFrontRegardless()
        let orderMilliseconds = SwitcherDiagnostics.elapsedMilliseconds(since: orderStart)

        return SwitcherPanelShowMetrics(
            pointerMilliseconds: pointerMilliseconds,
            updateMilliseconds: updateMilliseconds,
            centerMilliseconds: centerMilliseconds,
            orderMilliseconds: orderMilliseconds
        )
    }

    var currentSelectedItem: SwitcherItem? {
        guard items.indices.contains(selectedIndex) else {
            return nil
        }

        return items[selectedIndex]
    }

    var currentSelectedIndex: Int {
        selectedIndex
    }

    func updateItemsPreservingSelection(_ items: [SwitcherItem]) {
        let items = self.items.compactMap { existing in
            items.first { $0.hasSameIdentity(as: existing) }
        }
        let previousSelection = currentSelectedItem
        let nextIndex = currentSelectedItem.flatMap { selected in
            items.firstIndex { $0.hasSameIdentity(as: selected) }
        } ?? selectedIndex
        updateItems(items, selectedIndex: nextIndex)
        if let selected = currentSelectedItem,
           previousSelection?.hasSameIdentity(as: selected) != true {
            onSelectionChanged?(selected)
        }
    }

    func updateItems(_ items: [SwitcherItem], selectedIndex: Int? = nil) {
        let rowCountChanged = self.items.count != items.count
        let displayChanged = self.items.first?.displayID != items.first?.displayID
        let changedRows = IndexSet(items.indices.filter { index in
            !self.items.indices.contains(index) || !itemsArePresentationEqual(self.items[index], items[index])
        })
        let previousPanelSize = panel.frame.size
        self.items = items
        let requestedIndex = selectedIndex ?? self.selectedIndex
        let nextSelectedIndex = max(0, min(requestedIndex, max(0, items.count - 1)))
        let selectionChanged = self.selectedIndex != nextSelectedIndex
        self.selectedIndex = nextSelectedIndex

        if rowCountChanged || displayChanged {
            emptyLabel.isHidden = !items.isEmpty
            scrollView.isHidden = items.isEmpty
            updatePanelSize(preferredDisplayID: items.first?.displayID)
        }
        if rowCountChanged {
            tableView.reloadData()
        } else if !changedRows.isEmpty {
            tableView.reloadData(forRowIndexes: changedRows, columnIndexes: IndexSet(integer: 0))
        }

        if !items.isEmpty, rowCountChanged || displayChanged || selectionChanged {
            tableView.selectRowIndexes(IndexSet(integer: self.selectedIndex), byExtendingSelection: false)
            revealSelection()
        }
        if panel.isVisible {
            if displayChanged || panel.frame.size != previousPanelSize {
                centerOnActiveScreen(preferredDisplayID: items.first?.displayID)
            }
            if rowCountChanged || !changedRows.isEmpty {
                tableView.refreshHoveredRow()
            }
        }
    }

    func hide() {
        isVisible = false
        pendingVisibilityRestore?.cancel()
        pendingVisibilityRestore = nil
        pendingSpaceChange = false
        visibilityRestoreRequests = 0
        tableView.resetPointerTracking()
        panel.orderOut(nil)
    }

    func restoreVisibility(afterSpaceChange: Bool = false) {
        guard isVisible else { return }
        pendingSpaceChange = pendingSpaceChange || afterSpaceChange
        visibilityRestoreRequests += 1
        guard pendingVisibilityRestore == nil else { return }
        pendingVisibilityRestore = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, isVisible else { return }
            pendingVisibilityRestore = nil
            let rejoinSpace = pendingSpaceChange
            let requests = visibilityRestoreRequests
            pendingSpaceChange = false
            visibilityRestoreRequests = 0
            let start = ContinuousClock.now
            if rejoinSpace { panel.orderOut(nil) }
            panel.orderFrontRegardless()
            SwitcherDiagnostics().benchmark(
                "switcher.restoreVisibility",
                since: start,
                details: "space_changed=\(rejoinSpace) requests=\(requests)"
            )
        }
    }

    func moveSelection(delta: Int) {
        guard !items.isEmpty else {
            return
        }

        selectedIndex = (selectedIndex + delta + items.count) % items.count
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        revealSelection()
        restoreVisibility()
        onSelectionChanged?(items[selectedIndex])
    }

    func confirmSelection() {
        guard items.indices.contains(selectedIndex) else {
            hide()
            return
        }

        onConfirm?(items[selectedIndex])
    }

    private func configureTable() {
        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleColumn.width = 574

        tableView.addTableColumn(titleColumn)
        tableView.headerView = nil
        tableView.style = .fullWidth
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.onHoverRow = { [weak self] row in
            self?.selectRowFromPointer(row)
        }
        panel.onMouseDown = { [weak self] point in
            guard let self else { return false }
            let localPoint = tableView.convert(point, from: nil)
            guard tableView.visibleRect.contains(localPoint) else { return false }
            let row = tableView.row(at: localPoint)
            guard items.indices.contains(row) else { return false }
            activateRowFromPointer(row)
            return true
        }

        scrollView.isHidden = true
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        visualEffectView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: Self.verticalChromeInset),
            scrollView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -Self.verticalChromeInset),
        ])
    }

    private func configureEmptyState() {
        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: visualEffectView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: visualEffectView.centerYAnchor),
        ])
    }

    private func centerOnActiveScreen(preferredDisplayID: CGDirectDisplayID?) {
        let screen = screen(preferredDisplayID: preferredDisplayID)
        guard let screen else {
            return
        }

        let size = panel.frame.size
        let x = screen.frame.midX - (size.width / 2)
        let y = screen.frame.midY - (size.height / 2)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func selectRowFromPointer(_ row: Int) {
        guard items.indices.contains(row), selectedIndex != row else {
            return
        }

        selectedIndex = row
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        onSelectionChanged?(items[row])
    }

    private func activateRowFromPointer(_ row: Int) {
        guard items.indices.contains(row) else {
            return
        }

        selectedIndex = row
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        onConfirm?(items[row])
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = HighlightRowView()
        rowView.isEmphasized = true
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]

        let identifier = NSUserInterfaceItemIdentifier("itemCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ItemCellView
            ?? ItemCellView()
        cell.identifier = identifier
        cell.configure(with: item)
        return cell
    }
}

extension SwitcherPanelController {
    private var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private var effectiveMaterial: NSVisualEffectView.Material {
        reduceTransparency ? .windowBackground : .hudWindow
    }

    private var tintOpacity: CGFloat {
        reduceTransparency ? 0.96 : 0.18
    }

    private func applyPanelAppearance() {
        visualEffectView.material = effectiveMaterial
        tintView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(tintOpacity).cgColor
        borderView.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
    }

    private func updatePanelSize(preferredDisplayID: CGDirectDisplayID?) {
        let visibleFrame = screen(preferredDisplayID: preferredDisplayID)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let maximumHeight = floor(visibleFrame.height * 0.7)
        let desiredHeight: CGFloat

        if items.isEmpty {
            desiredHeight = Self.emptyPanelHeight
        } else {
            let maximumRowCount = max(1, floor((maximumHeight - (Self.verticalChromeInset * 2)) / Self.rowHeight))
            let visibleRowCount = min(CGFloat(items.count), maximumRowCount)
            desiredHeight = visibleRowCount * Self.rowHeight + (Self.verticalChromeInset * 2)
        }

        panel.setContentSize(NSSize(width: Self.panelWidth, height: desiredHeight))
    }

    private func revealSelection() {
        contentContainer.layoutSubtreeIfNeeded()

        let documentHeight = tableView.bounds.height
        let viewportHeight = scrollView.contentView.bounds.height

        guard documentHeight > viewportHeight + 1 else {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return
        }

        tableView.scrollRowToVisible(selectedIndex)
    }

    private func screen(preferredDisplayID: CGDirectDisplayID?) -> NSScreen? {
        if let preferredDisplayID {
            let matchingScreen = NSScreen.screens.first { screen in
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                    == preferredDisplayID
            }
            if let matchingScreen {
                return matchingScreen
            }
        }

        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
    }

    private func itemsArePresentationEqual(_ lhs: SwitcherItem, _ rhs: SwitcherItem) -> Bool {
        lhs.kind == rhs.kind &&
            lhs.appName == rhs.appName &&
            lhs.displayTitle == rhs.displayTitle &&
            lhs.appIcon === rhs.appIcon &&
            lhs.isHidden == rhs.isHidden &&
            lhs.isMinimized == rhs.isMinimized
    }
}

private final class HighlightRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else {
            return
        }

        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 4, yRadius: 4)
        NSColor.selectedContentBackgroundColor.setFill()
        path.fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected ? .emphasized : .normal
    }
}

private final class MousePassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

struct PointerMovementGate {
    private var openingLocation: NSPoint?
    private var hasMovedSinceOpening = false

    mutating func begin(at location: NSPoint) {
        openingLocation = location
        hasMovedSinceOpening = false
    }

    mutating func reset() {
        openingLocation = nil
        hasMovedSinceOpening = false
    }

    mutating func allowsPointerSelection(at location: NSPoint) -> Bool {
        guard let openingLocation else {
            return false
        }

        if location != openingLocation {
            hasMovedSinceOpening = true
        }
        return hasMovedSinceOpening
    }
}

final class SwitcherPanel: NSPanel {
    var onMouseDown: ((NSPoint) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, onMouseDown?(event.locationInWindow) == true {
            return
        }
        super.sendEvent(event)
    }
}

private final class HoverTableView: NSTableView {
    var onHoverRow: ((Int) -> Void)?

    private var pointerTrackingArea: NSTrackingArea?
    private var pointerMovementGate = PointerMovementGate()
    private var lastHoveredRow: Int?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseEntered(with event: NSEvent) {
        updateHoveredRowAfterMovement(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoveredRowAfterMovement(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        lastHoveredRow = nil
    }

    func beginPointerTracking(at location: NSPoint) {
        pointerMovementGate.begin(at: location)
        lastHoveredRow = nil
    }

    func resetPointerTracking() {
        pointerMovementGate.reset()
        lastHoveredRow = nil
    }

    func refreshHoveredRow() {
        guard let window, window.isVisible else {
            resetPointerTracking()
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        guard pointerMovementGate.allowsPointerSelection(at: mouseLocation) else {
            return
        }

        let windowPoint = window.convertPoint(fromScreen: mouseLocation)
        let localPoint = convert(windowPoint, from: nil)
        guard bounds.contains(localPoint) else {
            lastHoveredRow = nil
            return
        }
        updateHoveredRow(at: localPoint)
    }

    private func updateHoveredRowAfterMovement(with event: NSEvent) {
        guard pointerMovementGate.allowsPointerSelection(at: NSEvent.mouseLocation) else {
            return
        }

        updateHoveredRow(at: convert(event.locationInWindow, from: nil))
    }

    private func updateHoveredRow(at point: NSPoint) {
        let row = row(at: point)
        guard row >= 0 else {
            lastHoveredRow = nil
            return
        }
        guard lastHoveredRow != row else {
            return
        }

        lastHoveredRow = row
        onHoverRow?(row)
    }
}

private final class ItemCellView: NSTableCellView {
    private let appNameField = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let windowTitleField = NSTextField(labelWithString: "")
    private let statusField = NSTextField(labelWithString: "")

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            updateTextColors()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        appNameField.font = .systemFont(ofSize: 12, weight: .medium)
        appNameField.alignment = .right
        appNameField.lineBreakMode = .byTruncatingTail

        iconView.symbolConfiguration = .init(pointSize: 15, weight: .medium)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 6
        iconView.layer?.masksToBounds = true

        windowTitleField.font = .systemFont(ofSize: 12, weight: .medium)
        windowTitleField.lineBreakMode = .byTruncatingTail

        statusField.font = .systemFont(ofSize: 11, weight: .medium)
        statusField.alignment = .right

        addSubview(appNameField)
        addSubview(iconView)
        addSubview(windowTitleField)
        addSubview(statusField)
        updateTextColors()
    }

    override func layout() {
        super.layout()
        let textHeight = appNameField.intrinsicContentSize.height
        let textY = floor((bounds.height - textHeight) / 2)
        appNameField.frame = NSRect(x: 34, y: textY, width: 104, height: textHeight)
        iconView.frame = NSRect(x: 144, y: floor((bounds.height - 16) / 2), width: 16, height: 16)
        let statusSize = statusField.intrinsicContentSize
        let statusWidth = statusField.isHidden ? 0 : ceil(statusSize.width)
        let statusSpacing: CGFloat = statusField.isHidden ? 0 : 8
        windowTitleField.frame = NSRect(
            x: 166, y: textY,
            width: max(0, bounds.width - 174 - statusWidth - statusSpacing),
            height: textHeight
        )
        statusField.frame = NSRect(
            x: bounds.width - 8 - statusWidth, y: floor((bounds.height - statusSize.height) / 2),
            width: statusWidth, height: statusSize.height
        )
    }

    func configure(with item: SwitcherItem) {
        appNameField.stringValue = item.appName
        iconView.image = item.appIcon
        let title = item.kind == .window ? item.displayTitle : "Application"
        windowTitleField.stringValue = title
        windowTitleField.toolTip = title
        statusField.stringValue = [
            item.isHidden ? "Hidden" : nil,
            item.isMinimized ? "Minimized" : nil,
        ].compactMap { $0 }.joined(separator: " · ")
        statusField.isHidden = statusField.stringValue.isEmpty
        needsLayout = true
    }

    private func updateTextColors() {
        let selected = backgroundStyle == .emphasized
        appNameField.textColor = selected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        windowTitleField.textColor = selected ? .alternateSelectedControlTextColor : .labelColor
        statusField.textColor = selected ? .alternateSelectedControlTextColor : .secondaryLabelColor
    }
}
