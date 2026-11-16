import Foundation

/// Patching and signing happen on the destination volume, while the previous
/// installed app remains available. Commit only after preparation succeeds.
final class LCAppInstallTransaction {
    let stagingDirectory: URL
    let bundleURL: URL
    private let destination: URL
    private let fm: FileManager

    static func bundleIdentifier(in bundle: URL) throws -> String {
        let root = bundle.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let infoURL = bundle.appendingPathComponent("Info.plist")
        guard infoURL.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root),
              let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // LCAppInfo restores these original fields after an interrupted sign.
        // Validate the same identity/executable that it will actually use.
        let recovering = info["LCBundleIdentifier"] != nil
        guard let identifier = info[recovering ? "LCBundleIdentifier" : "CFBundleIdentifier"] as? String,
              !identifier.isEmpty, !identifier.contains(where: { $0 == "/" || $0 == "\\" || $0.isWhitespace || $0 == "\0" }),
              identifier != ".", identifier != "..",
              let executable = info[recovering ? "LCBundleExecutable" : "CFBundleExecutable"] as? String,
              !executable.isEmpty, executable != ".", executable != "..",
              !executable.contains("/"), !executable.contains("\\"), !executable.contains("\0") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let executableURL = bundle.appendingPathComponent(executable).resolvingSymlinksInPath().standardizedFileURL
        guard executableURL.path.hasPrefix(root), FileManager.default.fileExists(atPath: executableURL.path) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return identifier
    }

    init(source: URL, destination: URL, fileManager fm: FileManager = .default) throws {
        self.destination = destination
        self.fm = fm
        stagingDirectory = destination.deletingLastPathComponent().appendingPathComponent(".ipa-install-\(UUID().uuidString)", isDirectory: true)
        bundleURL = stagingDirectory.appendingPathComponent(destination.lastPathComponent, isDirectory: true)
        try fm.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        do { try fm.moveItem(at: source, to: bundleURL) }
        catch { try? fm.removeItem(at: stagingDirectory); throw error }
    }
    deinit { try? fm.removeItem(at: stagingDirectory) }

    func commit(after prepare: () async throws -> Void) async throws {
        try await prepare()
        try LCFileReplacement.commitDirectory(stagingDirectory, to: destination.deletingLastPathComponent(),
                                              names: [destination.lastPathComponent], fileManager: fm)
    }
}
