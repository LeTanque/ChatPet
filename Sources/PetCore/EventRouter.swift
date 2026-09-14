import Foundation

/// Sources emit semantic events. The router alone owns priority and temporary-animation lifetime.
/// Add future sources (build status, timers, etc.) without coupling them to the renderer.
public struct EventRouter: Sendable {
    public private(set) var baseEvent: PetEvent = .idle
    private var transient: (event: PetEvent, deadline: Double, priority: Int)?
    public init() {}
    public mutating func reset() { baseEvent = .idle; transient = nil }
    public mutating func receive(_ event: PetEvent, at time: Double, duration: Double = 0, priority: Int = 0) {
        if duration > 0 {
            if let current = transient, current.deadline > time, current.priority > priority { return }
            transient = (event, time + duration, priority)
        } else {
            baseEvent = event
        }
    }
    public mutating func currentEvent(at time: Double) -> PetEvent {
        if let current = transient {
            if current.deadline > time { return current.event }
            transient = nil
        }
        return baseEvent
    }
}
