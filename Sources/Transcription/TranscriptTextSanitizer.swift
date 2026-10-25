import Foundation

enum TranscriptTextSanitizer {
    /// Removes Whisper / WhisperKit special tokens (e.g. `<|startoftranscript|>`, `<|pl|>`, timestamp markers) from decoded text.
    static func clean(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: "<\\|[^|>]+\\|>", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        if let whitespace = try? NSRegularExpression(pattern: "\\s+", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = whitespace.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
