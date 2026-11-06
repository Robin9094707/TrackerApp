import Foundation

/// Web Push headers contain named, semicolon-separated parameters. Extra
/// parameters must never become part of an elliptic-curve key or salt.
enum GooglePushHeader {
    static func parameter(_ name: String, in header: String) -> String {
        for part in header.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespaces) == name else { continue }
            return pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return ""
    }
}
