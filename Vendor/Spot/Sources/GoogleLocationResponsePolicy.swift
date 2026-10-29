// Adaptive mode first asks for aggregated reports, then makes at most one
// all-areas request when that answer contains no newer report. Later packets
// remain eligible for merging throughout both response windows.
struct GoogleLocationResponsePolicy {
    private(set) var fallbackStarted = false
    mutating func needsAllAreasFallback(adaptive: Bool, tryingAgain: Bool, receivedUpdate: Bool) -> Bool {
        guard adaptive, !tryingAgain, !receivedUpdate, !fallbackStarted else { return false }
        fallbackStarted = true
        return true
    }
}
