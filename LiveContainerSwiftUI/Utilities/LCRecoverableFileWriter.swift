import Foundation

/// Preserve the inode observed by CFPreferences while retaining the previous
/// contents until the new bytes are synchronized and verified.
enum LCRecoverableFileWriter {
    private static let lock = NSRecursiveLock()

    static func backupURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).gamecase-write-backup")
    }

    private static func overwrite(_ data: Data, at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    static func recoverIfNeeded(at url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        let backup = backupURL(for: url)
        guard FileManager.default.fileExists(atPath: backup.path) else { return }
        let original = try Data(contentsOf: backup)
        try overwrite(original, at: url)
        guard try Data(contentsOf: url) == original else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.removeItem(at: backup)
    }

    /// The optional writer lets fault tests exercise partial writes and a
    /// second failure during recovery using the production transaction logic.
    static func write(_ data: Data, to url: URL, writer: ((Data, URL) throws -> Void)? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        try recoverIfNeeded(at: url)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            try data.write(to: url, options: .atomic)
            return
        }
        let old = try Data(contentsOf: url)
        guard old != data else { return }
        let backup = backupURL(for: url)
        try old.write(to: backup, options: .atomic)
        let write = writer ?? { try overwrite($0, at: $1) }
        do {
            try write(data, url)
            guard try Data(contentsOf: url) == data else { throw CocoaError(.fileWriteUnknown) }
            try fm.removeItem(at: backup)
        } catch {
            let writeError = error
            do {
                try write(old, url)
                guard try Data(contentsOf: url) == old else { throw CocoaError(.fileWriteUnknown) }
                try fm.removeItem(at: backup)
            } catch {
                throw NSError(domain: "GameCase.FileRecovery", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "\(writeError.localizedDescription)\n\(error.localizedDescription)\nRecovery: \(backup.path)"
                ])
            }
            throw writeError
        }
    }
}
