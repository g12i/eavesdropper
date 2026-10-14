import AppKit
import Foundation
import OSLog

/// Requests macOS system audio capture consent (`kTCCServiceAudioCapture`) before process tap.
enum SystemAudioCapturePermission {
    enum Status: String {
        case unknown
        case denied
        case authorized
    }

    private static let logger = Logger(subsystem: "com.tapscribe.app", category: "SystemAudioCapturePermission")

    static func currentStatus() -> Status {
        guard let preflight = preflightSPI else {
            logger.warning("TCC preflight unavailable")
            return .unknown
        }
        let result = preflight("kTCCServiceAudioCapture" as CFString, nil)
        switch result {
        case 0: return .authorized
        case 1: return .denied
        default: return .unknown
        }
    }

    static func ensureAuthorized() throws {
        activateAppIfNeeded()

        let status = currentStatus()
        logger.info("System audio capture TCC status: \(status.rawValue, privacy: .public)")

        switch status {
        case .authorized:
            return
        case .denied:
            throw SystemAudioCaptureError.denied
        case .unknown:
            break
        }

        guard let request = requestSPI else {
            logger.warning("TCC request SPI unavailable — relying on tap creation to prompt")
            return
        }

        let sem = DispatchSemaphore(value: 0)
        var granted = false
        request("kTCCServiceAudioCapture" as CFString, nil) { ok in
            granted = ok
            sem.signal()
        }
        sem.wait()

        if granted {
            return
        }
        throw SystemAudioCaptureError.denied
    }

    private static func activateAppIfNeeded() {
        let activate = { NSApplication.shared.activate(ignoringOtherApps: true) }
        if Thread.isMainThread {
            activate()
        } else {
            DispatchQueue.main.sync(execute: activate)
        }
    }

    private typealias PreflightFunc = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFunc = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    private static let apiHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    }()

    private static let preflightSPI: PreflightFunc? = {
        guard let apiHandle, let sym = dlsym(apiHandle, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(sym, to: PreflightFunc.self)
    }()

    private static let requestSPI: RequestFunc? = {
        guard let apiHandle, let sym = dlsym(apiHandle, "TCCAccessRequest") else { return nil }
        return unsafeBitCast(sym, to: RequestFunc.self)
    }()
}

enum SystemAudioCaptureError: LocalizedError {
    case denied
    case tapFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .denied:
            "Brak zgody na nagrywanie dźwięku systemu. Włącz TapScribe w Ustawienia → Prywatność → Nagrywanie dźwięku systemu."
        case let .tapFailed(code):
            "Nie udało się uruchomić przechwytywania dźwięku systemu (kod \(code))."
        }
    }
}
