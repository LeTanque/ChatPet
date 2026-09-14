import Foundation

public struct InterfaceCounters: Equatable, Sendable {
    public var received: UInt64
    public var sent: UInt64
    public init(received: UInt64, sent: UInt64) { self.received = received; self.sent = sent }
}

public struct NetworkRate: Equatable, Sendable {
    public var downstream: Double
    public var upstream: Double
    public var total: Double { downstream + upstream }
    public init(downstream: Double, upstream: Double) {
        self.downstream = downstream; self.upstream = upstream
    }
    public static let zero = NetworkRate(downstream: 0, upstream: 0)
}

/// Each interface gets its own baseline; interface changes and counter resets never spike.
public struct RateEstimator: Sendable {
    private var previous: [String: InterfaceCounters] = [:]
    private var previousTime: Double?
    public init() {}
    public mutating func reset() { previous = [:]; previousTime = nil }
    public mutating func sample(_ counters: [String: InterfaceCounters], at time: Double) -> NetworkRate? {
        defer { previous = counters; previousTime = time }
        guard let oldTime = previousTime, time > oldTime, time - oldTime <= 15 else { return nil }
        var received = 0.0
        var sent = 0.0
        for (name, current) in counters {
            guard let old = previous[name], current.received >= old.received, current.sent >= old.sent else { continue }
            received += Double(current.received - old.received)
            sent += Double(current.sent - old.sent)
        }
        return NetworkRate(downstream: received / (time - oldTime), upstream: sent / (time - oldTime))
    }
}

/// Pure event detector with hysteresis, a stop grace period, and one slowdown per activity burst.
public struct NetworkEventDetector: Sendable {
    private var active = false
    private var peak = 0.0
    private var belowThresholdSince: Double?
    private var slowdownReported = false
    private var direction = PetEvent.downstream
    public init() {}
    public mutating func reset() { self = Self() }

    public mutating func consume(_ rate: NetworkRate, at time: Double, settings: NetworkSettings) -> PetEvent {
        if rate.total < settings.activityThreshold {
            guard active else { return .idle }
            if belowThresholdSince == nil { belowThresholdSince = time }
            if time - (belowThresholdSince ?? time) >= settings.stopDelay {
                active = false; peak = 0; slowdownReported = false
                belowThresholdSince = nil
                return .stopped
            }
            return direction
        }
        belowThresholdSince = nil
        if !active {
            active = true; peak = rate.total; slowdownReported = false
            direction = rate.upstream > rate.downstream ? .upstream : .downstream
        }
        // A 20% margin prevents direction flicker during simultaneous transfers.
        if rate.downstream > rate.upstream * 1.2 { direction = .downstream }
        if rate.upstream > rate.downstream * 1.2 { direction = .upstream }
        peak = max(peak, rate.total)
        if !slowdownReported && rate.total < peak * settings.slowdownRatio {
            slowdownReported = true
            return .slowdown
        }
        // Only substantial recovery rearms a slowdown in the same burst.
        if rate.total >= peak * 0.7 { slowdownReported = false }
        return direction
    }
}
