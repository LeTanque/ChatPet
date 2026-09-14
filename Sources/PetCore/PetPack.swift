import Foundation

public enum PetSpecies: String, Codable, Sendable { case cat, fox, robot }

public struct SpriteClip: Codable, Equatable, Sendable {
    public var frames: [String]
    public var framesPerSecond: Double
    public var frameDurations: [Double]?
    public init(frames: [String], framesPerSecond: Double, frameDurations: [Double]? = nil) {
        self.frames = frames; self.framesPerSecond = framesPerSecond; self.frameDurations = frameDurations
    }
    public func frameIndex(elapsed: Double) -> Int {
        guard !frames.isEmpty else { return 0 }
        let durations = frameDurations ?? Array(repeating: 1 / max(1, framesPerSecond), count: frames.count)
        let total = durations.reduce(0, +)
        guard total > 0, elapsed.isFinite else { return 0 }
        var position = max(0, elapsed).truncatingRemainder(dividingBy: total)
        for (index, duration) in durations.enumerated() {
            if position < duration { return index }
            position -= duration
        }
        return frames.count - 1
    }
}

/// Data only: packs cannot contain executable plug-ins or remote resources.
public struct PetPack: Codable, Equatable, Sendable, Identifiable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var species: PetSpecies
    public var bodyColor: String
    public var accentColor: String
    public var clips: [String: SpriteClip]
    public init(id: String, name: String, species: PetSpecies, bodyColor: String, accentColor: String,
                clips: [String: SpriteClip] = [:]) {
        schemaVersion = 1; self.id = id; self.name = name; self.species = species
        self.bodyColor = bodyColor; self.accentColor = accentColor; self.clips = clips
    }
    public func validate() throws {
        guard schemaVersion == 1, !id.isEmpty, id.count <= 80,
              id.range(of: "^[a-zA-Z0-9][a-zA-Z0-9._-]*$", options: .regularExpression) != nil,
              !name.isEmpty, name.count <= 80,
              [bodyColor, accentColor].allSatisfy({ $0.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil })
        else { throw PackError.invalidManifest }
        guard clips.count <= PetAnimation.allCases.count else { throw PackError.invalidManifest }
        for (key, clip) in clips {
            guard PetAnimation(rawValue: key) != nil, !clip.frames.isEmpty, clip.frames.count <= 120,
                  clip.framesPerSecond.isFinite, (1...30).contains(clip.framesPerSecond),
                  clip.frames.allSatisfy(Self.safeFramePath) else { throw PackError.invalidManifest }
            if let durations = clip.frameDurations {
                guard durations.count == clip.frames.count,
                      durations.allSatisfy({ $0.isFinite && (0.03...10).contains($0) })
                else { throw PackError.invalidManifest }
            }
        }
    }
    public static func safeFramePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.hasPrefix("/") && !parts.contains("..") && !parts.contains(".") &&
            !parts.contains("") && !path.contains(":") && !path.contains("\\") &&
            ["png"].contains((path as NSString).pathExtension.lowercased())
    }
    public static let builtins: [PetPack] = [
        .init(id: "builtin.mochi", name: "Mochi", species: .cat, bodyColor: "#E9E2D3", accentColor: "#AA8DC7"),
        .init(id: "builtin.ember", name: "Ember", species: .fox, bodyColor: "#ED9754", accentColor: "#FFF0D9"),
        .init(id: "builtin.pip", name: "Pip", species: .robot, bodyColor: "#83BFB0", accentColor: "#DCF8BA")
    ]
}

public enum PackError: LocalizedError {
    case invalidManifest, unsafeOrMissingImage, duplicateID, oversized
    public var errorDescription: String? {
        switch self {
        case .invalidManifest: "The pet pack manifest is invalid or uses an unsupported version."
        case .unsafeOrMissingImage: "A frame is missing, is not a valid PNG, or is outside the pet pack folder."
        case .duplicateID: "A pet with this ID is already installed. Give the new pack a unique ID."
        case .oversized: "Pet packs must be under 64 MB with images no larger than 2048 × 2048."
        }
    }
}
