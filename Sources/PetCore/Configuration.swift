import Foundation

public enum PetAnimation: String, Codable, CaseIterable, Sendable, Identifiable {
    case idle, runLeft, runRight, failed, laptop, waiting, celebration
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .idle: "Idle"
        case .runLeft: "Run left"
        case .runRight: "Run right"
        case .failed: "Failed / tired"
        case .laptop: "Viewing laptop"
        case .waiting: "Waiting"
        case .celebration: "Celebration"
        }
    }
    public var direction: Double {
        switch self { case .runLeft: -1; case .runRight: 1; default: 0 }
    }
}

public enum PetEvent: String, Codable, CaseIterable, Sendable, Identifiable {
    case idle, downstream, upstream, slowdown, stopped, occasional
    case taskWorking, taskWaiting, taskCompleted, taskFailed
    public var id: String { rawValue }
    public var isTaskEvent: Bool { [.taskWorking, .taskWaiting, .taskCompleted, .taskFailed].contains(self) }
    public var title: String {
        switch self {
        case .idle: "No recent activity"
        case .downstream: "Downloading"
        case .upstream: "Uploading"
        case .slowdown: "Traffic slows significantly"
        case .stopped: "Traffic stops"
        case .occasional: "Occasional break"
        case .taskWorking: "Task working"
        case .taskWaiting: "Task waiting for input"
        case .taskCompleted: "Task finished"
        case .taskFailed: "Task failed or interrupted"
        }
    }
    public var defaultAnimation: PetAnimation {
        switch self {
        case .idle: .idle
        case .downstream: .runLeft
        case .upstream: .runRight
        case .slowdown, .stopped: .failed
        case .occasional: .laptop
        case .taskWorking: .laptop
        case .taskWaiting: .waiting
        case .taskCompleted: .celebration
        case .taskFailed: .failed
        }
    }
}

public struct NetworkSettings: Codable, Equatable, Sendable {
    /// nil selects active Ethernet/Wi-Fi interfaces (en*), avoiding VPN double counting.
    public var interface: String? = nil
    public var sampleInterval: Double = 1
    public var activityThreshold: Double = 2_048
    public var slowdownRatio: Double = 0.25
    public var stopDelay: Double = 3
    public var failureDuration: Double = 2.5
    public init() {}
    public mutating func normalize() {
        sampleInterval = sampleInterval.clamped(0.25...5, fallback: 1)
        activityThreshold = activityThreshold.clamped(64...100_000_000, fallback: 2_048)
        slowdownRatio = slowdownRatio.clamped(0.05...0.9, fallback: 0.25)
        stopDelay = stopDelay.clamped(1...30, fallback: 3)
        failureDuration = failureDuration.clamped(0.5...10, fallback: 2.5)
        if interface == "" { interface = nil }
    }
}

public struct CodexSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var sessionsDirectory = "~/.codex/sessions"
    public var staleAfter: Double = 3600
    public var reactionDuration: Double = 4
    public init() {}
    public mutating func normalize() {
        staleAfter = staleAfter.clamped(60...86_400, fallback: 3600)
        reactionDuration = reactionDuration.clamped(1...15, fallback: 4)
        if sessionsDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { sessionsDirectory = "~/.codex/sessions" }
    }
}

public struct PetConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var selectedPet = "builtin.blue-turtle"
    public var scale: Double = 1
    public var visible = true
    public var paused = false
    public var clickThrough = false
    public var movementEnabled = true
    public var networkEnabled = true
    public var occasionalEnabled = true
    public var occasionalMinimum: Double = 45
    public var occasionalMaximum: Double = 100
    public var occasionalDuration: Double = 4
    public var network = NetworkSettings()
    public var codex = CodexSettings()
    public var mappings: [String: PetAnimation] = [:]
    public var positionX: Double? = nil
    public var positionY: Double? = nil
    public init() {}
    public func animation(for event: PetEvent) -> PetAnimation {
        mappings[event.rawValue] ?? event.defaultAnimation
    }
    public mutating func normalize() {
        scale = scale.clamped(0.6...2, fallback: 1)
        occasionalMinimum = occasionalMinimum.clamped(10...3_600, fallback: 45)
        occasionalMaximum = occasionalMaximum.clamped(occasionalMinimum...7_200, fallback: 100)
        occasionalDuration = occasionalDuration.clamped(1...15, fallback: 4)
        if let x = positionX, !x.isFinite { positionX = nil }
        if let y = positionY, !y.isFinite { positionY = nil }
        network.normalize()
        codex.normalize()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, selectedPet, scale, visible, paused, clickThrough, movementEnabled, networkEnabled
        case occasionalEnabled, occasionalMinimum, occasionalMaximum, occasionalDuration, network, codex, mappings, positionX, positionY
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        selectedPet = try values.decode(String.self, forKey: .selectedPet)
        scale = try values.decode(Double.self, forKey: .scale)
        visible = try values.decode(Bool.self, forKey: .visible)
        paused = try values.decode(Bool.self, forKey: .paused)
        clickThrough = try values.decode(Bool.self, forKey: .clickThrough)
        movementEnabled = try values.decode(Bool.self, forKey: .movementEnabled)
        networkEnabled = try values.decode(Bool.self, forKey: .networkEnabled)
        occasionalEnabled = try values.decode(Bool.self, forKey: .occasionalEnabled)
        occasionalMinimum = try values.decode(Double.self, forKey: .occasionalMinimum)
        occasionalMaximum = try values.decode(Double.self, forKey: .occasionalMaximum)
        occasionalDuration = try values.decode(Double.self, forKey: .occasionalDuration)
        network = try values.decode(NetworkSettings.self, forKey: .network)
        // Upgrade existing v1 settings without resetting any user preference.
        codex = try values.decodeIfPresent(CodexSettings.self, forKey: .codex) ?? CodexSettings()
        mappings = try values.decode([String: PetAnimation].self, forKey: .mappings)
        positionX = try values.decodeIfPresent(Double.self, forKey: .positionX)
        positionY = try values.decodeIfPresent(Double.self, forKey: .positionY)
    }
}

extension Double {
    func clamped(_ range: ClosedRange<Double>, fallback: Double) -> Double {
        isFinite ? min(range.upperBound, max(range.lowerBound, self)) : fallback
    }
}

/// Explicit versioning prevents silently overwriting settings from a newer app.
public enum ConfigurationCodec {
    public static func decode(_ data: Data) throws -> PetConfiguration {
        var config = try JSONDecoder().decode(PetConfiguration.self, from: data)
        guard config.schemaVersion == 1 else { throw ConfigurationError.unsupportedVersion }
        config.normalize()
        return config
    }
    public static func encode(_ configuration: PetConfiguration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(configuration)
    }
}

public enum ConfigurationError: LocalizedError {
    case unsupportedVersion
    public var errorDescription: String? { "This settings file uses an unsupported version." }
}
