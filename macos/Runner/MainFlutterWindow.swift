import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  var isDictationPanel = false
  override var canBecomeKey: Bool { !isDictationPanel }
  override var canBecomeMain: Bool { !isDictationPanel }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let lifecycle = FlutterMethodChannel(name: "com.aurascribe/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    (NSApp.delegate as? AppDelegate)?.lifecycleChannel = lifecycle
    lifecycle.setMethodCallHandler { call, result in
      if call.method == "configure" { (NSApp.delegate as? AppDelegate)?.quitClosesWindow = call.arguments as? Bool ?? false; result(nil) }
      else if call.method == "takePendingStory" {
        let app = NSApp.delegate as? AppDelegate
        result(app?.pendingStory); app?.pendingStory = nil
      }
      else if call.method == "allowTermination" { (NSApp.delegate as? AppDelegate)?.allowTermination = true; result(nil) }
      else { result(FlutterMethodNotImplemented) }
    }
    RegisterGeneratedPlugins(registry: flutterViewController)
    AccessibilityPlugin.register(with: flutterViewController.registrar(forPlugin: "AccessibilityPlugin"))
    UpdatePlugin.register(with: flutterViewController.registrar(forPlugin: "UpdatePlugin"))
    VoiceFilterPlugin.register(with: flutterViewController.registrar(forPlugin: "VoiceFilterPlugin"))
    AppleSpeechPlugin.register(with: flutterViewController.registrar(forPlugin: "AppleSpeechPlugin"))
    ReplayPlugin.register(with: flutterViewController.registrar(forPlugin: "ReplayPlugin"))
    CapturePlugin.register(with: flutterViewController.registrar(forPlugin: "CapturePlugin"))
    HotkeyPlugin.register(with: flutterViewController.registrar(forPlugin: "HotkeyPlugin"))

    super.awakeFromNib()
  }
}
