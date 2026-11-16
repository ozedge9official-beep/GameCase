import Foundation

/// A single, checked directory walk supplies both copy order and byte counts.
/// An unreadable directory or file must never become a successful partial backup.
enum LCFileTree {
    struct File {
        let url: URL
        let relativePath: String
        let size: Int64
    }
    struct Snapshot {
        let files: [File]
        let directories: [String]
        let totalBytes: Int64
    }

    static func scan(_ root: URL, fileManager fm: FileManager = .default) throws -> Snapshot {
        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { throw CocoaError(.fileReadUnsupportedScheme) }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        var scanError: Error?
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, error in
            scanError = error
            return false
        }) else { throw CocoaError(.fileReadUnknown) }
        var files: [File] = []
        var directories: [String] = []
        var total: Int64 = 0
        let prefix = root.standardizedFileURL.path + "/"
        for case let url as URL in enumerator {
            if url.lastPathComponent == "__MACOSX" || url.lastPathComponent == ".DS_Store" {
                enumerator.skipDescendants(); continue
            }
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else {
                throw NSError(domain: "GameCase.FileTree", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported symbolic link: \(url.path)"])
            }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { throw CocoaError(.fileReadInvalidFileName) }
            let relative = String(path.dropFirst(prefix.count))
            if values.isDirectory == true { directories.append(relative) }
            else if values.isRegularFile == true, let size = values.fileSize {
                guard size >= 0, Int64(size) <= Int64.max - total else { throw CocoaError(.fileReadTooLarge) }
                total += Int64(size)
                files.append(File(url: url, relativePath: relative, size: Int64(size)))
            } else { throw CocoaError(.fileReadUnknown) }
        }
        if let scanError { throw scanError }
        return Snapshot(files: files.sorted { $0.relativePath < $1.relativePath }, directories: directories.sorted(), totalBytes: total)
    }
}
