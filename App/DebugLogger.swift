import Foundation
import Observation

@MainActor
@Observable
final class DebugLogger {
    static let shared = DebugLogger()
    private(set) var entries: [String] = []
    private let formatter = ISO8601DateFormatter()

    func log(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)"
        entries.insert(line, at: 0)
        entries = Array(entries.prefix(300))
        #if DEBUG
        print(line)
        #endif
    }

    func clear() { entries.removeAll() }
}
