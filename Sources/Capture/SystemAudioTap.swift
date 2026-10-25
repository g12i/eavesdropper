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
    private var inputPCMFormat: AVAudioFormat?
    private var outputPCMFormat: AVAudioFormat?
    private var sampleRateConverter: AVAudioConverter?
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
        let captureSampleRate = try Self.resolveDefaultOutputCaptureSampleRate(device: outputDevice)
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

        do {
            try aggregateID.setNominalSampleRate(captureSampleRate)
        } catch {
            Self.logger.warning("Could not set aggregate nominal rate to \(captureSampleRate, privacy: .public) Hz: \(String(describing: error), privacy: .public)")
        }

        var inputStreamDescription = try Self.resolveInputStreamDescription(
            tapID: tapID,
            aggregateDeviceID: aggregateID
        )
        guard let inputFormat = AVAudioFormat(streamDescription: &inputStreamDescription) else {
            try? stop()
            throw CoreAudioError(message: "Failed to create AVAudioFormat from tap input")
        }
        inputPCMFormat = inputFormat

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: captureSampleRate,
            channels: inputFormat.channelCount,
            interleaved: inputFormat.isInterleaved
        ) else {
            try? stop()
            throw CoreAudioError(message: "Failed to create output PCM format at \(captureSampleRate) Hz")
        }
        outputPCMFormat = outputFormat

        if abs(inputFormat.sampleRate - captureSampleRate) > 1 {
            Self.logger.info(
                "Resampling tap IO \(inputFormat.sampleRate, privacy: .public) Hz → output device \(captureSampleRate, privacy: .public) Hz"
            )
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                try? stop()
                throw CoreAudioError(message: "Failed to create AVAudioConverter")
            }
            sampleRateConverter = converter
        } else {
            sampleRateConverter = nil
        }

        let settings: [String: Any] = [
            AVFormatIDKey: inputStreamDescription.mFormatID,
            AVSampleRateKey: captureSampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
        ]
        audioFile = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: inputFormat.isInterleaved
        )

        err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue) {
            [weak self] _, inInputData, _, _, _ in
            guard let self, let file = self.audioFile, let inputFormat = self.inputPCMFormat else { return }
            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, bufferListNoCopy: inInputData, deallocator: nil) else {
                return
            }
            do {
                if let converter = self.sampleRateConverter, let outputFormat = self.outputPCMFormat {
                    try self.writeConverted(from: inputBuffer, converter: converter, outputFormat: outputFormat, to: file)
                } else {
                    try file.write(from: inputBuffer)
                }
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

    private func writeConverted(
        from inputBuffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat,
        to file: AVAudioFile
    ) throws {
        let ratio = outputFormat.sampleRate / converter.inputFormat.sampleRate
        let outCapacity = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio)) + 32
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outCapacity) else {
            return
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if suppliedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }
        if status == .error {
            throw conversionError ?? CoreAudioError(message: "AVAudioConverter failed")
        }
        guard outputBuffer.frameLength > 0 else { return }
        try file.write(from: outputBuffer)
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
            inputPCMFormat = nil
            outputPCMFormat = nil
            sampleRateConverter = nil
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

    /// Default output device clock — CAF metadata should match what listeners hear on that device.
    private static func resolveDefaultOutputCaptureSampleRate(device: AudioObjectID) throws -> Double {
        let nominal = try device.readNominalSampleRate()
        let outputStream = try device.readDeviceStreamBasicDescription(scope: kAudioObjectPropertyScopeOutput)
        let streamRate = outputStream.mSampleRate

        if streamRate > 0, nominal > 0, abs(streamRate - nominal) > 1 {
            Self.logger.info(
                "Default output stream \(streamRate, privacy: .public) Hz vs nominal \(nominal, privacy: .public) Hz; using stream rate for capture"
            )
            return streamRate
        }
        if streamRate > 0 { return streamRate }
        if nominal > 0 { return nominal }
        throw CoreAudioError(message: "Could not read default output device sample rate")
    }

    /// Format of PCM delivered by the aggregate IO proc (may differ from default output rate).
    private static func resolveInputStreamDescription(
        tapID: AudioObjectID,
        aggregateDeviceID: AudioObjectID
    ) throws -> AudioStreamBasicDescription {
        let aggregateInput = try aggregateDeviceID.readDeviceStreamBasicDescription(scope: kAudioObjectPropertyScopeInput)
        if aggregateInput.mSampleRate > 0, aggregateInput.mChannelsPerFrame > 0 {
            return aggregateInput
        }

        var tapDescription = try tapID.readAudioTapStreamBasicDescription()
        guard tapDescription.mSampleRate > 0, tapDescription.mChannelsPerFrame > 0 else {
            throw CoreAudioError(message: "Tap returned invalid stream format")
        }
        return tapDescription
    }

    deinit {
        try? stop()
    }
}
