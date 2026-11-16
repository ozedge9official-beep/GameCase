import Foundation

let fm = FileManager.default
let root = LCPath.docPath
try fm.createDirectory(at: root, withIntermediateDirectories: true)
func file(_ path: URL, _ text: String) throws {
    try fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: path)
}
func text(_ path: URL) throws -> String { try String(contentsOf: path, encoding: .utf8) }
func require(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
    let result = try condition()
    precondition(result, message)
}

let destination = root.appendingPathComponent("destination")
let stagedFile = root.appendingPathComponent("staged")
try file(destination, "old")
try file(stagedFile, "new")
try LCFileReplacement.replaceFile(at: destination, with: stagedFile)
try require(text(destination) == "new", "atomic replacement")
do {
    try LCFileReplacement.replaceFile(at: destination, with: stagedFile)
    preconditionFailure("missing staged file should fail")
} catch {}
try require(text(destination) == "new", "failed rename preserves original")

final class FailingMoveManager: FileManager, @unchecked Sendable {
    var stagingPath = ""
    override func moveItem(at source: URL, to destination: URL) throws {
        if source.deletingLastPathComponent().path == stagingPath && source.lastPathComponent == "two" {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try super.moveItem(at: source, to: destination)
    }
}
let stage = root.appendingPathComponent("stage")
let target = root.appendingPathComponent("target")
for name in ["one", "two"] {
    try file(stage.appendingPathComponent(name), "new-\(name)")
    try file(target.appendingPathComponent(name), "old-\(name)")
}
let failing = FailingMoveManager()
failing.stagingPath = stage.path
do {
    try LCFileReplacement.commitDirectory(stage, to: target, names: ["one", "two"], fileManager: failing)
    preconditionFailure("commit should fail")
} catch {}
for name in ["one", "two"] {
    try require(text(target.appendingPathComponent(name)) == "old-\(name)", "rollback restores every original")
}
try file(stage.appendingPathComponent("one"), "new-one")
try LCFileReplacement.commitDirectory(stage, to: target, names: ["one", "two"])
try require(text(target.appendingPathComponent("two")) == "new-two", "complete transaction")

let containers = [LCContainer(containerURL: root.appendingPathComponent("guest-one")),
                  LCContainer(containerURL: root.appendingPathComponent("guest-two"))]
let app = LCAppModel(bundleIdentifier: "test.game", appInfo: LCAppInfo(containers: containers))
func seedRecord() throws {
    let record = LCGameCloudSaves.Record(bookmark: Data([1, 2, 3]), folderName: "Cloud", isOff: false)
    try fm.createDirectory(at: LCGameCloudSaves.directoryURL, withIntermediateDirectories: true)
    try PropertyListEncoder().encode(record).write(to: LCGameCloudSaves.fileURL(forBundleIdentifier: app.bundleIdentifier))
}
for container in containers {
    let prefs = LCGamePrefs(container: container, bundleIdentifier: app.bundleIdentifier)
    require(prefs.setRawValue(Data([1, 2, 3]), forKey: LCGameCloudSaves.guestBookmarkKey), "seed guest bookmark")
    require(prefs.setRawValue("preserved", forKey: "unrelated"), "seed unrelated preference")
}
try seedRecord()
try LCGameCloudSaves.setOff(true, forBundleIdentifier: app.bundleIdentifier)
// Remove immediately, without a launch in between: the reported bug.
try LCGameCloudSaves.removeRecord(for: app)
require(LCGameCloudSaves.record(forBundleIdentifier: app.bundleIdentifier) == nil, "record removed after cleanup")
for container in containers {
    let prefs = LCGamePrefs(container: container, bundleIdentifier: app.bundleIdentifier)
    require(prefs.values[LCGameCloudSaves.guestBookmarkKey] == nil, "all guest bookmarks cleared")
    require(prefs.values["unrelated"] as? String == "preserved", "other preferences preserved")
}
// No GC record means a guest's own cloud configuration remains under its control.
let guestPrefs = LCGamePrefs(container: containers[0], bundleIdentifier: app.bundleIdentifier)
require(guestPrefs.setRawValue(Data([9]), forKey: LCGameCloudSaves.guestBookmarkKey), "seed independent bookmark")
LCGameCloudSaves.syncGuestBookmark(container: containers[0], bundleIdentifier: app.bundleIdentifier)
require(LCGamePrefs(container: containers[0], bundleIdentifier: app.bundleIdentifier).values[LCGameCloudSaves.guestBookmarkKey] as? Data == Data([9]), "unmanaged configuration preserved")
try seedRecord()
let corruptURL = LCGamePrefs(container: containers[1], bundleIdentifier: app.bundleIdentifier).prefsURL
try Data("invalid plist".utf8).write(to: corruptURL)
do {
    try LCGameCloudSaves.removeRecord(for: app)
    preconditionFailure("corrupt guest preferences should prevent record deletion")
} catch {}
require(LCGameCloudSaves.record(forBundleIdentifier: app.bundleIdentifier)?.isOff == true, "failed removal retains disabled ownership")
try require(text(corruptURL) == "invalid plist", "corrupt preferences are never overwritten")
print("Storage regressions passed: atomic replacement, rollback, cloud cleanup, failure recovery")
