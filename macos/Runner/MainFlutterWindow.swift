import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    AccessibilityPlugin.register(with: flutterViewController.registrar(forPlugin: "AccessibilityPlugin"))
    HotkeyPlugin.register(with: flutterViewController.registrar(forPlugin: "HotkeyPlugin"))

    super.awakeFromNib()
  }
}
