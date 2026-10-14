import AppKit

@MainActor
final class SwitcherFailureFeedback {
    let panel: NSPanel
    private let titleLabel = NSTextField(labelWithString: "Could not switch. Try again.")
    private let targetLabel = NSTextField(labelWithString: "")
    private let duration: Duration
    private var dismissal: Task<Void, Never>?

    init(duration: Duration = .seconds(3)) {
        self.duration = duration
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none

        let content = FailureFeedbackView(frame: panel.contentView!.bounds)
        panel.contentView = content

        let icon = NSImageView(frame: NSRect(x: 14, y: 20, width: 20, height: 20))
        icon.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Switch failed")
        icon.contentTintColor = .labelColor
        content.addSubview(icon)

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 46, y: 32, width: 360, height: 16)
        content.addSubview(titleLabel)

        targetLabel.font = .systemFont(ofSize: 12)
        targetLabel.textColor = .secondaryLabelColor
        targetLabel.lineBreakMode = .byTruncatingTail
        targetLabel.frame = NSRect(x: 46, y: 12, width: 360, height: 16)
        content.addSubview(targetLabel)
    }

    func show(for item: SwitcherItem) {
        hide()
        targetLabel.stringValue = item.displayTitle
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == item.displayID
        } ?? NSScreen.main
        if let screen {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - panel.frame.width / 2,
                y: screen.visibleFrame.midY - panel.frame.height / 2
            ))
        }
        panel.orderFrontRegardless()
        dismissal = Task { [weak self, duration] in
            do { try await Task.sleep(for: duration) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        dismissal?.cancel()
        dismissal = nil
        panel.orderOut(nil)
    }
}

private final class FailureFeedbackView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }
}
