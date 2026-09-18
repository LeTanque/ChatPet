import Foundation
import Testing
import PetCore
@testable import DesktopPet

@MainActor
@Test func bundledBlueTurtleLoadsEveryRequestedAnimation() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = PetLibrary(directory: directory)
    library.reload()
    #expect(library.warnings.isEmpty)
    let turtle = try #require(library.pets.first)
    #expect(turtle.id == "builtin.blue-turtle")
    #expect(turtle.images.values.reduce(0) { $0 + $1.count } == 36)
    for (animation, _) in turtle.manifest.clips {
        let frames = try #require(turtle.images[animation])
        #expect(!frames.isEmpty)
        #expect(frames.allSatisfy { $0.size.width == 192 && $0.size.height == 208 })
    }
}

@MainActor
@Test func bundledMichelangeloLoadsEveryClip() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = PetLibrary(directory: directory)
    library.reload()
    let mikey = try #require(library.pets.first { $0.id == "builtin.michelangelo" })
    #expect(mikey.manifest.clips.count == 9)
    #expect(mikey.images.values.reduce(0) { $0 + $1.count } == 47)
    for (animation, _) in mikey.manifest.clips {
        let frames = try #require(mikey.images[animation])
        #expect(!frames.isEmpty)
        #expect(frames.allSatisfy { $0.size.width == 192 && $0.size.height == 208 })
    }
}

@Test func settingsPersistAndCorruptOriginalIsPreserved() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigurationStore(directory: directory)
    var config = PetConfiguration()
    config.selectedPet = "builtin.ember"
    config.network.interface = "en0"
    config.mappings["downstream"] = .laptop
    try store.save(config)
    #expect(try ConfigurationStore(directory: directory).load() == config)
    let corrupt = Data("corrupt settings, preserve me".utf8)
    try corrupt.write(to: store.file)
    try store.preserveUnreadableFile()
    try store.save(PetConfiguration())
    let backup = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("settings-unreadable-") })
    #expect(try Data(contentsOf: backup) == corrupt)
}

@MainActor
@Test func importedPackSurvivesReloadAndCannotOverwriteAnother() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let manifest = PetPack(id: "custom.test", name: "Custom test", species: .cat, bodyColor: "#AABBCC", accentColor: "#112233")
    try JSONEncoder().encode(manifest).write(to: source.appendingPathComponent("pet.json"))
    let library = PetLibrary(directory: directory.appendingPathComponent("Pets"))
    library.reload()
    #expect(try library.install(folder: source) == "custom.test")
    let reloaded = PetLibrary(directory: library.directory); reloaded.reload()
    #expect(reloaded.pets.contains { $0.id == "custom.test" })
    #expect(throws: PackError.self) { try reloaded.install(folder: source) }
}

@MainActor
@Test func packRejectsSymlinkOutsideItsRoot() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let outside = directory.appendingPathComponent("outside.png")
    try Data().write(to: outside)
    try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("escape.png"), withDestinationURL: outside)
    let manifest = PetPack(id: "custom.escape", name: "Escape", species: .cat, bodyColor: "#AABBCC", accentColor: "#112233",
                           clips: ["idle": SpriteClip(frames: ["escape.png"], framesPerSecond: 8)])
    try JSONEncoder().encode(manifest).write(to: source.appendingPathComponent("pet.json"))
    let library = PetLibrary(directory: directory.appendingPathComponent("Pets"))
    #expect(throws: PackError.self) { try library.load(folder: source) }
}
