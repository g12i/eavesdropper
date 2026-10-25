import AVFoundation
import AudioToolbox
import Foundation
import OSLog

final class SystemAudioTap {
    private static let logger = Logger(subsystem: "com.tapscribe.app", category: "SystemAudioTap")
    private var processTapID: AudioObjectID = .unknown
    private var aggregateDeviceID: AudioObjectID = .unknown
    private var deviceProcID: AudioDeviceIOProcID?
    private var audioFile: AVAudioFile?
    private var pcmFormat: AVAudioFormat?
    private let queue = DispatchQueue(label: "com.tapscribe.system-audio", qos: .userInitiated)

    var isRunning: Bool { deviceProcID != nil }

    func start(writingTo url: URL) throws {
        guard !isRunning else { return }

        let ownProcessID = try AudioObjectID.translatePIDToProcessObjectID(pid: getpid())

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcessID])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true

        var tapID = AudioObjectID.unknown
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard err == noErr else {
            throw SystemAudioCaptureError.tapFailed(err)
        }
        processTapID = tapID

        let outputDevice = try AudioObjectID.readDefaultSystemOutputDevice()
        let outputUID = try outputDevice.readDeviceUID()
        let aggregateUID = UUID().uuidString

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "TapScribe-\(aggregateUID.prefix(8))",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID],
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                ],
            ],
        ]

        var aggregateID = AudioObjectID.unknown
        err = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID)
        guard err == noErr else {
            try? destroyTapOnly()
            throw CoreAudioError(message: "AudioHardwareCreateAggregateDevice failed: \(err)")
        }
        aggregateDeviceID = aggregateID

        var streamDescription = try Self.captureStreamDescription(
            tapID: tapID,
            aggregateDeviceID: aggregateID
        )
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            try? stop()
            throw CoreAudioError(message: "Failed to create AVAudioFormat from tap")
        }
        pcmFormat = format

        let settings: [String: Any] = [
            AVFormatIDKey: streamDescription.mFormatID,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
        ]
        audioFile = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: format.isInterleaved
        )

        err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue) {
            [weak self] _, inInputData, _, _, _ in
            guard let self, let file = self.audioFile, let format = self.pcmFormat else { return }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil) else {
                return
            }
            do {
                try file.write(from: buffer)
            } catch {
                // IO proc cannot throw; best-effort write
            }
        }
        guard err == noErr, let procID = deviceProcID else {
            try? stop()
            throw CoreAudioError(message: "AudioDeviceCreateIOProcIDWithBlock failed: \(err)")
        }

        err = AudioDeviceStart(aggregateDeviceID, procID)
        guard err == noErr else {
            try? stop()
            throw CoreAudioError(message: "AudioDeviceStart failed: \(err)")
        }
    }

    /// Tears down every resource even if an earlier step fails, so the next `start` is never a silent no-op.
    func stop() throws {
        var firstError: CoreAudioError?
        func check(_ status: OSStatus, _ call: String) {
            if status != noErr, firstError == nil {
                firstError = CoreAudioError(message: "\(call) failed: \(status)")
            }
        }

        if aggregateDeviceID.isValid {
            if let procID = deviceProcID {
                check(AudioDeviceStop(aggregateDeviceID, procID), "AudioDeviceStop")
                check(AudioDeviceDestroyIOProcID(aggregateDeviceID, procID), "AudioDeviceDestroyIOProcID")
            }
            check(AudioHardwareDestroyAggregateDevice(aggregateDeviceID), "AudioHardwareDestroyAggregateDevice")
            aggregateDeviceID = .unknown
        }
        deviceProcID = nil

        if processTapID.isValid {
            check(AudioHardwareDestroyProcessTap(processTapID), "AudioHardwareDestroyProcessTap")
            processTapID = .unknown
        }

        // IO blocks run on `queue`; closing the file there avoids racing an in-flight write.
        queue.sync {
            audioFile = nil
            pcmFormat = nil
        }

        if let firstError {
            throw firstError
        }
    }

    private func destroyTapOnly() throws {
        if processTapID.isValid {
            let err = AudioHardwareDestroyProcessTap(processTapID)
            guard err == noErr else {
                throw CoreAudioError(message: "AudioHardwareDestroyProcessTap failed: \(err)")
            }
            processTapID = .unknown
        }
    }

    /// Tap ASBD can report a different rate than the aggregate IO proc (e.g. 48 kHz vs 44.1 kHz on built-in output).
    /// File metadata and PCM buffers must follow the aggregate device's input stream clock.
    private static func captureStreamDescription(
        tapID: AudioObjectID,
        aggregateDeviceID: AudioObjectID
    ) throws -> AudioStreamBasicDescription {
        var tapDescription = try tapID.readAudioTapStreamBasicDescription()
        let tapRate = tapDescription.mSampleRate

        let aggregateInput = try aggregateDeviceID.readDeviceStreamBasicDescription(
            scope: kAudioObjectPropertyScopeInput
        )
        if aggregateInput.mSampleRate > 0, aggregateInput.mChannelsPerFrame > 0 {
            if abs(aggregateInput.mSampleRate - tapRate) > 1 {
                logger.info(
                    "Using aggregate input rate \(aggregateInput.mSampleRate, privacy: .public) Hz (tap reported \(tapRate, privacy: .public) Hz)"
                )
            }
            return aggregateInput
        }

        let nominalRate = try aggregateDeviceID.readNominalSampleRate()
        if nominalRate > 0, abs(nominalRate - tapRate) > 1 {
            logger.info(
                "Using aggregate nominal rate \(nominalRate, privacy: .public) Hz (tap reported \(tapRate, privacy: .public) Hz)"
            )
            tapDescription.mSampleRate = nominalRate
        }

        return tapDescription
    }

    deinit {
        try? stop()
    }
}
