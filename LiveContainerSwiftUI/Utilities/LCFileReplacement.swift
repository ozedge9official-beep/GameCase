import Foundation
import Darwin

/// Staged files must be on the destination volume. rename replaces a file
/// atomically, so a failed commit leaves the previous file intact.
enum LCFileReplacement {
    static func replaceFile(at destination: URL, with staged: URL) throws {
        guard rename(staged.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// Commit an entire datapack together. Keep originals until every item has
    /// landed, and retain the recovery directory if any rollback fails.
    static func commitDirectory(_ staging: URL, to directory: URL, names: [String], fileManager fm: FileManager = .default) throws {
        let backup = directory.appendingPathComponent(".import-backup-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: backup, withIntermediateDirectories: false)
        var originals: [String] = []
        var installed: [String] = []
        do {
            for name in names {
                let staged = staging.appendingPathComponent(name)
                guard fm.fileExists(atPath: staged.path) else { continue }
                let destination = directory.appendingPathComponent(name)
                if fm.fileExists(atPath: destination.path) {
                    try fm.moveItem(at: destination, to: backup.appendingPathComponent(name))
                    originals.append(name)
                }
                try fm.moveItem(at: staged, to: destination)
                installed.append(name)
            }
        } catch {
            let commitError = error
            do {
                for name in installed.reversed() {
                    try fm.removeItem(at: directory.appendingPathComponent(name))
                }
                for name in originals.reversed() {
                    try fm.moveItem(at: backup.appendingPathComponent(name), to: directory.appendingPathComponent(name))
                }
            } catch {
                throw NSError(domain: "GameCase.Import", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "\(commitError.localizedDescription)\n\(error.localizedDescription)\nRecovery: \(backup.path)"
                ])
            }
            try? fm.removeItem(at: backup)
            throw commitError
        }
        try? fm.removeItem(at: backup)
    }
}
