import Foundation

enum LCSaveBackupStore {
    struct Backup: Identifiable {
        let url: URL
        let date: Date?
        var id: String { url.lastPathComponent }
    }

    static func root(in documents: URL) -> URL { documents.appendingPathComponent("save-backups", isDirectory: true) }

    private static func validateRoot(_ documents: URL) throws {
        let directory = root(in: documents)
        if FileManager.default.fileExists(atPath: directory.path) {
            let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, values.isDirectory == true else { throw CocoaError(.fileReadInvalidFileName) }
        }
    }

    static func validate(_ backup: URL, in documents: URL) throws {
        try validateRoot(documents)
        guard backup.deletingLastPathComponent().standardizedFileURL == root(in: documents).standardizedFileURL,
              !backup.lastPathComponent.hasPrefix(".") else { throw CocoaError(.fileReadInvalidFileName) }
        let values = try backup.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadInvalidFileName) }
    }

    static func list(in documents: URL) throws -> [Backup] {
        try validateRoot(documents)
        let directory = root(in: documents)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey], options: [.skipsHiddenFiles])
        return try urls.compactMap { url -> Backup? in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            return Backup(url: url, date: values.creationDate)
        }.sorted {
            let a = $0.date ?? .distantPast, b = $1.date ?? .distantPast
            return a == b ? $0.id > $1.id : a > b
        }
    }

    static func copy(_ snapshot: LCFileTree.Snapshot, to directory: URL, fm: FileManager) async throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for path in snapshot.directories { try fm.createDirectory(at: directory.appendingPathComponent(path), withIntermediateDirectories: true) }
        for file in snapshot.files {
            let destination = directory.appendingPathComponent(file.relativePath)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let written = try await LCFileCopy.copy(from: file.url, to: destination, isCancelled: { false }) { _ in }
            guard written == file.size else { throw CocoaError(.fileWriteUnknown) }
        }
    }

    @discardableResult
    static func create(of save: URL, in documents: URL, fm: FileManager = .default, snapshot: LCFileTree.Snapshot? = nil) async throws -> URL? {
        let snapshot = try snapshot ?? LCFileTree.scan(save, fileManager: fm)
        guard !snapshot.files.isEmpty || !snapshot.directories.isEmpty else { return nil }
        try validateRoot(documents)
        try LCStorageCapacity.check(sizes: [snapshot.totalBytes], at: documents)
        let directory = root(in: documents)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let pending = directory.appendingPathComponent(".pending-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: pending) }
        try await copy(snapshot, to: pending, fm: fm)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "save-" + formatter.string(from: Date())
        var destination = directory.appendingPathComponent(base)
        var suffix = 2
        while fm.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent(base + "-\(suffix)"); suffix += 1
        }
        try fm.moveItem(at: pending, to: destination)
        return destination
    }

    /// A backup is the exact save root. Do not apply import-wrapper heuristics.
    @discardableResult
    static func restore(_ backup: URL, in documents: URL, fm: FileManager = .default) async throws -> URL? {
        try validate(backup, in: documents)
        let incoming = try LCFileTree.scan(backup, fileManager: fm)
        let save = documents.appendingPathComponent("save", isDirectory: true)
        let current: LCFileTree.Snapshot?
        if fm.fileExists(atPath: save.path) { current = try LCFileTree.scan(save, fileManager: fm) }
        else { current = nil }
        try LCStorageCapacity.check(sizes: [incoming.totalBytes, current?.totalBytes ?? 0], at: documents)
        var safety: URL?
        if let current { safety = try await create(of: save, in: documents, fm: fm, snapshot: current) }
        let staging = documents.appendingPathComponent(".restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try await copy(incoming, to: staging.appendingPathComponent("save"), fm: fm)
        try LCFileReplacement.commitDirectory(staging, to: documents, names: ["save"], fileManager: fm)
        return safety
    }

    static func delete(_ backup: URL, in documents: URL) throws {
        try validate(backup, in: documents)
        try FileManager.default.removeItem(at: backup)
    }
}
