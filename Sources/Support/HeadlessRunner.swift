import Foundation

enum HeadlessRunner {
    static func runIfNeeded() async -> Bool {
        let args = CommandLine.arguments
        guard args.contains("--headless") || args.contains("--transcribe") || args.contains("--probe-capture") else {
            return false
        }

        if args.contains("--probe-capture") {
            let includeMic = !args.contains("--no-mic")
            CaptureDiagnostics.printReport(includeMicrophone: includeMic)
            exit(0)
        }

        if let transcribeIndex = args.firstIndex(of: "--transcribe"), transcribeIndex + 1 < args.count {
            let path = URL(fileURLWithPath: args[transcribeIndex + 1])
            do {
                let segments = try await Transcriber.transcribe(path: path, speaker: .others)
                for segment in segments {
                    print(segment.text)
                }
                exit(0)
            } catch {
                fputs("Transcription failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        guard let seconds = parseInt(flag: "--seconds", in: args),
              let outIndex = args.firstIndex(of: "--out"), outIndex + 1 < args.count
        else {
            fputs("Usage: --headless --seconds N --out <dir> [--no-mic]\n", stderr)
            exit(2)
        }

        let outDir = URL(fileURLWithPath: args[outIndex + 1])
        let recordMic = !args.contains("--no-mic")
        let session = RecordingSession()

        do {
            try session.start(in: outDir, recordMicrophone: recordMic)
            try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            try session.stop()
            exit(0)
        } catch {
            fputs("Headless recording failed: \(error.localizedDescription)\n", stderr)
            try? session.stop()
            exit(1)
        }
    }

    static func transcribeSession(at directory: URL) async throws {
        try await TranscriptionService.transcribeSession(at: directory)
    }

    private static func parseInt(flag: String, in args: [String]) -> Int? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return Int(args[index + 1])
    }
}
