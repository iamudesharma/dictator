// No microphone, keyboard injection or AX permissions. Exercises the real panel.
import Cocoa

@main struct FocusPanelProbe {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        precondition(before != ProcessInfo.processInfo.processIdentifier, "Probe must start in the background")
        let controller = DictationIndicatorController()
        let result = controller.show(["top": true, "phase": "recording", "level": 0.6])
        precondition(result["isKey"] as? Bool == false, "Panel became key")
        precondition(result["frontmostAfter"] as? pid_t == before, "Panel stole application focus")
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        controller.update(["phase": "transcribing"])
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        precondition(NSWorkspace.shared.frontmostApplication?.processIdentifier == before, "Focus changed while animating")
        controller.hide()
        precondition(NSWorkspace.shared.frontmostApplication?.processIdentifier == before, "Hide stole focus")
        print("PASS: native panel stayed non-key and preserved the frontmost application through show, animation, processing and hide.")
    }
}
