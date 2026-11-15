import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var pendingStory: String?
  override func application(_ application: NSApplication, open urls: [URL]) {
    guard let url = urls.first(where: { $0.scheme == "aurascribe" && $0.host == "story" }) else { return }
    pendingStory = url.absoluteString
    lifecycleChannel?.invokeMethod("openStory", arguments: url.absoluteString) { [weak self] result in
      if result as? Bool == true { self?.pendingStory = nil }
    }
  }
  var lifecycleChannel: FlutterMethodChannel?
  var quitClosesWindow = false
  var allowTermination = false
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    lifecycleChannel?.invokeMethod("showSettings", arguments: nil)
    return false
  }
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if quitClosesWindow && !allowTermination {
      lifecycleChannel?.invokeMethod("closeSettings", arguments: nil)
      return .terminateCancel
    }
    return .terminateNow
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Keep app running when the settings window is closed (menu bar app)
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
