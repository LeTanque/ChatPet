import Foundation
import PetCore

struct ConfigurationStore {
    let directory: URL
    var file: URL { directory.appendingPathComponent("settings.json") }
    var packsDirectory: URL { directory.appendingPathComponent("Pets", isDirectory: true) }
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DesktopPet", isDirectory: true)
    }
    func load() throws -> PetConfiguration {
        guard FileManager.default.fileExists(atPath: file.path) else { return PetConfiguration() }
        return try ConfigurationCodec.decode(Data(contentsOf: file))
    }
    func save(_ config: PetConfiguration) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try ConfigurationCodec.encode(config).write(to: file, options: .atomic)
    }
    func preserveUnreadableFile() throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let backup = directory.appendingPathComponent("settings-unreadable-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: file, to: backup)
    }
}
