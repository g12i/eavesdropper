import SwiftUI

@main
enum TapScribeMain {
    static func main() {
        if CommandLine.arguments.contains("--headless") || CommandLine.arguments.contains("--transcribe") {
            let group = DispatchGroup()
            group.enter()
            Task {
                _ = await HeadlessRunner.runIfNeeded()
                group.leave()
            }
            group.wait()
            exit(2)
        }
        TapScribeApp.main()
    }
}

struct TapScribeApp: App {
    @State private var isRecording = false
    @State private var session = RecordingSession()
    @State private var recordMicrophone = true
    @State private var status = "Gotowy"

    var body: some Scene {
        MenuBarExtra("TapScribe", systemImage: isRecording ? "record.circle.fill" : "waveform") {
            Button(isRecording ? "Stop nagrywania" : "Start nagrywania") {
                Task { await toggleRecording() }
            }
            Toggle("Nagrywaj mikrofon", isOn: $recordMicrophone)
                .disabled(isRecording)
            Text(status)
                .font(.caption)
            Button("Zakończ") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }

    @MainActor
    private func toggleRecording() async {
        if isRecording {
            do {
                try session.stop()
                status = "Transkrybuję…"
                if let dir = session.outputDirectory {
                    try await HeadlessRunner.transcribeSession(at: dir)
                    status = "Transkrypt gotowy"
                } else {
                    status = "Gotowy"
                }
            } catch {
                status = "Błąd: \(error.localizedDescription)"
            }
            isRecording = false
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = formatter.string(from: Date())
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Recordings/\(name)", isDirectory: true)

        do {
            try session.start(in: dir, recordMicrophone: recordMicrophone)
            isRecording = true
            status = "Nagrywanie…"
        } catch {
            status = "Błąd startu: \(error.localizedDescription)"
        }
    }
}
