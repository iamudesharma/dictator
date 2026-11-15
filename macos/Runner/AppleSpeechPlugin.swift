import Cocoa
import FlutterMacOS
import Speech

final class AppleSpeechPlugin: NSObject, FlutterPlugin {
    private var task: SFSpeechRecognitionTask?
    private var pending: FlutterResult?
    private var timeout: DispatchWorkItem?
    static func register(with registrar: FlutterPluginRegistrar) {
        registrar.addMethodCallDelegate(AppleSpeechPlugin(), channel: FlutterMethodChannel(name: "com.aurascribe/apple_speech", binaryMessenger: registrar.messenger))
    }
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "cancel" { finish(error: "Recognition cancelled"); result(nil); return }
        guard ["prepare", "transcribe"].contains(call.method) else { result(FlutterMethodNotImplemented); return }
        guard pending == nil else { result(FlutterError(code: "BUSY", message: "Apple Speech is busy", details: nil)); return }
        let args = call.arguments as? [String: Any] ?? [:]
        let language = args["language"] as? String ?? "en"
        let locale = language == "auto" ? Locale.current : Locale(identifier: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
            result(FlutterError(code: "OFFLINE_UNAVAILABLE", message: "Apple on-device speech is unavailable for this language. Choose an installed language or a project-local speech model.", details: nil)); return
        }
        SFSpeechRecognizer.requestAuthorization { authorization in DispatchQueue.main.async {
            guard authorization == .authorized else { result(FlutterError(code: "SPEECH_PERMISSION", message: "Allow Speech Recognition in System Settings", details: nil)); return }
            if call.method == "prepare" { result(nil); return }
            guard self.pending == nil else { result(FlutterError(code: "BUSY", message: "Apple Speech is busy", details: nil)); return }
            guard let path = args["path"] as? String else { result(FlutterError(code: "AUDIO", message: "Missing audio path", details: nil)); return }
            let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: path))
            request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = false
            self.pending = result
            self.task = recognizer.recognitionTask(with: request) { value, error in DispatchQueue.main.async {
                if let value = value, value.isFinal { self.finish(value: args["timed"] as? Bool == true ? ["text": value.bestTranscription.formattedString, "words": value.bestTranscription.segments.map { ["start": $0.timestamp, "end": $0.timestamp + $0.duration, "text": $0.substring] }] : value.bestTranscription.formattedString) }
                else if let error = error { self.finish(error: error.localizedDescription) }
            } }
            let timeout = DispatchWorkItem { self.finish(error: "Apple Speech timed out") }
            self.timeout = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: timeout)
        } }
    }
    private func finish(value: Any? = nil, error: String? = nil) {
        let callback = pending; pending = nil
        timeout?.cancel(); timeout = nil; task?.cancel(); task = nil
        if let error = error { callback?(FlutterError(code: "APPLE_SPEECH", message: error, details: nil)) }
        else { callback?(value ?? "") }
    }
}
