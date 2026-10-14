import Foundation

extension String: @retroactive Error {}

struct CoreAudioError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension String {
    func asCoreAudioError() -> CoreAudioError {
        CoreAudioError(message: self)
    }
}
