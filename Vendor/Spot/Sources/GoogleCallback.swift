import Foundation

// A callback operation may finish, fail, time out or be cancelled. Only the first result wins.
final class GoogleOneShot<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }
    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result; let continuation = self.continuation; self.continuation = nil
        lock.unlock(); continuation?.resume(with: result)
    }
}
func googleCallback<Value>(seconds: Double = 30, start: (@escaping (Result<Value, Error>) -> Void) -> Void) async throws -> Value {
    let gate = GoogleOneShot<Value>()
    return try await withTaskCancellationHandler(operation: {
        try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { gate.finish(.failure(URLError(.timedOut))) }
            start { gate.finish($0) }
        }
    }, onCancel: { gate.finish(.failure(CancellationError())) })
}
func googleError(_ message: String, code: Int = 1) -> NSError { NSError(domain: "RJGoogle", code: code, userInfo: [NSLocalizedDescriptionKey: message]) }
