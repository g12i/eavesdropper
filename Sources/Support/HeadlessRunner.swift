import Foundation

enum HeadlessRunner {
    static func runIfNeeded() async -> Bool {
        let args = CommandLine.arguments
        guard args.contains("--headless") || args.contains("--transcribe") || args.contains("--probe-capture") else {
            return false
        }

        if args.contains("--probe-capture") {
            await CaptureDiagnostics.printReport()
            exit(0)
        }

        if let transcribeIndex = args.firstIndex(of: "--transcribe"), transcribeIndex + 1 < args.count {
            let path = URL(fileURLWithPath: args[transcribeIndex + 1])
            
            let languageArg = args.firstIndex(of: "--language").flatMap { i in
                i + 1 < args.count ? args[i + 1] : nil
            }
            let language = languageArg.flatMap { TranscriptionLanguage(rawValue: $0) } ?? .polish
            
            do {
                let decodeOptions = Transcriber.decodingOptions(for: language)
                let whisperKit = try await Transcriber.makeWhisperKit()
                let segments = try await Transcriber.transcribeFile(
                    path,
                    whisperKit: whisperKit,
                    decodeOptions: decodeOptions
                )
                
                for segment in segments {
                    print(segment.text)
                }
                
                exit(0)
            } catch {
                fputs("Transcription failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        guard args.contains("--headless") else {
            fputs("Usage: --headless --seconds N --out <dir>\n", stderr)
            exit(2)
        }

        guard let seconds = parseInt(flag: "--seconds", in: args),
              let outIndex = args.firstIndex(of: "--out"), outIndex + 1 < args.count
        else {
            fputs("Usage: --headless --seconds N --out <dir>\n", stderr)
            exit(2)
        }

        let outDir = URL(fileURLWithPath: args[outIndex + 1])
        let session = RecordingSession()

        do {
            try await session.start(in: outDir)
            try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            try session.stop()
            exit(0)
        } catch {
            fputs("Headless recording failed: \(error.localizedDescription)\n", stderr)
            try? session.stop()
            exit(1)
        }
    }

    private static func parseInt(flag: String, in args: [String]) -> Int? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return Int(args[index + 1])
    }
}
