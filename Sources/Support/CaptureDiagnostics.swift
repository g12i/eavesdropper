import Foundation
import OSLog

enum CaptureDiagnostics {
    private static let logger = Logger(subsystem: "com.tapscribe.app", category: "CaptureDiagnostics")

    static func printReport() async {
        let bundleID = Bundle.main.bundleIdentifier ?? "(unknown)"
        let appPath = Bundle.main.bundleURL.path
        let signing = signingSummary(for: appPath)

        print("TapScribe capture probe")
        print("  bundle_id: \(bundleID)")
        print("  app_path: \(appPath)")
        print("  codesign: \(signing)")
        print("  note: TCC entries are per bundle ID + stable code signature (use Apple Development, not adhoc)")

        let systemStatus = SystemAudioCapturePermission.currentStatus()
        print("  system_audio_tcc: \(systemStatus.rawValue)")

        do {
            try await SystemAudioCapturePermission.ensureAuthorized()
            print("  system_audio_request: ok")
        } catch {
            print("  system_audio_request: FAIL — \(error.localizedDescription)")
            logger.error("System audio request failed: \(error.localizedDescription, privacy: .public)")
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("tapscribe-probe-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let session = RecordingSession()
            try await session.start(in: tempDir)
            try session.stop()
            let systemPath = tempDir.appendingPathComponent("system.caf")
            let attrs = try? FileManager.default.attributesOfItem(atPath: systemPath.path)
            let bytes = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            print("  tap_session: ok (system.caf \(bytes) bytes)")
            try? FileManager.default.removeItem(at: tempDir)
        } catch {
            print("  tap_session: FAIL — \(error.localizedDescription)")
            logger.error("Tap session probe failed: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private static func signingSummary(for appPath: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", appPath]

        let pipe = Pipe()
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            if text.contains("Signature=adhoc") || text.contains("not signed") {
                return "unsigned/adhoc (TCC prompts may not persist between builds)"
            }
            if let line = text.split(separator: "\n").first(where: { $0.contains("Authority=") }) {
                return String(line).trimmingCharacters(in: .whitespaces)
            }
            return text.split(separator: "\n").prefix(3).joined(separator: "; ")
        } catch {
            return "codesign failed: \(error.localizedDescription)"
        }
    }
}
