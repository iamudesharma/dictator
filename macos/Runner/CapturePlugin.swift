import Cocoa
import FlutterMacOS
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import Vision
import CoreAudio
import AudioToolbox
import Darwin

final class CapturePlugin: NSObject, FlutterPlugin {
    private let meeting = MeetingRecorder()
    private let capsule = MeetingCapsule()
    private var channel: FlutterMethodChannel?
    private var player: AVAudioPlayer?
    private var video: Process?
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.aurascribe/capture", binaryMessenger: registrar.messenger)
        let instance = CapturePlugin(); instance.channel = channel
        instance.capsule.onStop = { channel.invokeMethod("stopMeeting", arguments: nil) }
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startScreenRecording":
            guard let path = call.arguments as? String, CGPreflightScreenCaptureAccess(), video == nil else {
                result(FlutterError(code: "SCREEN_RECORDING", message: "Allow screen recording and stop any active recording first.", details: nil)); return
            }
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-v", "-x", path]
            do { try process.run(); video = process; result(nil) }
            catch { result(FlutterError(code: "SCREEN_RECORDING", message: error.localizedDescription, details: nil)) }
        case "stopScreenRecording":
            if let process = video { if process.isRunning { process.interrupt() }; video = nil
                DispatchQueue.global().async { process.waitUntilExit(); DispatchQueue.main.async { result(nil) } }
            } else { result(nil) }
        case "copyImage", "shareImage":
            guard let path = call.arguments as? String, let image = NSImage(contentsOfFile: path) else {
                result(FlutterError(code: "IMAGE", message: "Image unavailable.", details: nil)); return
            }
            if call.method == "copyImage" { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image]) }
            else if let view = NSApp.keyWindow?.contentView {
                NSSharingServicePicker(items: [URL(fileURLWithPath: path)]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            }
            result(nil)
        case "imageSize":
            guard let path = call.arguments as? String, let image = NSImage(contentsOfFile: path), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { result(nil); return }
            result(["width": cg.width, "height": cg.height])
        case "cropImage":
            guard let args = call.arguments as? [String: Any], let path = args["path"] as? String,
                let image = NSImage(contentsOfFile: path), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                result(FlutterError(code: "CROP", message: "Image unavailable.", details: nil)); return
            }
            let x = args["x"] as? Double ?? 0, y = args["y"] as? Double ?? 0
            let w = args["width"] as? Double ?? 1, h = args["height"] as? Double ?? 1
            guard w > 0, h > 0, let cropped = cg.cropping(to: CGRect(x: x * Double(cg.width), y: y * Double(cg.height), width: w * Double(cg.width), height: h * Double(cg.height))) else {
                result(FlutterError(code: "CROP", message: "Select a nonempty crop.", details: nil)); return
            }
            do { try NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path), options: .atomic); result(nil) }
            catch { result(FlutterError(code: "CROP", message: error.localizedDescription, details: nil)) }
        case "chooseAudio":
            let panel = NSOpenPanel(); panel.canChooseDirectories = false
            panel.allowedFileTypes = ["wav", "mp3", "m4a", "aac", "aiff", "flac", "mp4", "mov"]
            panel.begin { response in result(response == .OK ? panel.url?.path : nil) }
        case "playAudio":
            guard let path = call.arguments as? String else { result(nil); return }
            do { player?.stop(); player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)); player?.play(); result(nil) }
            catch { result(FlutterError(code: "PLAYBACK", message: error.localizedDescription, details: nil)) }
        case "stopAudio": player?.stop(); player = nil; result(nil)
        case "captureRegion", "captureWindow":
            guard let path = call.arguments as? String, CGPreflightScreenCaptureAccess() else {
                result(FlutterError(code: "SCREEN_PERMISSION", message: "Allow Screen & System Audio Recording in System Settings.", details: nil)); return
            }
            NSApp.hide(nil)
            let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = call.method == "captureWindow" ? ["-i", "-w", "-x", path] : ["-i", "-x", path]
            capture.terminationHandler = { process in DispatchQueue.main.async {
                NSApp.unhide(nil); result(process.terminationStatus == 0 && FileManager.default.fileExists(atPath: path))
            } }
            do { try capture.run() } catch { NSApp.unhide(nil); result(FlutterError(code: "CAPTURE", message: error.localizedDescription, details: nil)) }
        case "recognizeText":
            guard let path = call.arguments as? String else { result(""); return }
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
                    try VNImageRequestHandler(url: URL(fileURLWithPath: path)).perform([request])
                    let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
                    DispatchQueue.main.async { result(text) }
                } catch { DispatchQueue.main.async { result(FlutterError(code: "OCR", message: error.localizedDescription, details: nil)) } }
            }
        case "screenAccess": result(CGPreflightScreenCaptureAccess())
        case "requestScreenAccess": result(CGRequestScreenCaptureAccess())
        case "meetingStart":
            guard let args = call.arguments as? [String: Any], let directory = args["directory"] as? String else {
                result(FlutterError(code: "ARGUMENTS", message: "Missing meeting directory", details: nil)); return
            }
            Task { do {
                try await meeting.start(directory: URL(fileURLWithPath: directory), microphone: args["microphone"] as? Bool ?? true,
                    system: args["system"] as? Bool ?? true, echoCancellation: args["echoCancellation"] as? Bool ?? true, microphoneId: args["microphoneId"] as? String ?? "", live: args["live"] as? Bool ?? false)
                await MainActor.run { result(nil) }
            } catch { await MainActor.run { result(FlutterError(code: "MEETING_CAPTURE", message: error.localizedDescription, details: nil)) } } }
        case "meetingStop":
            Task { let status = await meeting.stop(); await MainActor.run { result(status) } }
        case "showMeetingCapsule":
            let args = call.arguments as? [String: String] ?? [:]
            capsule.show(args["title"] ?? call.arguments as? String ?? "AuraScribe", stopLabel: args["stop"] ?? "Stop"); result(nil)
        case "hideMeetingCapsule": capsule.hide(); result(nil)
        case "meetingStatus": result(meeting.status())
        case "activeCallApps": result(activeCallApps())
        case "browserCallPage":
            guard let args = call.arguments as? [String: Any], let id = args["id"] as? String,
                  activeCallApps().contains(where: { $0["id"] == id }) else { result([String: String]()); return }
            let automation = args["automation"] as? Bool ?? false
            BrowserCallReader.queue.async {
                let page = BrowserCallReader.read(id: id, automation: automation)
                DispatchQueue.main.async { result(page) }
            }
        case "trash":
            guard let path = call.arguments as? String else { result(nil); return }
            do { try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil); result(nil) }
            catch { result(FlutterError(code: "TRASH", message: error.localizedDescription, details: nil)) }
        default: result(FlutterMethodNotImplemented)
        }
    }
    private func activeCallApps() -> [[String: String]] {
        guard #available(macOS 14.2, *) else { return [] }
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        var bytes: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &bytes) == noErr else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &bytes, &objects) == noErr else { return [] }
        let known = ["us.zoom.xos", "com.tinyspeck.slackmacgap", "com.microsoft.teams2", "com.microsoft.teams", "com.hnc.Discord", "com.apple.FaceTime", "com.cisco.webexmeetingsapp", "org.whispersystems.signal-desktop", "ru.keepcoder.Telegram", "com.tencent.xinWeChat", "jp.naver.line.mac", "im.riot.app", "com.apple.Phone", "com.google.Chrome", "com.apple.Safari", "com.microsoft.edgemac", "org.mozilla.firefox", "com.brave.Browser"]
        let supported = Set(known).union(BrowserCallReader.ids)
        var result = [[String: String]]()
        for object in objects {
            var active: UInt32 = 0; var size: UInt32 = 4
            var running = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
            guard AudioObjectGetPropertyData(object, &running, 0, nil, &size, &active) == noErr, active != 0 else { continue }
            var pid: pid_t = 0
            var query = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
            guard AudioObjectGetPropertyData(object, &query, 0, nil, &size, &pid) == noErr else { continue }
            var bundleReference: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var bundleQuery = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
            let bundleStatus = AudioObjectGetPropertyData(object, &bundleQuery, 0, nil, &bundleSize, &bundleReference)
            // CoreAudio transfers ownership of this CFObject to the caller.
            let audioBundle = bundleStatus == noErr ? bundleReference?.takeRetainedValue() as String? : nil
            guard let app = Self.callApplication(pid: pid, audioBundle: audioBundle, supported: supported),
                  let id = app.bundleIdentifier else { continue }
            if !result.contains(where: { $0["id"] == id }) { result.append(["id": id, "name": app.localizedName ?? id]) }
        }
        return result
    }

    private static func callApplication(pid: pid_t, audioBundle: String?, supported: Set<String>) -> NSRunningApplication? {
        func canonical(_ value: String) -> String? {
            let lower = value.lowercased()
            // Longest first keeps Chrome Canary/Beta and Safari Technology Preview distinct.
            return supported.sorted { $0.count > $1.count }.first {
                lower == $0.lowercased() || lower.hasPrefix($0.lowercased() + ".")
            }
        }
        let direct = NSRunningApplication(processIdentifier: pid)
        if let app = direct, supported.contains(app.bundleIdentifier ?? "") { return app }
        // Sandboxed Chromium audio utilities often have no LaunchServices record.
        // Follow process ancestry, never the unrelated foreground application.
        var current = pid
        for _ in 0..<8 {
            var query: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, current]
            var info = kinfo_proc(); var bytes = MemoryLayout<kinfo_proc>.stride
            guard sysctl(&query, 4, &info, &bytes, nil, 0) == 0, bytes > 0 else { break }
            let parent = info.kp_eproc.e_ppid
            guard parent > 1, parent != current else { break }
            current = parent
            if let app = NSRunningApplication(processIdentifier: parent),
               let id = app.bundleIdentifier, supported.contains(id) {
                // Reject attribution when CoreAudio identifies a different known app.
                if let audio = audioBundle.flatMap(canonical), audio != id { continue }
                return app
            }
        }
        for bundle in [audioBundle, direct?.bundleIdentifier].compactMap({ $0 }) {
            if let id = canonical(bundle),
               let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first { return app }
        }
        // Safari's GPU service belongs to shared WebKit, so the bundle alone
        // cannot identify Safari. Require the OS-provided Safari process name.
        if (direct?.bundleIdentifier ?? audioBundle ?? "").lowercased() == "com.apple.webkit.gpu",
           direct?.localizedName?.lowercased().hasPrefix("safari") == true {
            return NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first
        }
        return nil
    }

}

/// Separate local and remote PCM WAV tracks, with clock offsets. ScreenCaptureKit
/// delivers system audio only; no screen frames are retained for meeting capture.
private final class MeetingRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label: "com.aurascribe.meeting.audio")
    private var stream: SCStream?
    private var engine: AVAudioEngine?
    private var micFile: AVAudioFile?
    private var systemFile: AVAudioFile?
    private var liveDirectory: URL?
    private var liveFiles = [String: AVAudioFile]()
    private var liveFrames = [String: Int64]()
    private var ready = [String]()
    private var liveIndex = [String: Int]()
    private var running = false
    private var failure: String?
    private var starts = [String: Double]()
    private var frames = [String: Int64]()
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private func file(_ url: URL) throws -> AVAudioFile {
        try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false], commonFormat: .pcmFormatFloat32, interleaved: false)
    }
    func start(directory: URL, microphone: Bool, system: Bool, echoCancellation: Bool, microphoneId: String, live: Bool = false) async throws {
        guard !running else { throw captureError("A meeting recording is already active.") }
        guard microphone || system else { throw captureError("Choose microphone or system audio.") }
        if microphone {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            if !allowed { throw captureError("Allow Microphone access in System Settings before recording.") }
        }
        if system && !CGPreflightScreenCaptureAccess() { throw captureError("Allow Screen & System Audio Recording in System Settings, then try again.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        queue.sync { starts = [:]; frames = [:]; failure = nil; ready = []; liveFiles = [:]; liveFrames = [:]; liveIndex = [:]; liveDirectory = live ? directory : nil }
        do {
            if system {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { throw captureError("No display is available for system audio capture.") }
                let config = SCStreamConfiguration()
                config.width = 2; config.height = 2; config.minimumFrameInterval = CMTime(value: 1, timescale: 2)
                config.capturesAudio = true; config.excludesCurrentProcessAudio = true
                config.sampleRate = 16000; config.channelCount = 1
                systemFile = try file(directory.appendingPathComponent("system.wav"))
                let recording = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
                try recording.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
                stream = recording; try await recording.startCapture()
            }
            if microphone {
                let audio = AVAudioEngine()
                try AuraAudioDevice.setInput(audio, uid: microphoneId)
                if echoCancellation { try audio.inputNode.setVoiceProcessingEnabled(true) }
                micFile = try file(directory.appendingPathComponent("microphone.wav"))
                let format = audio.inputNode.outputFormat(forBus: 0)
                audio.inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                    guard let self = self, let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
                    copy.frameLength = buffer.frameLength
                    let from = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
                    let to = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
                    for i in 0..<min(from.count, to.count) { if let src = from[i].mData, let dst = to[i].mData {
                        memcpy(dst, src, min(Int(from[i].mDataByteSize), Int(to[i].mDataByteSize)))
                    } }
                    self.queue.async { self.write(copy, track: "microphone") }
                }
                engine = audio; try audio.start()
            }
            running = true
        } catch { _ = await stop(); throw error }
    }
    private func write(_ input: AVAudioPCMBuffer, track: String) {
        guard failure == nil else { return }
        do {
            guard let converter = AVAudioConverter(from: input.format, to: outputFormat),
                  let output = AVAudioPCMBuffer(pcmFormat: outputFormat,
                    frameCapacity: AVAudioFrameCount(Double(input.frameLength) * 16000 / input.format.sampleRate) + 16) else { throw captureError("Could not convert captured audio.") }
            var supplied = false; var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return input
            }
            if let error = error { throw error }
            if starts[track] == nil { starts[track] = Date().timeIntervalSince1970 }
            if track == "microphone" { try micFile?.write(from: output) } else { try systemFile?.write(from: output) }
            frames[track, default: 0] += Int64(output.frameLength)
            if let directory = liveDirectory {
                if liveFiles[track] == nil { liveFiles[track] = try file(directory.appendingPathComponent("live-\(track)-\(liveIndex[track, default: 0]).wav")) }
                try liveFiles[track]?.write(from: output)
                liveFrames[track, default: 0] += Int64(output.frameLength)
                if liveFrames[track, default: 0] >= 400000 {
                    liveFiles[track] = nil
                    ready.append("live-\(track)-\(liveIndex[track, default: 0]).wav")
                    liveIndex[track, default: 0] += 1; liveFrames[track] = 0
                }
            }
        } catch { failure = error.localizedDescription }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let list = AudioBufferList.allocate(maximumBuffers: Int(format.channelCount))
        defer { list.unsafeMutablePointer.deallocate() }
        var block: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: nil,
            bufferListOut: list.unsafeMutablePointer, bufferListSize: AudioBufferList.sizeInBytes(maximumBuffers: Int(format.channelCount)),
            blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &block)
        guard status == noErr, let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list.unsafePointer, deallocator: nil) else { return }
        buffer.frameLength = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        write(buffer, track: "system")
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.failure = error.localizedDescription }
        engine?.stop()
        running = false
    }
    func status() -> [String: Any] { queue.sync {
        ["running": running, "error": failure ?? "", "starts": starts, "frames": frames, "ready": ready]
    } }
    func stop() async -> [String: Any] {
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        if let capture = stream { try? await capture.stopCapture() }; stream = nil
        running = false
        return queue.sync { liveFiles = [:]; micFile = nil; systemFile = nil; return ["running": false, "error": failure ?? "", "starts": starts, "frames": frames, "ready": ready] }
    }
    private func captureError(_ message: String) -> NSError { NSError(domain: "AuraScribeCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

/// Read only the microphone-active browser's front window. Never scan history,
/// execute page JavaScript, or inspect another application to guess the call.
private enum BrowserCallReader {
    static let ids: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome",
        "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.brave.Browser", "com.brave.Browser.beta",
        "com.brave.Browser.nightly", "com.microsoft.edgemac", "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition", "app.zen-browser.zen"
    ]
    static let queue = DispatchQueue(label: "com.aurascribe.browser-call", qos: .utility)

    static func read(id: String, automation: Bool) -> [String: String] {
        guard ids.contains(id), let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { return [:] }
        let page = accessibilityPage(app.processIdentifier)
        if page["url"] != nil || !automation { return page }
        // Firefox and Zen expose page information through AX only.
        if id.contains("firefox") || id == "app.zen-browser.zen" { return page }
        let safari = id.hasPrefix("com.apple.Safari")
        let tab = safari ? "current tab" : "active tab"
        let title = safari ? "name" : "title"
        // id is an allowlisted constant; no page/user text enters the script.
        let script = "with timeout of 2 seconds\ntell application id \"\(id)\"\nif (count of windows) is 0 then return \"\"\nreturn (URL of \(tab) of front window) & linefeed & (\(title) of \(tab) of front window)\nend tell\nend timeout"
        let process = Process(); let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return page }
        // Read concurrently so a long title cannot fill the pipe and deadlock.
        let bytes = NSMutableData(); let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            bytes.append(output.fileHandleForReading.readDataToEndOfFile()); finished.signal()
        }
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { process.terminate(); if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        if finished.wait(timeout: .now() + 1) != .success { return page }
        guard !process.isRunning, process.terminationStatus == 0,
              let text = String(data: bytes as Data, encoding: .utf8) else { return page }
        let parts = text.split(separator: "\n", maxSplits: 1).map(String.init)
        guard let first = parts.first, let url = URL(string: first),
              ["https", "http"].contains(url.scheme ?? "") else { return page }
        return ["url": first, "title": parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""]
    }

    static func accessibilityPage(_ pid: pid_t) -> [String: String] {
        guard AXIsProcessTrusted() else { return [:] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        func value(_ node: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
            var result: CFTypeRef?
            return AXUIElementCopyAttributeValue(node, attribute, &result) == .success ? result : nil
        }
        guard let windows = value(app, kAXWindowsAttribute as CFString) as? [AXUIElement], let window = windows.first else { return [:] }
        let windowTitle = value(window, kAXTitleAttribute as CFString) as? String ?? ""
        var nodes: [(AXUIElement, Int)] = [(window, 0)]; var visited = 0
        let deadline = Date().addingTimeInterval(1.5)
        while let (node, depth) = nodes.popLast(), visited < 384, Date() < deadline {
            visited += 1
            AXUIElementSetMessagingTimeout(node, 0.08)
            let role = value(node, kAXRoleAttribute as CFString) as? String ?? ""
            if role == "AXWebArea" {
                let address = value(node, kAXURLAttribute as CFString)
                let url = (address as? URL)?.absoluteString ?? address as? String ?? ""
                if let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme ?? "") {
                    let title = value(node, kAXTitleAttribute as CFString) as? String ?? windowTitle
                    return ["url": url, "title": title.isEmpty ? windowTitle : title]
                }
                // Never traverse the web page's text, fields, or private contents.
                continue
            }
            if depth < 12, let children = value(node, kAXChildrenAttribute as CFString) as? [AXUIElement] {
                nodes.append(contentsOf: children.prefix(64).reversed().map { ($0, depth + 1) })
            }
        }
        return windowTitle.isEmpty ? [:] : ["title": windowTitle]
    }
}
