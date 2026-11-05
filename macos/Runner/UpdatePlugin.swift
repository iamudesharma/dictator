import Cocoa
import FlutterMacOS
import Security

final class UpdatePlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.aurascribe/updates", binaryMessenger: registrar.messenger)
        registrar.addMethodCallDelegate(UpdatePlugin(), channel: channel)
    }
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "version": result(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
        case "install":
            guard let args = call.arguments as? [String:String], let dmg = args["dmg"], let work = args["workingDirectory"] else { result(nil); return }
            DispatchQueue.global(qos: .userInitiated).async {
                do { try self.install(dmg: URL(fileURLWithPath: dmg), work: URL(fileURLWithPath: work))
                    DispatchQueue.main.async { result(nil); NSApp.terminate(nil) }
                } catch { DispatchQueue.main.async { result(FlutterError(code: "UPDATE_INSTALL", message: error.localizedDescription, details: nil)) } }
            }
        default: result(FlutterMethodNotImplemented)
        }
    }
    private func failure(_ text: String) -> NSError { NSError(domain: "AuraScribeUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey:text]) }
    private func command(_ executable: String, _ args: [String]) throws -> Data {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = args; process.standardOutput = output
        try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        if process.terminationStatus != 0 { throw failure("Update verification failed while running \(URL(fileURLWithPath: executable).lastPathComponent).") }
        return data
    }
    private func signingTeam(_ url: URL) throws -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code = code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), nil) == errSecSuccess else { throw failure("The update has an invalid code signature.") }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String:Any])?[kSecCodeInfoTeamIdentifier as String] as? String else {
            throw failure("Automatic installation requires a Developer ID signed build. This development build can check and download updates; install release builds manually.")
        }
        return team
    }
    private func install(dmg: URL, work: URL) throws {
        let installed = Bundle.main.bundleURL, team = try signingTeam(Bundle.main.bundleURL)
        guard FileManager.default.isWritableFile(atPath: installed.deletingLastPathComponent().path) else {
            throw failure("The app directory requires administrator access. Open the downloaded DMG and install the update manually.")
        }
        let mount = work.appendingPathComponent("mounted-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        _ = try command("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, dmg.path])
        defer { _ = try? command("/usr/bin/hdiutil", ["detach", mount.path]); try? FileManager.default.removeItem(at: mount) }
        let source = mount.appendingPathComponent("AuraScribe.app")
        guard let bundle = Bundle(url: source), bundle.bundleIdentifier == Bundle.main.bundleIdentifier else { throw failure("This update belongs to a different application.") }
        guard try signingTeam(source) == team else { throw failure("The update signing team does not match this app.") }
        _ = try command("/usr/sbin/spctl", ["--assess", "--type", "execute", source.path])
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let next = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard next.compare(current, options: .numeric) == .orderedDescending else { throw failure("The update is not newer than this app.") }
        let staged = installed.deletingLastPathComponent().appendingPathComponent(".AuraScribe-update-\(UUID().uuidString).app")
        try FileManager.default.copyItem(at: source, to: staged)
        guard try signingTeam(staged) == team else { throw failure("Staged update signature failed verification.") }
        let script = work.appendingPathComponent("install-update.sh")
        let text = """
        #!/bin/bash
        set -euo pipefail
        staged="$1"; destination="$2"; pid="$3"
        for attempt in {1..120}; do
          if ! kill -0 "$pid" 2>/dev/null; then break; fi
          sleep 0.5
        done
        if kill -0 "$pid" 2>/dev/null; then exit 1; fi
        backup="${destination}.previous-$(date +%s)"
        mv "$destination" "$backup"
        if ! mv "$staged" "$destination"; then mv "$backup" "$destination"; exit 1; fi
        /usr/bin/open "$destination"
        """
        try text.write(to: script, atomically: true, encoding: .utf8)
        let helper = Process(); helper.executableURL = URL(fileURLWithPath: "/bin/bash")
        helper.arguments = [script.path, staged.path, installed.path, String(ProcessInfo.processInfo.processIdentifier)]
        try helper.run()
    }
}
