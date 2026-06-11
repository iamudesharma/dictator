import Cocoa
import FlutterMacOS

class AccessibilityPlugin: NSObject, FlutterPlugin {
    private static var instance: AccessibilityPlugin?
    /// App that owned the selection when [copySelectedText] last ran (before our HUD opens).
    private var lastTargetAppPID: pid_t = 0

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.dictator/accessibility",
            binaryMessenger: registrar.messenger
        )
        let instance = AccessibilityPlugin()
        AccessibilityPlugin.instance = instance
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "checkPermission":
            result(checkPermission())
        case "requestPermission":
            requestPermission()
            result(nil)
        case "insertText":
            guard let args = call.arguments as? [String: Any],
                  let text = args["text"] as? String else {
                print("[AccessibilityPlugin] insertText — INVALID_ARGS")
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'text'", details: nil))
                return
            }
            print("[AccessibilityPlugin] insertText called (\(text.count) chars)")
            let usedAX = insertText(text)
            print("[AccessibilityPlugin] insertText finished — usedAX=\(usedAX)")
            result(usedAX)
        case "replaceSelectedText":
            guard let args = call.arguments as? [String: Any],
                  let text = args["text"] as? String else {
                print("[AccessibilityPlugin] replaceSelectedText — INVALID_ARGS")
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'text'", details: nil))
                return
            }
            print("[AccessibilityPlugin] replaceSelectedText called (\(text.count) chars)")
            let usedAX = replaceSelectedText(text)
            print("[AccessibilityPlugin] replaceSelectedText finished — usedAX=\(usedAX)")
            result(usedAX)
        case "copySelectedText":
            result(copySelectedText())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Copy Highlighted Text

    private func rememberFrontmostApp() {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            lastTargetAppPID = pid
            let name = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
            print("[AccessibilityPlugin] remembered target app pid=\(pid) (\(name))")
        }
    }

    private func activateTargetApp() {
        guard lastTargetAppPID != 0 else { return }
        guard let app = NSRunningApplication(processIdentifier: lastTargetAppPID) else {
            print("[AccessibilityPlugin] target app pid=\(lastTargetAppPID) is not running")
            return
        }
        print("[AccessibilityPlugin] activating target app pid=\(lastTargetAppPID) (\(app.localizedName ?? "unknown"))")
        app.activate(options: [.activateIgnoringOtherApps])
        Thread.sleep(forTimeInterval: 0.4)
    }

    private func copySelectedText() -> String? {
        rememberFrontmostApp()
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        print("[AccessibilityPlugin] copySelectedText from frontmost app: \(frontApp)")
        
        // 1. Try AX first if process is trusted
        if AXIsProcessTrusted() {
            let systemWide = AXUIElementCreateSystemWide()
            var focusedElement: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(
                systemWide,
                kAXFocusedUIElementAttribute as CFString,
                &focusedElement
            )
            if error == .success, let element = focusedElement {
                let axElement = element as! AXUIElement
                var selectedText: CFTypeRef?
                let axError = AXUIElementCopyAttributeValue(
                    axElement,
                    kAXSelectedTextAttribute as CFString,
                    &selectedText
                )
                if axError == .success, let text = selectedText as? String {
                    print("[AccessibilityPlugin] ✅ copySelectedText via AX succeeded: \(text.count) chars")
                    return text
                }
                print("[AccessibilityPlugin] kAXSelectedTextAttribute failed (error=\(axError.rawValue))")
            } else {
                print("[AccessibilityPlugin] AXFocusedUIElement failed (error=\(error.rawValue))")
            }
        } else {
            print("[AccessibilityPlugin] AX not trusted for copySelectedText")
        }
        
        // 2. Fall back to Cmd+C simulation
        print("[AccessibilityPlugin] falling back to Cmd+C simulation...")
        
        let pasteboard = NSPasteboard.general
        
        // Save current items on the clipboard to restore them later
        let previousItems = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }
        
        // Wait 200ms for user to release physical Control/Shift keys
        Thread.sleep(forTimeInterval: 0.2)
        
        pasteboard.clearContents()
        
        let source = CGEventSource(stateID: .hidSystemState)
        // 'c' is virtualKey 0x08
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
        
        // Wait a tiny moment for target app to write to pasteboard
        Thread.sleep(forTimeInterval: 0.15)
        
        let text = pasteboard.string(forType: .string)
        print("[AccessibilityPlugin] copySelectedText (simulated) got: \(text?.count ?? 0) characters")
        
        // Restore previous pasteboard contents
        if let prev = previousItems {
            pasteboard.clearContents()
            pasteboard.writeObjects(prev)
            print("[AccessibilityPlugin] restored previous clipboard contents after simulated copy")
        }
        
        return text
    }

    // MARK: - Permission

    private func checkPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    private func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        // Also open System Settings directly
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Text Insertion

    /// Activates the app that had the selection, then replaces selected text or pastes.
    private func replaceSelectedText(_ text: String) -> Bool {
        activateTargetApp()
        return insertTextInFocusedElement(text, context: "replaceSelectedText")
    }

    /// Attempts AX insertion first, falls back to ⌘V clipboard paste.
    /// Returns true if AX insertion succeeded, false if clipboard fallback was used.
    private func insertText(_ text: String) -> Bool {
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        print("[AccessibilityPlugin] frontmost app: \(frontApp)")
        return insertTextInFocusedElement(text, context: "insertText")
    }

    private func insertTextInFocusedElement(_ text: String, context: String) -> Bool {
        guard AXIsProcessTrusted() else {
            print("[AccessibilityPlugin] AX not trusted → clipboard fallback (\(context))")
            return fallbackPaste(text, reason: "accessibility_not_trusted")
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        let error = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard error == .success, let element = focusedElement else {
            print("[AccessibilityPlugin] no focused AX element (error=\(error.rawValue)) → clipboard fallback (\(context))")
            return fallbackPaste(text, reason: "no_focused_element")
        }

        let axElement = element as! AXUIElement

        let setResult = AXUIElementSetAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        if setResult == .success {
            print("[AccessibilityPlugin] ✅ kAXSelectedText succeeded (\(context))")
            return true
        }
        print("[AccessibilityPlugin] kAXSelectedText failed (error=\(setResult.rawValue)) (\(context))")

        let valueResult = AXUIElementSetAttributeValue(
            axElement,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )

        if valueResult == .success {
            print("[AccessibilityPlugin] ✅ kAXValue succeeded (\(context))")
            return true
        }
        print("[AccessibilityPlugin] kAXValue failed (error=\(valueResult.rawValue)) → clipboard fallback (\(context))")

        return fallbackPaste(text, reason: "ax_attributes_failed")
    }

    /// Places text on the clipboard and simulates ⌘V.
    private func fallbackPaste(_ text: String, reason: String) -> Bool {
        print("[AccessibilityPlugin] fallbackPaste (reason=\(reason))")
        let pasteboard = NSPasteboard.general
        
        // Save previous clipboard items to restore them later
        let previousItems = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }
        
        pasteboard.clearContents()
        
        // Declare types including TransientType, ConcealedType and AutoGeneratedType
        let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let autoGeneratedType = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
        
        pasteboard.declareTypes([.string, transientType, concealedType, autoGeneratedType], owner: nil)
        pasteboard.setString(text, forType: .string)
        
        // Also set data to empty for transient/concealed/auto-generated types
        pasteboard.setData(Data(), forType: transientType)
        pasteboard.setData(Data(), forType: concealedType)
        pasteboard.setData(Data(), forType: autoGeneratedType)

        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)

        print("[AccessibilityPlugin] posted ⌘V (keyDown=\(keyDown != nil), keyUp=\(keyUp != nil))")
        
        // Wait 250ms and restore previous clipboard items so user's clipboard is unchanged
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
            if let prev = previousItems {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects(prev)
                print("[AccessibilityPlugin] restored previous clipboard contents after fallback paste")
            }
        }
        
        return false
    }
}

class HotkeyPlugin: NSObject, FlutterPlugin {
    private static var channel: FlutterMethodChannel?
    private static var instance: HotkeyPlugin?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    // Tap tracking
    private var ctrlTapCount = 0
    private var lastCtrlTapTime: TimeInterval = 0
    private var targetTapCount = 2
    private var lastKeyCode: UInt16 = 0
    private var isListening = false

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.dictator/hotkey",
            binaryMessenger: registrar.messenger
        )
        let instance = HotkeyPlugin()
        HotkeyPlugin.instance = instance
        registrar.addMethodCallDelegate(instance, channel: channel)
        HotkeyPlugin.channel = channel
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startListening":
            guard let args = call.arguments as? [String: Any],
                  let target = args["targetCount"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'targetCount'", details: nil))
                return
            }
            targetTapCount = target
            startListening()
            result(nil)
        case "stopListening":
            stopListening()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startListening() {
        guard !isListening else { return }
        isListening = true
        print("[HotkeyPlugin] 🟢 startListening called, targetTapCount = \(targetTapCount)")
        
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
    }

    private func stopListening() {
        guard isListening else { return }
        isListening = false
        print("[HotkeyPlugin] 🔴 stopListening called")
        
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        print("[HotkeyPlugin] ⌨️ flagsChanged event received: keyCode = \(event.keyCode), modifierFlags = \(event.modifierFlags.rawValue)")
        
        // Left Control is 59, Right Control is 62
        guard event.keyCode == 62 || event.keyCode == 59 else {
            ctrlTapCount = 0
            lastKeyCode = 0
            return
        }
        
        let isControlPressed = event.modifierFlags.contains(.control)
        print("[HotkeyPlugin]   Is Control modifier pressed? \(isControlPressed)")
        guard isControlPressed else {
            return
        }
        
        let now = NSDate().timeIntervalSince1970
        let timeDiff = now - lastCtrlTapTime
        lastCtrlTapTime = now
        
        if event.keyCode == lastKeyCode && timeDiff < 0.4 {
            ctrlTapCount += 1
            print("[HotkeyPlugin]   Matching key sequence. Tap count incremented to: \(ctrlTapCount) (timeDiff = \(timeDiff)s)")
        } else {
            ctrlTapCount = 1
            print("[HotkeyPlugin]   New or timed-out key sequence. Tap count reset to: 1 (timeDiff = \(timeDiff)s)")
        }
        lastKeyCode = event.keyCode
        
        if ctrlTapCount >= targetTapCount {
            print("[HotkeyPlugin]   🔥 Target tap count reached (\(ctrlTapCount) >= \(targetTapCount)). Triggering hotkey!")
            ctrlTapCount = 0
            lastKeyCode = 0
            HotkeyPlugin.channel?.invokeMethod("onHotkeyTriggered", arguments: nil)
        }
    }
}

