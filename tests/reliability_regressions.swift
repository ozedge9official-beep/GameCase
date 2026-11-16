// Appended to storage_regressions.swift, with the same temporary root.
var reliabilityChecks = 0
func verify(_ condition: @autoclosure () throws -> Bool, _ reason: String) rethrows {
    let result = try condition()
    precondition(result, reason)
    reliabilityChecks += 1
}
func expectFailure(_ reason: String, _ action: () throws -> Void) {
    do { try action(); preconditionFailure(reason) } catch { reliabilityChecks += 1 }
}

let tracked = root.appendingPathComponent("tracked.plist")
try file(tracked, "old complete settings")
let inodeBefore = try fm.attributesOfItem(atPath: tracked.path)[.systemFileNumber] as! NSNumber
try LCRecoverableFileWriter.write(Data("new complete settings".utf8), to: tracked)
try verify(text(tracked) == "new complete settings", "complete in-place write")
let inodeAfter = try fm.attributesOfItem(atPath: tracked.path)[.systemFileNumber] as! NSNumber
verify(inodeBefore == inodeAfter, "CFPreferences-tracked inode is preserved")
verify(!fm.fileExists(atPath: LCRecoverableFileWriter.backupURL(for: tracked).path), "committed journal removed")
var attempts = 0
expectFailure("partial write must report failure") {
    try LCRecoverableFileWriter.write(Data("replacement settings".utf8), to: tracked) { data, url in
        attempts += 1
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        if attempts == 1 {
            try handle.write(contentsOf: data.prefix(3))
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }
}
try verify(text(tracked) == "new complete settings", "partial write restores original")
expectFailure("failed write and failed rollback retain journal") {
    try LCRecoverableFileWriter.write(Data("another settings".utf8), to: tracked) { _, url in
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        throw CocoaError(.fileWriteOutOfSpace)
    }
}
verify(fm.fileExists(atPath: LCRecoverableFileWriter.backupURL(for: tracked).path), "recovery bytes survive second failure")
try LCRecoverableFileWriter.recoverIfNeeded(at: tracked)
try verify(text(tracked) == "new complete settings", "next access recovers interrupted settings")
let prefsRecovery = LCGamePrefs(container: containers[0], bundleIdentifier: "test.recovered")
verify(prefsRecovery.setRawValue("safe", forKey: "value"), "seed recoverable preferences")
let prefsOriginal = try Data(contentsOf: prefsRecovery.prefsURL)
try prefsOriginal.write(to: LCRecoverableFileWriter.backupURL(for: prefsRecovery.prefsURL))
try Data().write(to: prefsRecovery.prefsURL)
verify(LCGamePrefs(container: containers[0], bundleIdentifier: "test.recovered").values["value"] as? String == "safe", "prefs reload recovers a pending write")

let tree = root.appendingPathComponent("tree")
try file(tree.appendingPathComponent("nested/one"), "one")
try file(tree.appendingPathComponent(".hidden"), "keep")
try file(tree.appendingPathComponent("__MACOSX/ignored"), "junk")
try fm.createDirectory(at: tree.appendingPathComponent("empty"), withIntermediateDirectories: true)
let snapshot = try LCFileTree.scan(tree)
verify(snapshot.files.map(\.relativePath) == [".hidden", "nested/one"], "complete stable list without system junk")
verify(snapshot.totalBytes == 7, "same walk supplies exact byte count")
verify(snapshot.directories.contains("empty"), "empty directories preserved")
try fm.createSymbolicLink(at: tree.appendingPathComponent("external"), withDestinationURL: tracked)
expectFailure("symlink must not silently become a partial backup") { _ = try LCFileTree.scan(tree) }
try fm.removeItem(at: tree.appendingPathComponent("external"))
final class BrokenEnumeration: FileManager {
    override func enumerator(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?,
                             options mask: FileManager.DirectoryEnumerationOptions = [],
                             errorHandler handler: ((URL, Error) -> Bool)? = nil) -> FileManager.DirectoryEnumerator? {
        _ = handler?(url, CocoaError(.fileReadNoPermission))
        return super.enumerator(at: url, includingPropertiesForKeys: keys, options: mask, errorHandler: handler)
    }
}
expectFailure("directory read failures propagate") { _ = try LCFileTree.scan(tree, fileManager: BrokenEnumeration()) }
let backupDocuments = root.appendingPathComponent("backup-documents")
let backup = try await LCSaveDataStore.makeBackup(of: tree, in: backupDocuments, fm: fm)!
try verify(text(backup.appendingPathComponent("nested/one")) == "one", "actual save backup copies complete file")
verify(fm.fileExists(atPath: backup.appendingPathComponent("empty").path), "actual save backup keeps empty folders")
do {
    _ = try await LCSaveDataStore.makeBackup(of: tree, in: backupDocuments, fm: BrokenEnumeration())
    preconditionFailure("incomplete scan must prevent backup completion")
} catch { reliabilityChecks += 1 }
let backupNames = try fm.contentsOfDirectory(atPath: backupDocuments.appendingPathComponent("save-backups").path)
verify(backupNames.count == 1 && !backupNames.contains(where: { $0.hasPrefix(".pending-") }), "only successful backup receives final name")
let gameSave = containers[0].containerURL.appendingPathComponent("Documents/save")
try file(gameSave.appendingPathComponent("slot.dat"), "old save")
let importedSlot = root.appendingPathComponent("incoming-single/slot.dat")
try file(importedSlot, "new save")
let beforeSingle = try await LCSaveDataStore.importSave(from: importedSlot, for: app)!
try verify(text(gameSave.appendingPathComponent("slot.dat")) == "new save" && text(beforeSingle.appendingPathComponent("slot.dat")) == "old save", "single-file save import retains complete prior backup")
let importedFolder = root.appendingPathComponent("incoming-save")
try file(importedFolder.appendingPathComponent("nested/new-slot"), "folder save")
try fm.createDirectory(at: importedFolder.appendingPathComponent("empty"), withIntermediateDirectories: true)
_ = try await LCSaveDataStore.importSave(from: importedFolder, for: app)
try verify(text(gameSave.appendingPathComponent("nested/new-slot")) == "folder save", "complete save folder import")
verify(fm.fileExists(atPath: gameSave.appendingPathComponent("empty").path) && !fm.fileExists(atPath: gameSave.appendingPathComponent("slot.dat").path), "folder import keeps empty directories and replaces the complete set")
try fm.createSymbolicLink(at: importedFolder.appendingPathComponent("bad-link"), withDestinationURL: tracked)
do {
    _ = try await LCSaveDataStore.importSave(from: importedFolder, for: app)
    preconditionFailure("unsupported source content must abort import")
} catch { reliabilityChecks += 1 }
try verify(text(gameSave.appendingPathComponent("nested/new-slot")) == "folder save", "failed source scan leaves current save unchanged")

let modRecovery = root.appendingPathComponent("mod-recovery")
let modDestination = root.appendingPathComponent("mods")
try fm.createDirectory(at: modDestination, withIntermediateDirectories: true)
for name in ["one", "two"] { try file(modRecovery.appendingPathComponent(name), "old-\(name)") }
final class BrokenRestore: FileManager {
    override func moveItem(at source: URL, to destination: URL) throws {
        if source.lastPathComponent == "one" { throw CocoaError(.fileWriteNoPermission) }
        try super.moveItem(at: source, to: destination)
    }
}
expectFailure("failed Mod recovery retains recovery directory") {
    try LCFileReplacement.restoreMovedItems([modRecovery.appendingPathComponent("one"), modRecovery.appendingPathComponent("two")],
                                            to: modDestination, recoveryDirectory: modRecovery,
                                            cause: CocoaError(.fileWriteOutOfSpace), fileManager: BrokenRestore())
}
try verify(text(modRecovery.appendingPathComponent("one")) == "old-one", "unrestored Mod original retained")
try verify(text(modDestination.appendingPathComponent("two")) == "old-two", "other originals still restored")

func ipaBundle(_ name: String) throws -> URL {
    let url = root.appendingPathComponent(name + "/Game.app")
    try file(url.appendingPathComponent("Game"), "new executable")
    let info: [String: Any] = ["CFBundleIdentifier": "test.game", "CFBundleExecutable": "Game"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url.appendingPathComponent("Info.plist"))
    return url
}
let oldBundle = root.appendingPathComponent("installed/Game.app")
try file(oldBundle.appendingPathComponent("Game"), "old playable executable")
let newBundle = try ipaBundle("source-one")
try verify(LCAppInstallTransaction.bundleIdentifier(in: newBundle) == "test.game", "validate IPA identity before staging")
let failedPreparation = try LCAppInstallTransaction(source: newBundle, destination: oldBundle)
do {
    try await failedPreparation.commit {
        try verify(text(oldBundle.appendingPathComponent("Game")) == "old playable executable", "old app exists throughout preparation")
        throw CocoaError(.fileReadCorruptFile)
    }
    preconditionFailure("signing/preparation failure must abort replacement")
} catch { reliabilityChecks += 1 }
try verify(text(oldBundle.appendingPathComponent("Game")) == "old playable executable", "failed preparation preserves playable old app")
final class BrokenInstallCommit: FileManager {
    override func moveItem(at source: URL, to destination: URL) throws {
        if source.deletingLastPathComponent().lastPathComponent.hasPrefix(".ipa-install-") {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try super.moveItem(at: source, to: destination)
    }
}
let failedCommit = try LCAppInstallTransaction(source: ipaBundle("source-two"), destination: oldBundle, fileManager: BrokenInstallCommit())
do {
    try await failedCommit.commit {}
    preconditionFailure("install commit failure must roll back")
} catch { reliabilityChecks += 1 }
try verify(text(oldBundle.appendingPathComponent("Game")) == "old playable executable", "failed app commit restores original bundle")
let successfulInstall = try LCAppInstallTransaction(source: ipaBundle("source-three"), destination: oldBundle)
try await successfulInstall.commit { try file(successfulInstall.bundleURL.appendingPathComponent("prepared"), "signed") }
try verify(text(oldBundle.appendingPathComponent("Game")) == "new executable" && text(oldBundle.appendingPathComponent("prepared")) == "signed", "prepared app committed together")
let malformed = try ipaBundle("malformed")
let malformedInfo = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "test.game", "CFBundleExecutable": "../other"], format: .xml, options: 0)
try malformedInfo.write(to: malformed.appendingPathComponent("Info.plist"))
expectFailure("invalid executable path rejected") { _ = try LCAppInstallTransaction.bundleIdentifier(in: malformed) }
let recoveredBundle = try ipaBundle("recovered-bundle")
let recoveredInfo: [String: Any] = ["CFBundleIdentifier": "temporary.wrapper", "CFBundleExecutable": "missing-temporary-executable",
                                  "LCBundleIdentifier": "test.game", "LCBundleExecutable": "Game"]
try PropertyListSerialization.data(fromPropertyList: recoveredInfo, format: .xml, options: 0).write(to: recoveredBundle.appendingPathComponent("Info.plist"))
try verify(LCAppInstallTransaction.bundleIdentifier(in: recoveredBundle) == "test.game", "interrupted-sign IPA recovery fields retain original compatibility")

let cache = LCFileValueCache<NSString>(costLimit: 1024, countLimit: 8)
let cover = root.appendingPathComponent("cover")
try file(cover, "image one")
var imageLoads = 0
func cachedValue() -> NSString? {
    cache.value(at: cover, load: { url in imageLoads += 1; return (try? String(contentsOf: url)) as NSString? }, cost: { $0.length })
}
for _ in 0..<500 { precondition(cachedValue() == "image one", "same version returns cached value") }
verify(imageLoads == 1, "500 requests perform only one value load")
let replacementImage = root.appendingPathComponent("replacement-cover")
try file(replacementImage, "image two")
try LCFileReplacement.replaceFile(at: cover, with: replacementImage)
verify(cachedValue() == "image two" && imageLoads == 2, "same-size image replacement invalidates cached version")
cache.removeAll()
verify(cachedValue() == "image two" && imageLoads == 3, "explicit purge reloads image")
try fm.removeItem(at: cover)
verify(cachedValue() == nil, "deleted covers never return stale images")
var gate = LCProgressGate()
let allowed = (0..<10000).filter { gate.shouldReport(now: Double($0) / 1000) }.count
verify(allowed <= 100 && allowed >= 90, "UI progress limited to about ten reports per second")
let largeSource = root.appendingPathComponent("large-source")
let largeDest = root.appendingPathComponent("large-dest")
let sourceBytes = Data(repeating: 0xa5, count: 12 * 1024 * 1024 + 17)
try sourceBytes.write(to: largeSource)
var finalProgress: Int64 = -1
let copied = try await LCFileCopy.copy(from: largeSource, to: largeDest, isCancelled: { false }) { finalProgress = $0 }
try verify(copied == Int64(sourceBytes.count) && Data(contentsOf: largeDest) == sourceBytes, "chunked copy preserves every byte")
verify(finalProgress == copied, "throttled progress still reports exact final count")
do {
    _ = try await LCFileCopy.copy(from: largeSource, to: root.appendingPathComponent("cancelled"), isCancelled: { true }) { _ in }
    preconditionFailure("copy cancellation must still work")
} catch LCFileCopyError.cancelled { reliabilityChecks += 1 }
print("Reliability/performance regressions passed: \(reliabilityChecks) checks; 500 unchanged-file requests -> 1 loader call; 10000 progress events -> \(allowed) reports")
