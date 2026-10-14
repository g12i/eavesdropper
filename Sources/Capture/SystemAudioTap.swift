import AVFoundation
import AudioToolbox
import Foundation

final class SystemAudioTap {
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

        var streamDescription = try tapID.readAudioTapStreamBasicDescription()
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            try stop()
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
            try stop()
            throw CoreAudioError(message: "AudioDeviceCreateIOProcIDWithBlock failed: \(err)")
        }

        err = AudioDeviceStart(aggregateDeviceID, procID)
        guard err == noErr else {
            try stop()
            throw CoreAudioError(message: "AudioDeviceStart failed: \(err)")
        }
    }

    func stop() throws {
        defer {
            audioFile = nil
            pcmFormat = nil
        }

        if aggregateDeviceID.isValid, let procID = deviceProcID {
            var err = AudioDeviceStop(aggregateDeviceID, procID)
            if err != noErr {
                throw CoreAudioError(message: "AudioDeviceStop failed: \(err)")
            }
            err = AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            if err != noErr {
                throw CoreAudioError(message: "AudioDeviceDestroyIOProcID failed: \(err)")
            }
            deviceProcID = nil

            err = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            if err != noErr {
                throw CoreAudioError(message: "AudioHardwareDestroyAggregateDevice failed: \(err)")
            }
            aggregateDeviceID = .unknown
        }

        if processTapID.isValid {
            let err = AudioHardwareDestroyProcessTap(processTapID)
            if err != noErr {
                throw CoreAudioError(message: "AudioHardwareDestroyProcessTap failed: \(err)")
            }
            processTapID = .unknown
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

    deinit {
        try? stop()
    }
}
