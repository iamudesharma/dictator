import Cocoa
import FlutterMacOS
import ServiceManagement
import Security
import CoreAudio
import IOKit.hidsystem
import Carbon
import UniformTypeIdentifiers

class AccessibilityPlugin: NSObject, FlutterPlugin {
    private static var instance: AccessibilityPlugin?
    /// App that owned the selection when [copySelectedText] last ran (before our HUD opens).
    private var lastTargetAppPID: pid_t = 0
    private let audioOutput = AudioOutputController()
    private var terminalPaste = false
    private var restoreClipboard = true
    private let indicator = DictationIndicatorController()
    private var dictationTargetPID: pid_t = 0
    private var dictationTargetElement: AXUIElement?


    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.aurascribe/accessibility",
            binaryMessenger: registrar.messenger
        )
        let instance = AccessibilityPlugin()
        AccessibilityPlugin.instance = instance
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "showAbout":
            NSApp.orderFrontStandardAboutPanel(options: [:]); NSApp.activate(ignoringOtherApps: true); result(nil)
        case "currentKeyboardSource":
            let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            if let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                result(Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String)
            } else { result("") }
        case "keyboardSources":
            let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
            let rows: [[String: String]] = sources.compactMap { source in
                guard let category = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory),
                      Unmanaged<CFString>.fromOpaque(category).takeUnretainedValue() == kTISCategoryKeyboardInputSource,
                      let selectable = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable),
                      CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(selectable).takeUnretainedValue()),
                      let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                      let name = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return nil }
                return ["id": Unmanaged<CFString>.fromOpaque(id).takeUnretainedValue() as String,
                        "name": Unmanaged<CFString>.fromOpaque(name).takeUnretainedValue() as String]
            }
            result(rows)
        case "chooseBenchmarkAudio":
            let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.wav]
            panel.begin { response in result(response == .OK ? panel.url?.path : nil) }
        case "chooseSpeechModel":
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [UTType(filenameExtension: "gguf") ?? .data]
            panel.begin { response in result(response == .OK ? panel.url?.path : nil) }
        case "showDictationIndicator":
            result(indicator.show(call.arguments as? [String: Any] ?? [:]))
        case "updateDictationIndicator":
            indicator.update(call.arguments as? [String: Any] ?? [:]); result(nil)
        case "hideDictationIndicator":
            indicator.hide(); result(nil)
        case "beginDictationTarget":
            let app = NSWorkspace.shared.frontmostApplication
            dictationTargetPID = app?.processIdentifier ?? 0
            dictationTargetElement = editableFocusedElement(in: dictationTargetPID)
            result(["bundleId": app?.bundleIdentifier ?? "", "name": app?.localizedName ?? ""])
        case "endDictationTarget":
            dictationTargetPID = 0; dictationTargetElement = nil; result(nil)
        case "frontmostApplication":
            let app = NSWorkspace.shared.frontmostApplication
            result(["bundleId": app?.bundleIdentifier ?? "", "name": app?.localizedName ?? ""])
        case "beginAudioOutput":
            do {
                let args = call.arguments as? [String: Any] ?? [:]
                try audioOutput.begin(pauseBrowser: args["pauseBrowser"] as? Bool ?? false, speakersOnly: args["speakersOnly"] as? Bool ?? false, mode: args["mode"] as? String ?? "unchanged", level: args["level"] as? Double ?? 0.2)
                result(nil)
            } catch { result(FlutterError(code: "AUDIO_OUTPUT", message: error.localizedDescription, details: nil)) }
        case "restoreAudioOutput":
            do { try audioOutput.restore(); result(nil) }
            catch { result(FlutterError(code: "AUDIO_OUTPUT", message: error.localizedDescription, details: nil)) }
        case "readHfToken":
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.aurascribe.huggingface",
                kSecAttrAccount as String: "token", kSecReturnData as String: true]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecSuccess, let data = item as? Data {
                result(String(data: data, encoding: .utf8) ?? "")
            } else if status == errSecItemNotFound { result("") }
            else { result(FlutterError(code: "KEYCHAIN", message: "Could not read token (\(status))", details: nil)) }
        case "writeHfToken":
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.aurascribe.huggingface",
                kSecAttrAccount as String: "token"]
            let text = call.arguments as? String ?? ""
            var status: OSStatus
            if text.isEmpty { status = SecItemDelete(query as CFDictionary) }
            else {
                let attributes = [kSecValueData as String: Data(text.utf8)]
                status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
                if status == errSecItemNotFound {
                    var add = query
                    add[kSecValueData as String] = Data(text.utf8)
                    status = SecItemAdd(add as CFDictionary, nil)
                }
            }
            if status == errSecSuccess || (text.isEmpty && status == errSecItemNotFound) { result(nil) }
            else { result(FlutterError(code: "KEYCHAIN", message: "Could not save token (\(status))", details: nil)) }
        case "setProjectRoot":
            if let path = call.arguments as? String, FileManager.default.fileExists(atPath: path + "/pubspec.yaml") {
                UserDefaults.standard.set(path, forKey: "AuraScribeProjectRoot")
            }
            result(nil)
        case "projectRoot":
            let compiled = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().path
            result(UserDefaults.standard.string(forKey: "AuraScribeProjectRoot") ?? compiled)
        case "positionDictationPanel":
            if let window = NSApp.windows.compactMap({ $0 as? MainFlutterWindow }).first,
               let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
                window.isDictationPanel = true
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                let frame = screen.visibleFrame
                window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2,
                                               y: (call.arguments as? Bool ?? true)
                                                  ? frame.maxY - window.frame.height - 12
                                                  : frame.minY + 16))
            }
            result(nil)
        case "restoreSettingsWindow":
            if let window = NSApp.windows.compactMap({ $0 as? MainFlutterWindow }).first {
                window.isDictationPanel = false
                window.collectionBehavior = []
            }
            result(nil)
        case "launchAtLogin":
            result(SMAppService.mainApp.status == .enabled)
        case "setLaunchAtLogin":
            do {
                if call.arguments as? Bool == true { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                result(SMAppService.mainApp.status == .enabled)
            } catch {
                result(FlutterError(code: "LOGIN_ITEM", message: error.localizedDescription, details: nil))
            }

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
            terminalPaste = args["terminalPaste"] as? Bool ?? false
            restoreClipboard = args["restoreClipboard"] as? Bool ?? true
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
            let original = args["returnToApp"] as? Bool ?? true
            let pid = original && dictationTargetPID != 0 ? dictationTargetPID : front
            let captured = pid == dictationTargetPID ? dictationTargetElement : nil
            let element = captured ?? focusedElement(in: pid)
            let output = args["smartSpacing"] as? Bool == true ? spacedText(text, element: element) : text
            performInsertion(output, pid: pid, element: captured, result: result)

        case "replaceSelectedText":
            guard let args = call.arguments as? [String: Any],
                  let text = args["text"] as? String else {
                print("[AccessibilityPlugin] replaceSelectedText — INVALID_ARGS")
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'text'", details: nil))
                return
            }
            print("[AccessibilityPlugin] replaceSelectedText called (\(text.count) chars)")
            terminalPaste = args["terminalPaste"] as? Bool ?? false
            restoreClipboard = args["restoreClipboard"] as? Bool ?? true
            performInsertion(text, pid: lastTargetAppPID, element: nil, result: result)

        case "selectFocusedText":
            guard let element = dictationTargetElement else { result(nil); return }
            var roleValue: CFTypeRef?, value: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
            guard let role = roleValue as? String, [kAXTextFieldRole as String, kAXTextAreaRole as String].contains(role),
                  AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
                  let text = value as? String else { result(nil); return }
            var range = CFRange(location: 0, length: (text as NSString).length)
            guard let selection = AXValueCreate(.cfRange, &range), AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, selection) == .success else { result(nil); return }
            result(text)
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

    private func focusedElement(in pid: pid_t) -> AXUIElement? {
        guard pid > 0, AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let element = value, CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        return (element as! AXUIElement)
    }

    private func editableFocusedElement(in pid: pid_t) -> AXUIElement? {
        guard let element = focusedElement(in: pid) else { return nil }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        // Chromium/Electron may expose only a web area or window while their
        // accessibility tree initializes. Those containers are not text targets
        // and cannot be restored with AXFocused. Keep the original app pinned.
        guard let value = role as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(value) else { return nil }
        return element
    }

    /// Activation is asynchronous; wait for the original app instead of pasting
    /// into whichever window happens to own focus after the overlay appeared.
    private func performInsertion(_ text: String, pid: pid_t, element: AXUIElement?, result: @escaping FlutterResult) {
        guard AXIsProcessTrusted() else {
            result(FlutterError(code: "ACCESSIBILITY_REQUIRED", message: "Enable AuraScribe in System Settings → Privacy & Security → Accessibility, then use Paste last dictation.", details: nil)); return
        }
        guard pid > 0, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            result(FlutterError(code: "TARGET_CLOSED", message: "The original application is no longer open. Click a text field and use Paste last dictation.", details: nil)); return
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        let deadline = Date().addingTimeInterval(0.8)
        func attempt() {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                if Date() < deadline { DispatchQueue.main.asyncAfter(deadline: .now() + 0.025, execute: attempt) }
                else { result(FlutterError(code: "TARGET_FOCUS", message: "Could not activate the original app. Click its text field and use Paste last dictation.", details: nil)) }
                return
            }
            if let captured = element {
                var owner: pid_t = 0
                guard AXUIElementGetPid(captured, &owner) == .success, owner == pid else {
                    result(FlutterError(code: "TARGET_FIELD_CLOSED", message: "The original text field is no longer available. Click a text field and use Paste last dictation.", details: nil)); return
                }
                let current = focusedElement(in: pid)
                if current == nil || !CFEqual(current!, captured) {
                    _ = AXUIElementSetAttributeValue(captured, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                    guard let restored = focusedElement(in: pid), CFEqual(restored, captured) else {
                        result(FlutterError(code: "TARGET_FIELD_FOCUS", message: "The original text field lost focus. Click it and use Paste last dictation.", details: nil)); return
                    }
                }
            }
            do { try insertTextInFocusedElement(text, element: element ?? focusedElement(in: pid), result: result) }
            catch { result(FlutterError(code: "INSERTION_FAILED", message: error.localizedDescription, details: nil)) }
        }
        attempt()
    }

    private func spacedText(_ text: String, element: AXUIElement?) -> String {
        guard let element = element, let first = text.first, first.isLetter || first.isNumber else { return text }
        var rangeValue: CFTypeRef?, contentValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let raw = rangeValue, CFGetTypeID(raw) == AXValueGetTypeID(),
              AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &contentValue) == .success,
              let content = contentValue as? String else { return text }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range), range.length == 0, range.location > 0 else { return text }
        let string = content as NSString
        guard range.location <= string.length else { return text }
        let previous = string.substring(with: string.rangeOfComposedCharacterSequence(at: range.location - 1))
        return previous.last.map { $0.isLetter || $0.isNumber } == true ? " " + text : text
    }

    private func insertTextInFocusedElement(_ text: String, element: AXUIElement?, result: @escaping FlutterResult) throws {
        // AXSelectedText may report success without updating a web editor's DOM
        // or firing its input events. Use the application's normal input path.
        let app = NSWorkspace.shared.frontmostApplication
        if TextInsertionPolicy.hasClipboardRace(bundleURL: app?.bundleURL) {
            let events = try TextInsertionPolicy.unicodeEvents(text)
            for event in events { event.post(tap: .cghidEventTap) }
            if !restoreClipboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { result(false) }
        } else {
            try fallbackPaste(text, reason: "application_input", result: result)
        }
    }

    /// Places text on the clipboard and simulates ⌘V.
    private func fallbackPaste(_ text: String, reason: String, result: @escaping FlutterResult) throws {
        print("[AccessibilityPlugin] fallbackPaste (reason=\(reason))")
        let flags: CGEventFlags = terminalPaste && isTerminalApp() ? [.maskControl, .maskShift] : .maskCommand
        let source = CGEventSource(stateID: .privateState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            throw NSError(domain: "AuraScribe", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create the paste key events."])
        }
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

        let insertedChangeCount = pasteboard.changeCount
        let shouldRestore = restoreClipboard
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        // Keep the clipboard stable until the app has consumed the paste. The
        // method completes after settling, so live deltas cannot overwrite it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            defer { result(false) }
            guard shouldRestore else { return }
            let pb = NSPasteboard.general
            guard pb.changeCount == insertedChangeCount else { return }
            pb.clearContents()
            if let prev = previousItems { pb.writeObjects(prev) }
        }

    }
    private func isTerminalApp() -> Bool {
        let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        return ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
                "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm"].contains(id)
    }

}

class HotkeyPlugin: NSObject, FlutterPlugin {
    private static var channel: FlutterMethodChannel?
    private static var instance: HotkeyPlugin?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    private var auxiliaryGlobal: Any?
    private var auxiliaryLocal: Any?
    private var modifierKeyCode: UInt16?
    private var anyOption = false
    private var holdMode = true
    private var modifierDown = false
    private var capsEnabled = false, capsOriginal = false, capsUpdating = false
    private var capsIndicator = false
    private func capsLock(_ state: Bool? = nil) -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS else { return false }
        defer { IOServiceClose(connection) }
        var value = false
        _ = IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &value)
        if let state = state { _ = IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), state) }
        return value
    }
    private func setCapsLight(_ value: Bool) {
        capsUpdating = true; _ = capsLock(value)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.capsUpdating = false }
    }
    private let nativeShortcuts = NativeShortcutMonitor()
    private var modifierActive = false
    private var holdTimer: DispatchWorkItem?

    // Tap tracking
    private var ctrlTapCount = 0
    private var lastCtrlTapTime: TimeInterval = 0
    private var targetTapCount = 2
    private var lastKeyCode: UInt16 = 0
    private var isListening = false

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.aurascribe/hotkey",
            binaryMessenger: registrar.messenger
        )
        let instance = HotkeyPlugin()
        HotkeyPlugin.instance = instance
        registrar.addMethodCallDelegate(instance, channel: channel)
        HotkeyPlugin.channel = channel
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setRecordingCapsLock":
            let active = call.arguments as? Bool ?? false
            if capsEnabled && active != capsIndicator { capsIndicator = active; setCapsLight(active) }
            result(nil)
        case "configureNativeShortcuts":
            do {
                try nativeShortcuts.configure(call.arguments as? [[String: Any]] ?? []) { action, down in
                    HotkeyPlugin.channel?.invokeMethod("onNativeShortcut", arguments: ["action": action, "down": down])
                }; result(nil)
            } catch { result(FlutterError(code: "SHORTCUT_PERMISSION", message: error.localizedDescription, details: nil)) }
        case "configureAuxiliary":
            if let monitor = auxiliaryGlobal { NSEvent.removeMonitor(monitor) }; auxiliaryGlobal = nil
            if let monitor = auxiliaryLocal { NSEvent.removeMonitor(monitor) }; auxiliaryLocal = nil
            let args = call.arguments as? [String: Any] ?? [:]
            let caps = args["capsLock"] as? Bool ?? false, button = args["mouseButton"] as? Int ?? -1
            if caps && !capsEnabled { capsOriginal = capsLock(); setCapsLight(capsIndicator) }
            if !caps && capsEnabled { setCapsLight(capsOriginal) }
            capsEnabled = caps
            let handler: (NSEvent) -> Void = { [weak self] event in
                guard let self = self, !self.capsUpdating else { return }
                if (caps && event.type == .flagsChanged && event.keyCode == 57) ||
                   (event.type == .otherMouseDown && button >= 2 && event.buttonNumber == button) {
                    HotkeyPlugin.channel?.invokeMethod("onAuxiliaryToggle", arguments: nil)
                }
            }
            if caps || button >= 2 {
                auxiliaryGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .otherMouseDown], handler: handler)
                auxiliaryLocal = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .otherMouseDown]) { event in handler(event); return event }
            }
            result(nil)
        case "startModifierListening":
            guard let args = call.arguments as? [String: Any],
                  let code = args["keyCode"] as? Int,
                  [54, 55, 56, 58, 59, 60, 61, 62, 63].contains(code) else {
                result(FlutterError(code: "INVALID_ARGS", message: "Unsupported modifier key", details: nil)); return
            }
            stopListening()
            modifierKeyCode = UInt16(code)
            anyOption = args["anyOption"] as? Bool ?? false
            holdMode = args["hold"] as? Bool ?? true
            startListening()
            result(nil)
        case "startListening":
            guard let args = call.arguments as? [String: Any],
                  let target = args["targetCount"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'targetCount'", details: nil))
                return
            }
            stopListening()
            modifierKeyCode = nil
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
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            handler(event)
            return event
        }
    }

    private func stopListening() {
        releaseModifier()
        modifierKeyCode = nil
        ctrlTapCount = 0
        lastKeyCode = 0
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

    private func releaseModifier() {
        holdTimer?.cancel(); holdTimer = nil
        modifierDown = false
        if modifierActive {
            modifierActive = false
            HotkeyPlugin.channel?.invokeMethod("onModifierReleased", arguments: nil)
        }
    }

    private func handleModifier(_ event: NSEvent, code: UInt16) {
        if event.type == .keyDown {
            // A normal Option+key chord must not start dictation.
            if !modifierActive { holdTimer?.cancel(); holdTimer = nil }
            return
        }
        let mask: NSEvent.ModifierFlags
        switch code {
        case 58, 61: mask = .option
        case 59, 62: mask = .control
        case 55, 54: mask = .command
        case 56, 60: mask = .shift
        default: mask = .function
        }
        let pressed = anyOption || code == 63
            ? event.modifierFlags.contains(mask)
            : CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code))
        if !pressed { releaseModifier(); return }
        if modifierDown {
            if !modifierActive {
                let other: NSEvent.ModifierFlags = [.option, .control, .command, .shift, .function]
                if event.modifierFlags.intersection(other) != mask { holdTimer?.cancel(); holdTimer = nil }
            }
            return
        }
        // Only arm a standalone modifier, not Command+Option etc.
        let relevant: NSEvent.ModifierFlags = [.option, .control, .command, .shift, .function]
        guard event.modifierFlags.intersection(relevant) == mask else { return }
        modifierDown = true
        let activate = DispatchWorkItem { [weak self] in
            guard let self = self, self.isListening, self.modifierDown else { return }
            self.modifierActive = true
            HotkeyPlugin.channel?.invokeMethod("onModifierPressed", arguments: nil)
        }
        holdTimer = activate
        DispatchQueue.main.asyncAfter(deadline: .now() + (holdMode ? 0.18 : 0), execute: activate)
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        if let code = modifierKeyCode { handleModifier(event, code: code); return }
        guard event.type == .flagsChanged else { return }
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


/// A crash-recoverable volume lease on the original output device. A manual
/// volume change wins: restore only values still equal to the ones we applied.
private final class AudioOutputController {
    private var pausedBrowser: String?
    private func browserScript(_ id: String, _ javascript: String, allTabs: Bool = false) -> Bool {
        // Both arguments originate in this class, never from a transcript.
        let escaped = javascript.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let command: String
        if allTabs {
            let operation = id == "com.apple.Safari" ? "do JavaScript \"\(escaped)\" in t" : "execute t javascript \"\(escaped)\""
            command = "repeat with w in windows\nrepeat with t in tabs of w\ntry\n\(operation)\nend try\nend repeat\nend repeat"
        } else {
            command = id == "com.apple.Safari" ? "do JavaScript \"\(escaped)\" in current tab of front window" : "execute active tab of front window javascript \"\(escaped)\""
        }
        var error: NSDictionary?
        NSAppleScript(source: "tell application id \"\(id)\"\n\(command)\nend tell")?.executeAndReturnError(&error)
        return error == nil
    }

    private var receiptURL: URL {
        let compiled = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
        return URL(fileURLWithPath: UserDefaults.standard.string(forKey: "AuraScribeProjectRoot") ?? compiled)
            .appendingPathComponent(".aurascribe/audio/audio-output-lease.json")
    }
    private func address(_ selector: AudioObjectPropertySelector, _ element: UInt32 = 0) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }
    private func check(_ status: OSStatus) throws { if status != noErr { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) } }
    func begin(pauseBrowser: Bool = false, speakersOnly: Bool = false, mode: String, level: Double) throws {
        try restore()
        if pauseBrowser, let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser"].contains(id) {
            if browserScript(id, "window.__auraPaused = Array.from(document.querySelectorAll('audio,video')).filter(e=>!e.paused);window.__auraPaused.forEach(e=>e.pause());") { pausedBrowser = id }
        }
        guard mode != "unchanged" else { return }
        var query = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        var device: AudioDeviceID = 0; var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &query, 0, nil, &size, &device))
        if speakersOnly {
            var transport = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
            var kind: UInt32 = 0; var count: UInt32 = 4
            guard AudioObjectGetPropertyData(device, &transport, 0, nil, &count, &kind) == noErr,
                  kind == kAudioDeviceTransportTypeBuiltIn else { return }
            var source = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource, mScope: kAudioDevicePropertyScopeOutput, mElement: 0)
            var value: UInt32 = 0
            guard AudioObjectGetPropertyData(device, &source, 0, nil, &count, &value) == noErr,
                  value == 0x6973706b else { return } // 'ispk': internal speakers; unknown routes stay unchanged.
        }
        var changes = [[String: Any]]()
        let selector = mode == "mute" ? kAudioDevicePropertyMute : kAudioDevicePropertyVolumeScalar
        for element: UInt32 in [0, 1, 2] {
            var property = address(selector, element); var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(device, &property),
                  AudioObjectIsPropertySettable(device, &property, &settable) == noErr, settable.boolValue else { continue }
            var value: Float32 = 0; var muted: UInt32 = 0; var bytes: UInt32 = 4
            if mode == "mute" {
                try check(AudioObjectGetPropertyData(device, &property, 0, nil, &bytes, &muted))
            } else { try check(AudioObjectGetPropertyData(device, &property, 0, nil, &bytes, &value)) }
            let before = mode == "mute" ? Double(muted) : Double(value)
            let applied = mode == "mute" ? 1.0 : before * min(1, max(0, level))
            changes.append(["element": element, "before": before, "applied": applied])
            if element == 0 { break }
        }
        guard !changes.isEmpty else { throw NSError(domain: "AuraScribe", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "This output device does not support system volume control. Choose Leave unchanged."]) }
        let uidPointer = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: 1)
        uidPointer.initialize(to: nil)
        defer { uidPointer.deinitialize(count: 1); uidPointer.deallocate() }
        var uidAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        var uidBytes = UInt32(MemoryLayout<CFString>.size)
        try check(AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidBytes, uidPointer))
        guard let returnedUID = uidPointer.pointee else { throw NSError(domain: "AuraAudio", code: 3) }
        let uid = returnedUID.takeRetainedValue() as String
        let data = try JSONSerialization.data(withJSONObject: ["deviceUID": uid, "device": device, "selector": selector, "mode": mode, "changes": changes])
        try FileManager.default.createDirectory(at: receiptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: receiptURL, options: .atomic)
        do {
            for change in changes {
                var property = address(selector, change["element"] as! UInt32)
                if mode == "mute" { var value: UInt32 = 1; try check(AudioObjectSetPropertyData(device, &property, 0, nil, 4, &value)) }
                else { var value = Float32(change["applied"] as! Double); try check(AudioObjectSetPropertyData(device, &property, 0, nil, 4, &value)) }
            }
        } catch { try? restore(); throw error }
    }
    func restore() throws {
        if let id = pausedBrowser {
            _ = browserScript(id, "(window.__auraPaused||[]).forEach(e=>e.play().catch(()=>{}));window.__auraPaused=[];", allTabs: true)
            pausedBrowser = nil
        }
        guard FileManager.default.fileExists(atPath: receiptURL.path) else { return }
        let data = try Data(contentsOf: receiptURL)
        guard let saved = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let deviceUID = saved["deviceUID"] as? String, let selector = saved["selector"] as? UInt32,
            let mode = saved["mode"] as? String, let changes = saved["changes"] as? [[String: Any]] else { return }
        guard let device = try? AuraAudioDevice.resolve(deviceUID) else {
            try FileManager.default.removeItem(at: receiptURL); return
        }
        for change in changes {
            guard let element = change["element"] as? UInt32, let before = change["before"] as? Double,
                  let applied = change["applied"] as? Double else { continue }
            var property = address(selector, element); var bytes: UInt32 = 4
            guard AudioObjectHasProperty(device, &property) else { continue }
            if mode == "mute" {
                var current: UInt32 = 0
                if AudioObjectGetPropertyData(device, &property, 0, nil, &bytes, &current) == noErr && current == UInt32(applied) {
                    var value = UInt32(before); try check(AudioObjectSetPropertyData(device, &property, 0, nil, 4, &value))
                }
            } else {
                var current: Float32 = 0
                if AudioObjectGetPropertyData(device, &property, 0, nil, &bytes, &current) == noErr && abs(Double(current) - applied) < 0.002 {
                    var value = Float32(before); try check(AudioObjectSetPropertyData(device, &property, 0, nil, 4, &value))
                }
            }
        }
        try FileManager.default.removeItem(at: receiptURL)
    }
}

/// Optional event tap for sided chords and shortcuts shared with the foreground app.
private final class NativeShortcutMonitor {
    private final class Binding {
        let action: String, key: CGKeyCode, flags: CGEventFlags, sides: [CGKeyCode], modifierOnly: Bool, share: Bool, anyOption: Bool
        var down = false, emitted = false, cancelled = false, consumedDown = false
        var timer: DispatchWorkItem?
        init?(_ data: [String: Any]) {
            guard let action = data["action"] as? String, let code = data["keyCode"] as? Int else { return nil }
            self.action = action; key = CGKeyCode(code)
            modifierOnly = data["modifierOnly"] as? Bool ?? false; anyOption = data["anyOption"] as? Bool ?? false; share = data["share"] as? Bool ?? false
            sides = (data["sides"] as? [Int] ?? []).map { CGKeyCode($0) }
            var mask = CGEventFlags()
            for name in data["modifiers"] as? [String] ?? [] {
                switch name { case "alt": mask.insert(.maskAlternate); case "meta": mask.insert(.maskCommand); case "shift": mask.insert(.maskShift); case "control": mask.insert(.maskControl); case "fn": mask.insert(.maskSecondaryFn); default: break }
            }
            if modifierOnly { mask.formUnion(NativeShortcutMonitor.modifierMask(key)) }
            flags = mask
        }
    }
    private var tap: CFMachPort?, source: CFRunLoopSource?
    private var bindings: [Binding] = []
    private var emit: ((String, Bool) -> Void)?
    private static func modifierMask(_ code: CGKeyCode) -> CGEventFlags {
        switch code { case 58, 61: return .maskAlternate; case 59, 62: return .maskControl; case 54, 55: return .maskCommand; case 56, 60: return .maskShift; default: return .maskSecondaryFn }
    }
    func configure(_ rows: [[String: Any]], emit: @escaping (String, Bool) -> Void) throws {
        stop(); self.emit = emit; bindings = rows.compactMap(Binding.init)
        guard !bindings.isEmpty else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
            guard let context = context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<NativeShortcutMonitor>.fromOpaque(context).takeUnretainedValue()
            return monitor.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap = tap else { bindings = []; throw NSError(domain: "AuraShortcut", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enable Accessibility permission to use sided or shared shortcuts."]) }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    func stop() {
        for binding in bindings { binding.timer?.cancel(); if binding.emitted { emit?(binding.action, false) } }
        bindings = []
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }; source = nil
        if let tap = tap { CFMachPortInvalidate(tap) }; tap = nil
    }
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }; return false }
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
        var consume = false
        for b in bindings {
            if b.modifierOnly && type == .keyDown {
                b.cancelled = true; b.timer?.cancel(); continue
            }
            let primary = b.modifierOnly ? (b.anyOption ? event.flags.contains(.maskAlternate) : CGEventSource.keyState(.combinedSessionState, key: b.key)) : code == b.key && type == .keyDown
            let matches = primary && event.flags.intersection(relevant) == b.flags && b.sides.allSatisfy { CGEventSource.keyState(.combinedSessionState, key: $0) }
            if !b.modifierOnly && code != b.key && !(b.down && event.flags.intersection(relevant) != b.flags) { continue }
            if !b.modifierOnly && code == b.key && type == .keyUp && b.consumedDown { consume = true; b.consumedDown = false }
            if matches && !b.down {
                b.consumedDown = !b.share
                b.down = true; b.cancelled = false
                if b.modifierOnly {
                    let timer = DispatchWorkItem { [weak self, weak b] in
                        guard let b = b, b.down, !b.cancelled else { return }
                        b.emitted = true; self?.emit?(b.action, true)
                    }
                    b.timer = timer; DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: timer)
                } else { b.emitted = true; emit?(b.action, true) }
            } else if !matches && b.down {
                b.timer?.cancel()
                if b.modifierOnly && !b.emitted && !b.cancelled { emit?(b.action, true); b.emitted = true }
                if b.emitted { emit?(b.action, false) }
                b.down = false; b.emitted = false
            }
            // Modifier transitions must reach macOS to avoid stuck modifier state.
            if !b.modifierOnly && code == b.key && !b.share && matches { consume = true }
        }
        return consume
    }
    deinit { stop() }
}
