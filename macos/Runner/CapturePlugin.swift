import Cocoa
import FlutterMacOS
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import Vision
import CoreAudio
import AudioToolbox

final class CapturePlugin: NSObject, FlutterPlugin {
    private let meeting = MeetingRecorder()
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.aurascribe/capture", binaryMessenger: registrar.messenger)
        registrar.addMethodCallDelegate(CapturePlugin(), channel: channel)
    }
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "captureRegion":
            guard let path = call.arguments as? String, CGPreflightScreenCaptureAccess() else {
                result(FlutterError(code: "SCREEN_PERMISSION", message: "Allow Screen & System Audio Recording in System Settings.", details: nil)); return
            }
            NSApp.hide(nil)
            let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-i", "-x", path]
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
                    system: args["system"] as? Bool ?? true, echoCancellation: args["echoCancellation"] as? Bool ?? true, microphoneId: args["microphoneId"] as? String ?? "")
                await MainActor.run { result(nil) }
            } catch { await MainActor.run { result(FlutterError(code: "MEETING_CAPTURE", message: error.localizedDescription, details: nil)) } } }
        case "meetingStop":
            Task { let status = await meeting.stop(); await MainActor.run { result(status) } }
        case "meetingStatus": result(meeting.status())
        case "trash":
            guard let path = call.arguments as? String else { result(nil); return }
            do { try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil); result(nil) }
            catch { result(FlutterError(code: "TRASH", message: error.localizedDescription, details: nil)) }
        default: result(FlutterMethodNotImplemented)
        }
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
    func start(directory: URL, microphone: Bool, system: Bool, echoCancellation: Bool, microphoneId: String) async throws {
        guard !running else { throw captureError("A meeting recording is already active.") }
        guard microphone || system else { throw captureError("Choose microphone or system audio.") }
        if microphone {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            if !allowed { throw captureError("Allow Microphone access in System Settings before recording.") }
        }
        if system && !CGPreflightScreenCaptureAccess() { throw captureError("Allow Screen & System Audio Recording in System Settings, then try again.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        queue.sync { starts = [:]; frames = [:]; failure = nil }
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
        ["running": running, "error": failure ?? "", "starts": starts, "frames": frames]
    } }
    func stop() async -> [String: Any] {
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        if let capture = stream { try? await capture.stopCapture() }; stream = nil
        running = false
        return queue.sync { micFile = nil; systemFile = nil; return ["running": false, "error": failure ?? "", "starts": starts, "frames": frames] }
    }
    private func captureError(_ message: String) -> NSError { NSError(domain: "AuraScribeCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
