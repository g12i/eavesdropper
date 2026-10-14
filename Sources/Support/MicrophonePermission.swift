import AppKit
import AVFAudio
import AVFoundation
import Foundation

enum MicrophonePermission {
    static func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func ensureAuthorized() throws {
        activateAppIfNeeded()

        switch authorizationStatus() {
        case .authorized:
            return
        case .denied, .restricted:
            throw MicRecorderError.microphonePermissionDenied
        case .notDetermined:
            break
        @unknown default:
            break
        }

        if #available(macOS 14.0, *) {
            let sem = DispatchSemaphore(value: 0)
            var allowed = false
            AVAudioApplication.requestRecordPermission { ok in
                allowed = ok
                sem.signal()
            }
            sem.wait()
            if allowed { return }
            throw MicRecorderError.microphonePermissionDenied
        }

        let sem = DispatchSemaphore(value: 0)
        var allowed = false
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            allowed = ok
            sem.signal()
        }
        sem.wait()
        if allowed { return }
        throw MicRecorderError.microphonePermissionDenied
    }

    private static func activateAppIfNeeded() {
        let activate = { NSApplication.shared.activate(ignoringOtherApps: true) }
        if Thread.isMainThread {
            activate()
        } else {
            DispatchQueue.main.sync(execute: activate)
        }
    }
}
