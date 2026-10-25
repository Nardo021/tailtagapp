import Foundation

/// Tokens increase on every query. A finished search is applied only when its token is still current.
public actor LatestQueryGate {
    private var generation = 0

    public init() {}

    public func issue() -> Int {
        generation += 1
        return generation
    }

    public func isCurrent(_ token: Int) -> Bool {
        token == generation
    }

    public func accept<Value: Sendable>(token: Int, value: Value) -> Value? {
        guard token == generation else { return nil }
        return value
    }
}
