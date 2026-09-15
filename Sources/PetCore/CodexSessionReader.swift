import Foundation

/// Read-only local adapter. No app-server process, credentials, hooks, or configuration edits.
public actor CodexSessionReader {
    private struct Cursor {
        var offset: UInt64
        var identity: UInt64
        var lines: ActivityLineBuffer
        var activity = CodexSessionActivity()
    }
    private let root: URL
    private let monitoringSince: Date
    private var cursors: [URL: Cursor] = [:]
    private var files: [URL] = []
    private var lastScan = Date.distantPast
    public init(root: URL, monitoringSince: Date = Date()) { self.root = root; self.monitoringSince = monitoringSince }

    public func poll(now: Date = Date(), staleAfter: TimeInterval = 3600, reactionDuration: TimeInterval = 4) throws -> CodexActivitySummary {
        if now.timeIntervalSince(lastScan) >= 5 {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ReaderError.missingDirectory
            }
            guard FileManager.default.isReadableFile(atPath: root.path),
                  let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles])
            else { throw ReaderError.unreadableDirectory }
            var candidates: [(URL, Date)] = []
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                let attributes = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                if attributes.isRegularFile == true, let modified = attributes.contentModificationDate,
                   now.timeIntervalSince(modified) <= max(86_400, staleAfter) { candidates.append((url, modified)) }
            }
            files = candidates.sorted { $0.1 > $1.1 }.prefix(64).map(\.0)
            cursors = cursors.filter { files.contains($0.key) }
            lastScan = now
        }
        var unreadable = 0
        for file in files {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
                let identity = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
                var cursor: Cursor
                if let existing = cursors[file], existing.identity == identity, existing.offset <= size {
                    cursor = existing
                } else {
                    let start = size > 2_097_152 ? size - 2_097_152 : 0
                    cursor = Cursor(offset: start, identity: identity, lines: ActivityLineBuffer(skippingPartialLine: start > 0))
                }
                if cursor.offset < size {
                    let handle = try FileHandle(forReadingFrom: file)
                    defer { try? handle.close() }
                    try handle.seek(toOffset: cursor.offset)
                    // At most 2 MB per session per poll. Never load an entire transcript.
                    let data = try handle.read(upToCount: Int(min(2_097_152, size - cursor.offset))) ?? Data()
                    cursor.offset += UInt64(data.count)
                    for record in cursor.lines.append(data) { cursor.activity.consume(record, now: now) }
                }
                cursors[file] = cursor
            } catch {
                unreadable += 1; cursors.removeValue(forKey: file)
            }
        }
        var summary = CodexActivitySummary.summarize(cursors.values.map(\.activity), now: now, monitoringSince: monitoringSince,
                                                     staleAfter: staleAfter, reactionDuration: reactionDuration)
        summary.unreadableCount = unreadable
        return summary
    }
    public enum ReaderError: LocalizedError {
        case missingDirectory, unreadableDirectory
        public var errorDescription: String? {
            switch self {
            case .missingDirectory: "Session folder not found. Choose your Codex sessions folder."
            case .unreadableDirectory: "Session folder cannot be read. Choose an accessible folder."
            }
        }
    }
}
