import AppKit
import ImageIO
import PetCore

struct LoadedPet: Identifiable {
    var manifest: PetPack
    var images: [String: [NSImage]] = [:]
    var id: String { manifest.id }
}

@MainActor
final class PetLibrary {
    let directory: URL
    private(set) var pets: [LoadedPet] = []
    private(set) var warnings: [String] = []
    init(directory: URL) { self.directory = directory }
    func reload() {
        pets = []; warnings = []
        let packaged = Bundle.main.resourceURL?.appendingPathComponent("DesktopPet_DesktopPet.bundle")
        let resources = packaged.flatMap { Bundle(url: $0) } ?? Bundle.module
        let bundled = resources.resourceURL!.appendingPathComponent("Assets/BlueTurtle")
        do { pets.append(try load(folder: bundled)) }
        catch { warnings.append("Blue Turtle: \(error.localizedDescription)") }
        pets += PetPack.builtins.map { LoadedPet(manifest: $0) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
            for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard (try folder.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { continue }
                do {
                    let pet = try load(folder: folder)
                    guard !pets.contains(where: { $0.id == pet.id }), !pet.id.hasPrefix("builtin.") else { throw PackError.duplicateID }
                    pets.append(pet)
                } catch { warnings.append("\(folder.lastPathComponent): \(error.localizedDescription)") }
            }
        } catch { warnings.append(error.localizedDescription) }
    }
    func load(folder: URL) throws -> LoadedPet {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        let manifestURL = root.appendingPathComponent("pet.json").resolvingSymlinksInPath()
        guard manifestURL.path.hasPrefix(root.path + "/") else { throw PackError.invalidManifest }
        let manifestData = try Data(contentsOf: manifestURL)
        guard manifestData.count <= 1_000_000 else { throw PackError.oversized }
        let manifest = try JSONDecoder().decode(PetPack.self, from: manifestData)
        try manifest.validate()
        var pet = LoadedPet(manifest: manifest)
        var totalBytes = 0
        var decodedBytes = 0
        for (animation, clip) in manifest.clips {
            var images: [NSImage] = []
            for path in clip.frames {
                let file = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
                guard file.path.hasPrefix(root.path + "/") else { throw PackError.unsafeOrMissingImage }
                let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                totalBytes += values.fileSize ?? 0
                guard values.isRegularFile == true else { throw PackError.unsafeOrMissingImage }
                guard totalBytes <= 64 * 1_024 * 1_024 else { throw PackError.oversized }
                guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                      CGImageSourceGetType(source) as String? == "public.png",
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      width > 0, height > 0, width <= 2048, height <= 2048 else { throw PackError.unsafeOrMissingImage }
                decodedBytes += width * height * 4
                guard decodedBytes <= 128 * 1_024 * 1_024 else { throw PackError.oversized }
                guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PackError.unsafeOrMissingImage }
                images.append(NSImage(cgImage: image, size: NSSize(width: width, height: height)))
            }
            pet.images[animation] = images
        }
        return pet
    }
    /// Copy only validated manifest/frame files; never overwrite an installed pack.
    func install(folder: URL) throws -> String {
        let pet = try load(folder: folder)
        guard !pet.id.hasPrefix("builtin."), !pets.contains(where: { $0.id == pet.id }) else { throw PackError.duplicateID }
        let target = directory.appendingPathComponent(pet.id, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: target.path) else { throw PackError.duplicateID }
        let staging = directory.appendingPathComponent(".import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try JSONEncoder().encode(pet.manifest).write(to: staging.appendingPathComponent("pet.json"))
        for path in Set(pet.manifest.clips.values.flatMap(\.frames)) {
            let destination = staging.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: folder.appendingPathComponent(path), to: destination)
        }
        _ = try load(folder: staging)
        try FileManager.default.moveItem(at: staging, to: target)
        reload()
        return pet.id
    }
}
