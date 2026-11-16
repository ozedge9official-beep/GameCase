var backupChecks = 0
func checkBackup(_ condition: @autoclosure () throws -> Bool, _ reason: String) rethrows {
    let result = try condition()
    precondition(result, reason)
    backupChecks += 1
}
func backupFailure(_ reason: String, _ action: () throws -> Void) {
    do { try action(); preconditionFailure(reason) } catch { backupChecks += 1 }
}

let backupSuite = root.appendingPathComponent("backup-suite")
let liveSave = backupSuite.appendingPathComponent("save")
try file(liveSave.appendingPathComponent("nested/slot"), "first")
try fm.createDirectory(at: liveSave.appendingPathComponent("empty"), withIntermediateDirectories: true)
let firstBackup = try await LCSaveBackupStore.create(of: liveSave, in: backupSuite)!
try checkBackup(LCSaveBackupStore.list(in: backupSuite).count == 1, "completed backup listed")
try fm.createDirectory(at: LCSaveBackupStore.root(in: backupSuite).appendingPathComponent(".pending-incomplete"), withIntermediateDirectories: true)
try checkBackup(LCSaveBackupStore.list(in: backupSuite).count == 1, "pending backup hidden")
try file(liveSave.appendingPathComponent("nested/slot"), "second")
try file(liveSave.appendingPathComponent("extra"), "keep in safety backup")
let safetyBackup = try await LCSaveBackupStore.restore(firstBackup, in: backupSuite)!
try checkBackup(text(liveSave.appendingPathComponent("nested/slot")) == "first", "selected backup restored")
try checkBackup(text(safetyBackup.appendingPathComponent("nested/slot")) == "second", "pre-restore state backed up")
try checkBackup(text(safetyBackup.appendingPathComponent("extra")) == "keep in safety backup", "safety backup complete")
checkBackup(!fm.fileExists(atPath: liveSave.appendingPathComponent("extra").path), "restore replaces the entire set")
checkBackup(fm.fileExists(atPath: liveSave.appendingPathComponent("empty").path), "restore preserves empty directories")
try checkBackup(text(firstBackup.appendingPathComponent("nested/slot")) == "first", "source backup preserved")
try fm.removeItem(at: liveSave)
let missingSafety = try await LCSaveBackupStore.restore(firstBackup, in: backupSuite)
checkBackup(missingSafety == nil, "missing current save can be recovered")
try checkBackup(text(liveSave.appendingPathComponent("nested/slot")) == "first", "missing save recreated")
let shaped = LCSaveBackupStore.root(in: backupSuite).appendingPathComponent("manual-shaped")
try file(shaped.appendingPathComponent("save/inside"), "exact root")
_ = try await LCSaveBackupStore.restore(shaped, in: backupSuite)
try checkBackup(text(liveSave.appendingPathComponent("save/inside")) == "exact root", "backup restore never strips a legitimate nested save folder")
final class FailedBackupCommit: FileManager {
    override func moveItem(at source: URL, to destination: URL) throws {
        if source.deletingLastPathComponent().lastPathComponent.hasPrefix(".restore-") {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try super.moveItem(at: source, to: destination)
    }
}
do {
    try await LCSaveBackupStore.restore(firstBackup, in: backupSuite, fm: FailedBackupCommit())
    preconditionFailure("failed restore commit must roll back")
} catch { backupChecks += 1 }
try checkBackup(text(liveSave.appendingPathComponent("save/inside")) == "exact root", "failed restore retains current save")
try checkBackup(text(firstBackup.appendingPathComponent("nested/slot")) == "first", "failed restore retains selected backup")
let outside = root.appendingPathComponent("not-a-backup")
try fm.createDirectory(at: outside, withIntermediateDirectories: true)
backupFailure("cannot delete outside backup root") { try LCSaveBackupStore.delete(outside, in: backupSuite) }
let linked = LCSaveBackupStore.root(in: backupSuite).appendingPathComponent("linked")
try fm.createSymbolicLink(at: linked, withDestinationURL: outside)
backupFailure("cannot restore a linked backup") { try LCSaveBackupStore.validate(linked, in: backupSuite) }
try checkBackup(!LCSaveBackupStore.list(in: backupSuite).contains(where: { $0.id == "linked" }), "linked backups excluded")
let countBeforeDelete = try LCSaveBackupStore.list(in: backupSuite).count
try LCSaveBackupStore.delete(firstBackup, in: backupSuite)
try checkBackup(LCSaveBackupStore.list(in: backupSuite).count == countBeforeDelete - 1, "only selected backup deleted")
try checkBackup(text(liveSave.appendingPathComponent("save/inside")) == "exact root", "backup deletion does not change current save")
let redirected = root.appendingPathComponent("redirected-documents")
try fm.createDirectory(at: redirected, withIntermediateDirectories: true)
try fm.createSymbolicLink(at: LCSaveBackupStore.root(in: redirected), withDestinationURL: outside)
backupFailure("backup root cannot redirect to another directory") { _ = try LCSaveBackupStore.list(in: redirected) }

let needed = try LCStorageCapacity.required(for: [100, 200])
checkBackup(needed > 300, "capacity includes temporary overhead")
try LCStorageCapacity.check(sizes: [100, 200], at: root, capacity: { _ in needed })
do {
    try LCStorageCapacity.check(sizes: [100, 200], at: root, capacity: { _ in needed - 1 })
    preconditionFailure("insufficient capacity must stop before copying")
} catch LCStorageError.insufficientSpace(let required, let available) {
    checkBackup(required == needed && available == needed - 1, "capacity error reports required and available bytes")
}
try LCStorageCapacity.check(sizes: [100], at: root, capacity: { _ in nil })
backupFailure("negative sizes rejected") { _ = try LCStorageCapacity.required(for: [-1]) }
backupFailure("overflow rejected") { _ = try LCStorageCapacity.required(for: [Int64.max, 1]) }

let diagnosticDocs = root.appendingPathComponent("diagnostic-documents")
try file(diagnosticDocs.appendingPathComponent("log.txt"), "boot: API_TOKEN=private-secret\ncheats: no file for build ABCDEF0123456789\ncheat: unsupported opcode C4\nPermission denied: /private/user/secret-save\n")
let data = try LCGameDiagnostics.build(documents: diagnosticDocs, bundle: nil,
                                       metadata: ["gamecase_version": "test", "game_identifier": "test.game", "token": "private-secret"])
let reportText = String(decoding: data, as: UTF8.self)
checkBackup(!reportText.contains("private-secret") && !reportText.contains("/private/user"), "diagnostics never copy raw logs or unapproved metadata")
let report = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let categories = report["previous_run_error_categories"] as! [String]
checkBackup(categories.contains("cheat_build_mismatch") && categories.contains("cheat_unsupported_opcode") && categories.contains("permission_error"), "diagnostics preserve fixed failure categories")
checkBackup((report["nso_build_ids"] as! [String]).isEmpty, "unknown game build stays unknown")
let noContainer = try LCGameDiagnostics.build(documents: nil, bundle: nil, metadata: [:])
let noContainerReport = try JSONSerialization.jsonObject(with: noContainer) as! [String: Any]
checkBackup(noContainerReport["container_available"] as? Bool == false, "diagnostics work without a container")
print("Backup/capacity/diagnostic regressions passed: \(backupChecks) checks")
