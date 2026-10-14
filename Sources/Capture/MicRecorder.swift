import AVFoundation
import Foundation

final class MicRecorder {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var isRecording = false

    var startHostTime: UInt64?

    func start(writingTo url: URL) throws {
        guard !isRecording else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)

        input.removeTap(onBus: 0)
        startHostTime = mach_absolute_time()
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let file = self.audioFile else { return }
            try? file.write(from: buffer)
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stop() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        isRecording = false
    }
}

enum MicRecorderError: LocalizedError, Equatable {
    case microphonePermissionDenied

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Brak zgody na mikrofon."
        }
    }
}
