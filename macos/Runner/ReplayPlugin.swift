import Cocoa
import FlutterMacOS
import ScreenCaptureKit
import AVFoundation

/// Opt-in rolling screen-only capture. Encoded segments bound memory and disk use.
final class ReplayPlugin: NSObject, FlutterPlugin, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label: "com.aurascribe.replay")
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var startTime: CMTime?
    private var directory: URL?
    private var segments = [URL]()
    private let finishes = DispatchGroup()
    private var failure: String?
    private var width = 0, height = 0
    private var segmentNumber = 0

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = ReplayPlugin()
        registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(name: "com.aurascribe/replay", binaryMessenger: registrar.messenger))
    }
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task {
            do {
                switch call.method {
                case "start":
                    guard let path = call.arguments as? String else { throw problem("Missing capture directory") }
                    try await start(URL(fileURLWithPath: path)); await MainActor.run { result(nil) }
                case "stop":
                    await stop(); await MainActor.run { result(nil) }
                case "save":
                    guard let path = call.arguments as? String else { throw problem("Missing destination") }
                    try await save(URL(fileURLWithPath: path)); await MainActor.run { result(nil) }
                default: await MainActor.run { result(FlutterMethodNotImplemented) }
                }
            } catch { await MainActor.run { result(FlutterError(code: "REPLAY", message: error.localizedDescription, details: nil)) } }
        }
    }
    private func problem(_ text: String) -> NSError { NSError(domain: "AuraScribeReplay", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private func start(_ folder: URL) async throws {
        guard stream == nil else { throw problem("Replay capture is already running") }
        guard CGPreflightScreenCaptureAccess() else { throw problem("Allow screen recording before enabling replay") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if segments.isEmpty {
            for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where file.pathExtension == "mov" { try FileManager.default.removeItem(at: file) }
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw problem("No screen available") }
        width = display.width; height = display.height
        queue.sync { directory = folder; failure = nil }
        let config = SCStreamConfiguration()
        config.width = width; config.height = height; config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3; config.showsCursor = true; config.capturesAudio = false
        let capture = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
        try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await capture.startCapture(); stream = capture
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sample.isValid, CMSampleBufferGetImageBuffer(sample) != nil, failure == nil else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
        if let start = startTime, CMTimeGetSeconds(timestamp - start) >= 5 { finishSegment() }
        do {
            if writer == nil {
                guard let folder = directory else { return }
                segmentNumber += 1
                let url = folder.appendingPathComponent(String(format: "%08d-", segmentNumber) + UUID().uuidString + ".mov")
                let next = try AVAssetWriter(outputURL: url, fileType: .mov)
                let track = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: width, AVVideoHeightKey: height])
                track.expectsMediaDataInRealTime = true
                guard next.canAdd(track) else { throw problem("HEVC screen recording is unavailable") }
                next.add(track)
                guard next.startWriting() else { throw next.error ?? problem("Could not start replay encoder") }
                next.startSession(atSourceTime: timestamp)
                writer = next; input = track; startTime = timestamp
            }
            if let track = input, track.isReadyForMoreMediaData, !track.append(sample) { throw writer?.error ?? problem("Screen encoding failed") }
        } catch { failure = error.localizedDescription }
    }
    private func finishSegment() {
        guard let old = writer else { return }
        input?.markAsFinished(); writer = nil; input = nil; startTime = nil
        finishes.enter()
        old.finishWriting { self.queue.async {
            if old.status == .completed { self.segments.append(old.outputURL); self.segments.sort { $0.lastPathComponent < $1.lastPathComponent } }
            else { self.failure = old.error?.localizedDescription ?? "Replay segment could not finish" }
            while self.segments.count > 4 { try? FileManager.default.removeItem(at: self.segments.removeFirst()) }
            self.finishes.leave()
        } }
    }
    private func stopCapture() async {
        if let capture = stream { try? await capture.stopCapture() }; stream = nil
        queue.sync { finishSegment() }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finishes.notify(queue: .global()) { continuation.resume() }
        }
    }
    private func stop() async {
        await stopCapture()
        queue.sync { for url in segments { try? FileManager.default.removeItem(at: url) }; segments = []; directory = nil }
    }
    private func save(_ destination: URL) async throws {
        guard stream != nil, let folder = directory else { throw problem("Enable replay first") }
        await stopCapture()
        let urls = queue.sync { segments }
        do {
            if let error = queue.sync(execute: { failure }) { throw problem(error) }
            let composition = AVMutableComposition()
            guard let output = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw problem("Could not create replay") }
            var assets = [(AVURLAsset, CMTime, AVAssetTrack)]()
            for url in urls {
                let asset = AVURLAsset(url: url)
                let duration = try await asset.load(.duration)
                if let track = try await asset.loadTracks(withMediaType: .video).first, duration.isNumeric, duration > .zero { assets.append((asset, duration, track)) }
            }
            let total = assets.reduce(0.0) { $0 + CMTimeGetSeconds($1.1) }
            var skip = max(0, total - 15), cursor = CMTime.zero
            for (_, duration, track) in assets {
                let seconds = CMTimeGetSeconds(duration)
                if skip >= seconds { skip -= seconds; continue }
                let from = CMTime(seconds: skip, preferredTimescale: 600)
                let length = duration - from
                try output.insertTimeRange(CMTimeRange(start: from, duration: length), of: track, at: cursor)
                cursor = cursor + length; skip = 0
            }
            guard cursor > .zero, let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { throw problem("No replay frames yet") }
            export.outputURL = destination; export.outputFileType = .mov
            await export.export()
            guard export.status == .completed else { throw export.error ?? problem("Replay export failed") }
            try await start(folder)
        } catch { try? await start(folder); throw error }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { queue.async { self.failure = error.localizedDescription } }
}

/// Nonactivating, draggable meeting controls. Movement does not steal typing focus.
final class MeetingCapsule: NSObject {
    private var panel: NSPanel?
    var onStop: (() -> Void)?
    func show(_ text: String, stopLabel: String = "Stop") {
        if panel == nil {
            let value = DictationIndicatorPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 58), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            value.isMovableByWindowBackground = true; value.level = .floating
            value.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            value.isReleasedWhenClosed = false; value.backgroundColor = .windowBackgroundColor
            let label = NSTextField(labelWithString: ""); label.tag = 1; label.frame = NSRect(x: 14, y: 18, width: 190, height: 22)
            let stop = NSButton(title: stopLabel, target: self, action: #selector(stopPressed)); stop.tag = 2; stop.frame = NSRect(x: 218, y: 12, width: 70, height: 32)
            value.contentView?.addSubview(label); value.contentView?.addSubview(stop)
            if !value.setFrameUsingName("AuraMeetingCapsule"), let screen = NSScreen.main { value.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 320, y: screen.visibleFrame.maxY - 80)) }
            value.setFrameAutosaveName("AuraMeetingCapsule")
            panel = value
        }
        (panel?.contentView?.viewWithTag(1) as? NSTextField)?.stringValue = text
        (panel?.contentView?.viewWithTag(2) as? NSButton)?.title = stopLabel
        panel?.orderFrontRegardless()
    }
    @objc private func stopPressed() { onStop?() }
    func hide() { panel?.saveFrame(usingName: "AuraMeetingCapsule"); panel?.orderOut(nil) }
}
