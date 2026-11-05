import Cocoa
import FlutterMacOS
import AVFoundation
import CoreAudio
import AudioToolbox

final class VoiceFilterPlugin: NSObject, FlutterPlugin {
    private let processor = VoiceProcessor()
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.aurascribe/voice_filter", binaryMessenger: registrar.messenger)
        registrar.addMethodCallDelegate(VoiceFilterPlugin(), channel: channel)
    }
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "status": result(processor.status())
        case "start":
            let args = call.arguments as? [String: Any] ?? [:]
            Task {
                do { try await processor.start(args); await MainActor.run { result(nil) } }
                catch { await MainActor.run { result(FlutterError(code: "VOICE_FILTER", message: error.localizedDescription, details: nil)) } }
            }
        case "stop": processor.stop(); result(nil)
        case "installer":
            let bundled = Bundle.main.resourceURL!.appendingPathComponent("AuraScribeMicrophone.pkg")
            let local = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".aurascribe/tools/AuraScribeMicrophone.pkg")
            let url = FileManager.default.fileExists(atPath: bundled.path) ? bundled : local
            if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url); result(nil) }
            else { result(FlutterError(code: "INSTALLER", message: "Build the driver installer with tool/build_virtual_microphone.sh.", details: nil)) }
        default: result(FlutterMethodNotImplemented)
        }
    }
}

struct AuraAudioDevice {
    static func resolve(_ uid: String) throws -> AudioDeviceID {
        var value: CFString = uid as CFString
        var device: AudioDeviceID = 0
        var query = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        let status = withUnsafePointer(to: &value) { pointer in
            var bytes = UInt32(MemoryLayout<AudioDeviceID>.size)
            return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &query,
                UInt32(MemoryLayout<CFString>.size), pointer, &bytes, &device)
        }
        guard status == noErr && device != 0 else { throw NSError(domain: "AuraAudio", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Audio device is unavailable: \(uid)"]) }
        return device
    }
    static func setInput(_ engine: AVAudioEngine, uid: String) throws {
        guard !uid.isEmpty else { return }
        var device = try resolve(uid)
        guard let unit = engine.inputNode.audioUnit else { throw NSError(domain: "AuraAudio", code: 2) }
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        if status != noErr { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

private final class VoiceProcessor {
    private let queue = DispatchQueue(label: "com.aurascribe.voice.processing")
    private var capture: AVAudioEngine?, sink: AVAudioEngine?, preview: AVAudioEngine?
    private var sinkPlayer: AVAudioPlayerNode?, previewPlayer: AVAudioPlayerNode?
    private var running = false, generation = 0
    private var level = -90.0, failure = ""
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
    func status() -> [String: Any] {
        let installed = (try? AuraAudioDevice.resolve("com.aurascribe.microphone.sink")) != nil
        return queue.sync { ["running": running, "installed": installed, "levelDb": level, "error": failure] }
    }
    func start(_ args: [String: Any]) async throws {
        stop()
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw NSError(domain: "AuraAudio", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Allow Microphone access in System Settings."]) }
        let previewOnly = args["previewOnly"] as? Bool ?? false
        do {
            let audio = AVAudioEngine()
            try AuraAudioDevice.setInput(audio, uid: args["microphoneId"] as? String ?? "")
            if args["voiceProcessing"] as? Bool ?? true {
                try audio.inputNode.setVoiceProcessingEnabled(true)
                audio.inputNode.isVoiceProcessingAGCEnabled = args["automaticGain"] as? Bool ?? true
            }
            if !previewOnly {
                var device = try AuraAudioDevice.resolve("com.aurascribe.microphone.sink")
                let output = AVAudioEngine(); let player = AVAudioPlayerNode(); output.attach(player)
                guard let unit = output.outputNode.audioUnit else { throw NSError(domain: "AuraAudio", code: 4) }
                let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                    &device, UInt32(MemoryLayout<AudioDeviceID>.size))
                if status != noErr { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
                output.connect(player, to: output.mainMixerNode, format: format)
                try output.start(); player.play(); sink = output; sinkPlayer = player
            }
            if previewOnly || args["monitor"] as? Bool == true {
                let output = AVAudioEngine(); let player = AVAudioPlayerNode(); output.attach(player)
                output.connect(player, to: output.mainMixerNode, format: format)
                try output.start(); player.play(); preview = output; previewPlayer = player
            }
            let inputFormat = audio.inputNode.outputFormat(forBus: 0)
            guard let converter = AVAudioConverter(from: inputFormat, to: format) else { throw NSError(domain: "AuraAudio", code: 5) }
            let gain = Float(args["gain"] as? Double ?? 1), threshold = args["gateDb"] as? Double ?? -55
            let token = generation
            audio.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] input, _ in
                guard let self = self, let copy = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: input.frameLength) else { return }
                copy.frameLength = input.frameLength
                let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input.audioBufferList))
                let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
                for i in 0..<min(source.count, target.count) { if let from = source[i].mData, let to = target[i].mData {
                    memcpy(to, from, min(Int(source[i].mDataByteSize), Int(target[i].mDataByteSize)))
                } }
                self.queue.async {
                    guard token == self.generation, let output = AVAudioPCMBuffer(pcmFormat: self.format,
                        frameCapacity: AVAudioFrameCount(Double(copy.frameLength) * 48000 / inputFormat.sampleRate) + 32) else { return }
                    var supplied = false; var error: NSError?
                    converter.convert(to: output, error: &error) { _, status in
                        if supplied { status.pointee = .noDataNow; return nil }
                        supplied = true; status.pointee = .haveData; return copy
                    }
                    if let error = error { self.failure = error.localizedDescription; return }
                    guard let samples = output.floatChannelData?[0], output.frameLength > 0 else { return }
                    var square = 0.0
                    for i in 0..<Int(output.frameLength) { square += Double(samples[i] * samples[i]) }
                    self.level = 10 * log10(max(0.000000001, square / Double(output.frameLength)))
                    let multiplier: Float = self.level < threshold ? 0 : gain
                    for i in 0..<Int(output.frameLength) { samples[i] = max(-1, min(1, samples[i] * multiplier)) }
                    self.sinkPlayer?.scheduleBuffer(output)
                    self.previewPlayer?.scheduleBuffer(output)
                }
            }
            capture = audio; try audio.start(); running = true
        } catch { stop(); throw error }
    }
    func stop() {
        capture?.stop(); capture?.inputNode.removeTap(onBus: 0); capture = nil
        queue.sync {
            generation += 1; sinkPlayer?.stop(); previewPlayer?.stop()
            sink?.stop(); preview?.stop(); sink = nil; preview = nil
            sinkPlayer = nil; previewPlayer = nil; running = false; level = -90; failure = ""
        }
    }
}
