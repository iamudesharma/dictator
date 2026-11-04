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

    RegisterGeneratedPlugins(registry: flutterViewController)
    AccessibilityPlugin.register(with: flutterViewController.registrar(forPlugin: "AccessibilityPlugin"))
    UpdatePlugin.register(with: flutterViewController.registrar(forPlugin: "UpdatePlugin"))
    VoiceFilterPlugin.register(with: flutterViewController.registrar(forPlugin: "VoiceFilterPlugin"))
    CapturePlugin.register(with: flutterViewController.registrar(forPlugin: "CapturePlugin"))
    HotkeyPlugin.register(with: flutterViewController.registrar(forPlugin: "HotkeyPlugin"))

    super.awakeFromNib()
  }
}
