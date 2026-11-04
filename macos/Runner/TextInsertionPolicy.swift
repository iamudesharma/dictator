import Cocoa

/// Browser workaround and Unicode chunking adapted from Hex's paste.rs and
/// keyboard.rs (MIT; see THIRD_PARTY_NOTICES.md).
enum TextInsertionPolicy {
    enum Stroke: Equatable {
        case text([UniChar])
        case lineBreak
    }

    static func hasClipboardRace(bundleURL: URL?) -> Bool {
        guard let bundleURL else { return false }
        let frameworks = bundleURL.appendingPathComponent("Contents/Frameworks")
        let manager = FileManager.default
        for framework in (try? manager.contentsOfDirectory(at: frameworks, includingPropertiesForKeys: nil)) ?? [] {
            guard framework.lastPathComponent.hasSuffix("Framework.framework") else { continue }
            let versions = framework.appendingPathComponent("Versions")
            for version in (try? manager.contentsOfDirectory(at: versions, includingPropertiesForKeys: nil)) ?? [] {
                if affectedChromiumVersion(version.lastPathComponent) { return true }
            }
        }
        return false
    }

    static func affectedChromiumVersion(_ version: String) -> Bool {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ UInt($0) != nil }), let major = UInt(parts[0]) else { return false }
        return (155...156).contains(major)
    }

    /// Quartz carries at most 20 UTF-16 units per event. Never split a surrogate
    /// pair; normalize CRLF/CR/LF to Shift-Return, so a chat is never submitted.
    static func strokes(_ text: String) -> [Stroke] {
        var result: [Stroke] = [], buffer: [UniChar] = []
        let scalars = Array(text.unicodeScalars)
        var index = 0
        func flush() {
            if !buffer.isEmpty { result.append(.text(buffer)); buffer = [] }
        }
        while index < scalars.count {
            let scalar = scalars[index]
            index += 1
            if scalar.value == 13 || scalar.value == 10 {
                if scalar.value == 13 && index < scalars.count && scalars[index].value == 10 { index += 1 }
                flush(); result.append(.lineBreak)
            } else {
                let units = Array(String(scalar).utf16)
                if buffer.count + units.count > 20 { flush() }
                buffer.append(contentsOf: units)
            }
        }
        flush()
        return result
    }

    /// Build everything before posting, so allocation failure cannot insert a
    /// partial transcript and then cause a retry that duplicates the prefix.
    static func unicodeEvents(_ text: String) throws -> [CGEvent] {
        let source = CGEventSource(stateID: .privateState)
        var events: [CGEvent] = []
        for stroke in strokes(text) {
            for down in [true, false] {
                let code: CGKeyCode = stroke == .lineBreak ? 36 : 0
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else {
                    throw NSError(domain: "AuraScribe", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create text input events."])
                }
                event.flags = stroke == .lineBreak ? .maskShift : []
                if case .text(let units) = stroke {
                    units.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: $0.baseAddress!) }
                }
                events.append(event)
            }
        }
        return events
    }
}
