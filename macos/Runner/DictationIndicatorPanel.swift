import Cocoa

/// A separate non-activating panel. Never repurposes or activates the settings window.
final class DictationIndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DictationIndicatorController {
    private var panel: DictationIndicatorPanel?
    private var meter: DictationMeterView?
    private var anchor: NSScreen?
    private var top = true

    func show(_ data: [String: Any]) -> [String: Any] {
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        if panel == nil {
            let window = DictationIndicatorPanel(contentRect: NSRect(x: 0, y: 0, width: 104, height: 30),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.level = .floating
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.becomesKeyOnlyIfNeeded = true
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let view = DictationMeterView(frame: window.contentView!.bounds)
            window.contentView = view
            panel = window; meter = view
        }
        top = data["top"] as? Bool ?? true
        anchor = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        update(data)
        panel?.orderFrontRegardless() // Does not call NSApp.activate or makeKeyAndOrderFront.
        meter?.startAnimation()
        return ["frontmostBefore": before,
                "frontmostAfter": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0,
                "isKey": panel?.isKeyWindow ?? false]
    }

    func update(_ data: [String: Any]) {
        guard let window = panel, let view = meter, let screen = anchor else { return }
        view.phase = data["phase"] as? String ?? "preparing"
        view.level = min(1, max(0, data["level"] as? Double ?? 0))
        view.message = data["error"] as? String ?? ""
        view.setAccessibilityLabel(view.phase == "recording" ? "AuraScribe listening. Release shortcut to finish."
            : view.phase == "error" ? view.message : "AuraScribe \(view.phase)")
        let size = view.phase == "error" ? NSSize(width: 328, height: 64) : NSSize(width: 104, height: 30)
        let visible = screen.visibleFrame
        window.setFrame(NSRect(x: visible.midX - size.width / 2,
            y: top ? visible.maxY - size.height - 10 : visible.minY + 12,
            width: size.width, height: size.height), display: true)
        view.needsDisplay = true
    }

    func hide() { meter?.stopAnimation(); panel?.orderOut(nil) }
    deinit { hide() }
}

final class DictationMeterView: NSView {
    var phase = "preparing"
    var level: Double = 0
    var message = ""
    private var displayedLevel: Double = 0
    private var tick = 0.0
    private var timer: Timer?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    func startAnimation() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.displayedLevel += (self.level - self.displayedLevel) * 0.3
            self.tick += 1.0 / 30
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func stopAnimation() { timer?.invalidate(); timer = nil }
    deinit { stopAnimation() }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let shape = NSBezierPath(roundedRect: box, xRadius: 15, yRadius: 15)
        NSColor(calibratedRed: 0.075, green: 0.09, blue: 0.105, alpha: 0.97).setFill(); shape.fill()
        NSColor.white.withAlphaComponent(0.2).setStroke(); shape.lineWidth = 1; shape.stroke()
        let teal = NSColor(calibratedRed: 0.57, green: 0.87, blue: 0.85, alpha: 1)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if phase == "error" {
            let text = message as NSString
            text.draw(with: NSRect(x: 14, y: 10, width: bounds.width - 28, height: 45),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(calibratedRed: 1, green: 0.72, blue: 0.68, alpha: 1)])
            return
        }
        ("⌥" as NSString).draw(at: NSPoint(x: 13, y: 6), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.7)])
        if phase == "recording" {
            teal.setFill()
            for (index, weight) in [0.4, 0.7, 1.0, 0.75, 0.45].enumerated() {
                let breathing = reduced ? 0.0 : 0.5 + 0.5 * sin(tick * 4 + Double(index) * 0.8)
                let height = 4 + 17 * weight * max(displayedLevel, breathing * 0.12)
                NSBezierPath(roundedRect: NSRect(x: 39 + Double(index) * 8, y: (bounds.height - height) / 2,
                    width: 3, height: height), xRadius: 1.5, yRadius: 1.5).fill()
            }
        } else {
            for index in 0..<3 {
                let pulse = reduced ? 0.7 : 0.35 + 0.65 * (0.5 + 0.5 * sin(tick * 6 - Double(index) * 0.9))
                teal.withAlphaComponent(pulse).setFill()
                NSBezierPath(ovalIn: NSRect(x: 42 + index * 11, y: 12, width: 5, height: 5)).fill()
            }
        }
    }
}
