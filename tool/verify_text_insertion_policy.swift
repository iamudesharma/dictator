// Pure regression checks. Builds events but never posts input or opens a mic.
import Cocoa

@main struct TextInsertionPolicyProbe {
    static func main() throws {
        for version in ["155.0.0.1", "156.0.8078.80"] {
            precondition(TextInsertionPolicy.affectedChromiumVersion(version))
        }
        for version in ["154.0.0.1", "157.0.0.1", "156", "156.x.0.1", "A"] {
            precondition(!TextInsertionPolicy.affectedChromiumVersion(version))
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Contents/Frameworks/Google Chrome Framework.framework/Versions/156.0.8078.80"), withIntermediateDirectories: true)
        precondition(TextInsertionPolicy.hasClipboardRace(bundleURL: root))
        precondition(!TextInsertionPolicy.hasClipboardRace(bundleURL: nil))
        precondition(TextInsertionPolicy.strokes("a\r\nb\rc\nd") == [.text([97]), .lineBreak, .text([98]), .lineBreak, .text([99]), .lineBreak, .text([100])])
        let text = String(repeating: "a", count: 19) + "😀नमस्ते café"
        let chunks = TextInsertionPolicy.strokes(text)
        var rebuilt = ""
        for case .text(let units) in chunks {
            precondition(units.count <= 20)
            let decoded = String(decoding: units, as: UTF16.self)
            precondition(!decoded.contains("\u{FFFD}"))
            rebuilt += decoded
        }
        precondition(rebuilt == text)
        let events = try TextInsertionPolicy.unicodeEvents("Hello\nworld")
        precondition(events.count == 6)
        precondition(events[2].getIntegerValueField(.keyboardEventKeycode) == 36)
        precondition(events[2].flags.contains(.maskShift), "Chat newline must be Shift-Return")
        precondition(!events[0].flags.contains(.maskAlternate), "Held Option must not leak into input")
        print("PASS: Chromium version detection, framework discovery, UTF-16 chunking, multilingual round-trip and safe chat newline events.")
    }
}
