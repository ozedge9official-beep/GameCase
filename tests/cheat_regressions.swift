import Foundation

let fm = FileManager.default
let root = URL(fileURLWithPath: CommandLine.arguments[1])
try fm.createDirectory(at: root, withIntermediateDirectories: true)
var checks = 0
func check(_ value: @autoclosure () throws -> Bool, _ reason: String) rethrows {
    let result = try value()
    precondition(result, reason)
    checks += 1
}
func write(_ url: URL, _ text: String) throws {
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}
func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
func fails(_ reason: String, _ body: () throws -> Void) {
    do { try body(); preconditionFailure(reason) } catch { checks += 1 }
}

let code = "04000000 00123456 00000008"
let base = "[HP]\n\(code)\n[Money]\n04000000 00234567 00000009\n{Master}\n20000000\n"
let parsed = LCGameCheats.parse(text: base)
check(parsed.entries.map(\.name) == ["HP", "Money", "Master"], "existing ordinary and master entries")
check(parsed.entries[2].isMaster, "master flag")
check(parsed.entries[0].words == ["04000000", "00123456", "00000008"], "words unchanged")
check(LCGameCheats.parse(text: "[credits]\nAuthor: tester\n[--SectionStart:Stats--]\n[HP] \(code)").entries.map(\.name) == ["HP"], "labels are not cheats")
check(LCGameCheats.parse(text: "[HP] \(code)\n[HP]\n\(code)").entries.map(\.key) == ["HP", "HP #2"], "duplicate names remain separately selectable")
let labels = LCGameCheats.parse(text: "[HP]\n[HP]\n\(code)").entries
check(labels.first?.key == "HP #2", "labels consume duplicate ordinals like VM")
check(LCGameCheats.resolvedKeys(entries: labels, lines: ["HP"]) == ["HP #2"], "legacy raw-name fallback")
let repeats = LCGameCheats.parse(text: "[HP]\n\(code)\n[HP]\n\(code)").entries
check(LCGameCheats.resolvedKeys(entries: repeats, lines: ["HP", "HP"]) == ["HP", "HP #2"], "repeated legacy state lines")
check(LCGameCheats.parse(text: "[HP]\n\(code)\n[hp]\n\(code)").entries.map(\.key) == ["HP", "hp"], "case-distinct names are not merged")
let whitespace = LCGameCheats.parse(text: "[ HP ]\n\(code)").entries[0]
check(whitespace.key == " HP ", "spaces inside a header are significant")
let longName = String(repeating: "金", count: 50)
let longEntry = LCGameCheats.parse(text: "[\(longName)]\n\(code)").entries[0]
check(longEntry.name == String(repeating: "金", count: 42), "127-byte UTF-8 boundary")
// The VM repairs a glued header after a complete separate word.
let repaired = LCGameCheats.parse(text: "[HP]\n\(code)[Next]\n20000000")
check(repaired.entries.map(\.name) == ["HP", "Next"], "glued header after a word")
let packed = LCGameCheats.parse(text: "[HP]040000000012345600000008")
check(packed.entries[0].words == parsed.entries[0].words, "packed words and same-line header")
check(packed.text.contains("[HP]\n\(code)"), "canonical text readable by older engines")
check(LCGameCheats.parse(text: packed.text).text == packed.text, "normalization is idempotent")
check(LCGameCheats.parse(text: "[HP]\r\n\(code)\r\n").entries.count == 1, "Windows newline support")
let bad = LCGameCheats.parse(text: "[Bad]\n0400000 00123456\n[Good]\n\(code)")
check(bad.entries.count == 2 && bad.entries[0].invalidLines == [2], "bad hex gets a visible error, siblings preserved")
check(bad.text.contains("0400000 00123456"), "no silent deletion of malformed code")
check(LCGameCheats.parse(text: "[New engine opcode]\nFFF00000").entries.count == 1, "future opcodes not blacklisted by host")
fails("prose is not an executable cheat") { _ = try LCGameCheats.validated(Data("[Credits]\nby author".utf8)) }
fails("empty file") { _ = try LCGameCheats.validated(Data()) }
let bom = Data([0xef, 0xbb, 0xbf]) + Data(base.utf8)
try check(LCGameCheats.validated(bom).entries.count == 3, "UTF-8 BOM header not lost")
let utf16le = Data([0xff, 0xfe]) + base.data(using: .utf16LittleEndian)!
let utf16be = Data([0xfe, 0xff]) + base.data(using: .utf16BigEndian)!
try check(LCGameCheats.validated(utf16le).entries.count == 3, "UTF-16 LE with BOM")
try check(LCGameCheats.validated(utf16be).entries.count == 3, "UTF-16 BE with BOM")
fails("binary NUL rejected") { _ = try LCGameCheats.decode(Data([0, 1, 2])) }
fails("oversized input bounded") { _ = try LCGameCheats.decode(Data(repeating: 65, count: LCGameCheats.maxFileBytes + 1)) }
check(LCGameCheats.isCheatFileName("abcdef0123456789.TXT"), "case-insensitive filename")
check(!LCGameCheats.isCheatFileName("../ABCDEF0123456789.txt"), "reject paths")
check(!LCGameCheats.isCheatFileName("ＡＢＣＤＥＦ0123456789.txt"), "ASCII hex only")

let documents = root.appendingPathComponent("Documents")
let cheats = documents.appendingPathComponent("cheats")
let bid = "ABCDEF0123456789"
try LCGameCheats.importCheatFile(fileName: bid.lowercased() + ".TXT", data: utf16le, into: cheats)
let installed = LCGameCheats.installedFiles(in: cheats)
check(installed.count == 1 && installed[0].entries.count == 3, "normalized imported file")
try check(read(installed[0].fileURL).hasPrefix("[HP]"), "disk format is UTF-8, no BOM")
let snapshot = installed[0]
try LCGameCheats.setEntry(snapshot.entries[0], on: true, file: snapshot)
try LCGameCheats.setEntry(snapshot.entries[1], on: true, file: snapshot)
check(Set(LCGameCheats.readEnabledNames(enabledURL: snapshot.enabledURL)) == ["HP", "Money"], "stale UI snapshot cannot erase another toggle")
try write(snapshot.enabledURL, "HP\nMoney\nFuture setting\n")
try LCGameCheats.setEntry(snapshot.entries[0], on: false, file: snapshot)
check(LCGameCheats.readEnabledNames(enabledURL: snapshot.enabledURL) == ["Money", "Future setting"], "unknown engine selections preserved")
try write(snapshot.enabledURL, "HP\nMoney\nFuture setting\n")
let changed = base.replacingOccurrences(of: "00000008", with: "00000007")
try LCGameCheats.importCheatFile(fileName: bid + ".txt", data: Data(changed.utf8), into: cheats)
check(LCGameCheats.readEnabledNames(enabledURL: snapshot.enabledURL) == ["Money", "Future setting"], "only changed code disabled on replacement")
let backups = try fm.contentsOfDirectory(at: documents.appendingPathComponent("cheat-backups"), includingPropertiesForKeys: nil)
try check(backups.count == 1 && read(backups[0].appendingPathComponent(bid + ".txt")) == LCGameCheats.parse(text: base).text, "original is recoverable")
fails("changed file invalidates stale toggle") { try LCGameCheats.setEntry(snapshot.entries[0], on: true, file: snapshot) }
check(LCGameCheats.cheatsEnvValue(in: documents) == "cheats", "legacy relative cheat directory")
try LCGameCheats.setEnabled(false, in: documents)
check(LCGameCheats.cheatsEnvValue(in: documents) == LCGameCheats.disabledMarker + "/empty", "global off overrides implicit VM fallback")
check(!fm.fileExists(atPath: documents.appendingPathComponent(LCGameCheats.disabledMarker + "/empty/" + bid + ".txt").path), "no master can be loaded under marker file")
try LCGameCheats.setEnabled(true, in: documents)
check(LCGameCheats.cheatsEnvValue(in: documents) == "cheats", "global on restores path")
check(LCGameCheats.readEnabledNames(enabledURL: snapshot.enabledURL) == ["Money", "Future setting"], "global switch retains selections")
try write(cheats.appendingPathComponent("1111111111111111.txt"), "[ HP ]\n\(code)")
let spacedFile = LCGameCheats.installedFiles(in: cheats).first { $0.buildID == "1111111111111111" }!
try LCGameCheats.setEntry(spacedFile.entries[0], on: true, file: spacedFile)
check(LCGameCheats.installedFiles(in: cheats).first { $0.id == spacedFile.id }!.isOn(spacedFile.entries[0]), "spaced name survives state roundtrip")

let bundle = root.appendingPathComponent("Game.app")
try write(bundle.appendingPathComponent("dm/main.fixups.tsv"), "# IMAGE_SIZE\t1234\n# BUILD_ID\tabcdef0123456789aabbccddeeff0011\n")
check(LCGameCheats.buildIDs(in: bundle) == [bid], "read actual NSO Build ID prefix")
try write(bundle.appendingPathComponent("dm/p2/main.fixups.tsv"), "# BUILD_ID\t1111111111111111aabbccddeeff0011\n")
check(LCGameCheats.buildIDs(in: bundle) == [bid, "1111111111111111"], "multi-program build IDs")
check(LCGameCheats.buildIDs(in: root.appendingPathComponent("Unknown.app")).isEmpty, "missing identity remains unknown")
let folder = root.appendingPathComponent("pack")
try write(folder.appendingPathComponent("atmosphere/contents/0100000000000000/cheats/" + bid + ".txt"), base)
try write(folder.appendingPathComponent("atmosphere/contents/0200000000000000/cheats/" + bid + ".txt"), changed)
try check(LCGameCheats.sourceFiles(in: folder, titleID: "0100000000000000").count == 1, "filter another game's title folder")
try check(LCGameCheats.sourceFiles(in: folder, titleID: nil).isEmpty, "unknown title cannot select another game's pack")
try fm.createSymbolicLink(at: folder.appendingPathComponent("link"), withDestinationURL: cheats)
try check(LCGameCheats.sourceFiles(in: folder, titleID: "0100000000000000").count == 1, "do not traverse symlinks")
let p1 = LCGameCheats.ImportPayload(fileName: bid + ".txt", data: Data(base.utf8))
let p2 = LCGameCheats.ImportPayload(fileName: bid.lowercased() + ".TXT", data: Data(changed.utf8))
check(LCGameCheats.uniqueImports([p1, p2]).files.isEmpty, "conflicting batch files do not overwrite one another")
check(LCGameCheats.uniqueImports([p1, p1]).files.count == 1, "identical batch copies deduplicated")
let strayState = cheats.appendingPathComponent("2222222222222222.enabled")
try write(strayState, "HP\n")
try LCGameCheats.importCheatFile(fileName: "2222222222222222.txt", data: Data(base.utf8), into: cheats)
check(LCGameCheats.readEnabledNames(enabledURL: strayState).isEmpty, "stray old selections cannot enable a fresh import")

final class FailingCheatMove: FileManager {
    override func moveItem(at source: URL, to destination: URL) throws {
        if source.deletingLastPathComponent().lastPathComponent.hasPrefix(".staging-") && source.pathExtension == "enabled" {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try super.moveItem(at: source, to: destination)
    }
}
let beforeText = try read(snapshot.fileURL)
let beforeState = try read(snapshot.enabledURL)
fails("state commit failure rolls back text too") {
    try LCGameCheats.importCheatFile(fileName: bid + ".txt", data: Data(base.utf8), into: cheats, FailingCheatMove())
}
try check(read(snapshot.fileURL) == beforeText && read(snapshot.enabledURL) == beforeState, "two-file transaction preserves originals on failure")
let mixed = root.appendingPathComponent("case-sensitive-cheats")
try write(mixed.appendingPathComponent(bid.lowercased() + ".txt"), base)
try write(mixed.appendingPathComponent(bid + ".enabled"), "HP\n")
let lowercaseFile = LCGameCheats.installedFiles(in: mixed)[0]
check(lowercaseFile.isOn(lowercaseFile.entries[0]), "lowercase text uses uppercase engine state path")
try write(mixed.appendingPathComponent(bid + ".TXT"), changed)
if try fm.contentsOfDirectory(atPath: mixed.path).filter({ LCGameCheats.isCheatFileName($0) }).count == 2 {
    fails("ambiguous installed builds cannot be overwritten arbitrarily") {
        try LCGameCheats.importCheatFile(fileName: bid + ".txt", data: Data(base.utf8), into: mixed)
    }
    try LCGameCheats.delete(file: lowercaseFile)
    check(LCGameCheats.readEnabledNames(enabledURL: lowercaseFile.enabledURL) == ["HP"], "deleting one case variant preserves shared state")
}
print("Cheat regressions passed: \(checks) checks")
