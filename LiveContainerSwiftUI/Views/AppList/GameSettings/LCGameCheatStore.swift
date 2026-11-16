import Foundation

enum LCGameCheatError: Error {
    case invalidFileName, invalidContent, tooLarge, ambiguousBuild, staleFile
}

/// File-format support only. The VM lives in each imported game IPA.
/// See docs/cheats.md for the engine contract and compatibility limits.
enum LCGameCheats {
    static let envKey = "DM_CHEATS"
    static let envValue = "cheats"
    static let maxFileBytes = 4 * 1024 * 1024
    static let disabledMarker = ".gamecase-cheats-disabled"

    struct CheatEntry: Identifiable {
        let name: String
        let isMaster: Bool
        let key: String
        let ordinal: Int
        let words: [String]
        let invalidLines: [Int]
        var id: Int { ordinal }
    }

    struct ParsedFile {
        let text: String
        let entries: [CheatEntry]
        let headerCount: Int
    }

    struct ImportPayload {
        let fileName: String
        let data: Data
    }

    /// Folder imports flatten Atmosphere trees into this container's cheats
    /// directory. A title ID in a contents/<title>/cheats path must match.
    static func sourceFiles(in folder: URL, titleID: String?, _ fm: FileManager = .default) throws -> [URL] {
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                                            options: [.skipsHiddenFiles]) else { throw LCGameCheatError.invalidContent }
        var result: [URL] = []
        var count = 0
        for case let url as URL in enumerator {
            count += 1
            guard count <= 10000 else { throw LCGameCheatError.tooLarge }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isRegularFile == true, isCheatFileName(url.lastPathComponent) else { continue }
            let parts = url.pathComponents
            var allowed = true
            for i in parts.indices where parts[i].lowercased() == "contents" && i + 2 < parts.count && parts[i + 2].lowercased() == "cheats" {
                let pathTitle = parts[i + 1]
                if pathTitle.count == 16 && isHex(pathTitle) {
                    allowed = titleID.map { pathTitle.uppercased() == $0.uppercased() } ?? false
                }
            }
            if allowed { result.append(url) }
        }
        return result.sorted { $0.path < $1.path }
    }

    /// Never let directory order decide which of two different files for the
    /// same build wins. Identical copies are harmless and imported once.
    static func uniqueImports(_ payloads: [ImportPayload]) -> (files: [ImportPayload], conflicts: [String]) {
        let groups = Dictionary(grouping: payloads) { normalizedFileName($0.fileName) }
        var files: [ImportPayload] = []
        var conflicts: [String] = []
        for name in groups.keys.sorted() {
            let group = groups[name]!
            if group.dropFirst().contains(where: { $0.data != group[0].data }) { conflicts.append(name) }
            else { files.append(group[0]) }
        }
        return (files, conflicts)
    }

    struct CheatFile: Identifiable {
        let buildID: String
        let fileURL: URL
        let entries: [CheatEntry]
        let enabledNames: Set<String>
        let headerCount: Int
        var enabledURL: URL {
            // The engine constructs this path from its uppercase Build ID,
            // even when the .txt filename is lowercase.
            fileURL.deletingLastPathComponent().appendingPathComponent(buildID + ".enabled")
        }
        var id: String { fileURL.path }
        func isOn(_ entry: CheatEntry) -> Bool {
            entry.isMaster || enabledNames.contains(entry.key)
        }
    }

    static func isHex(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }

    static func isCheatFileName(_ name: String) -> Bool {
        guard !name.contains("/"), !name.contains("\\") else { return false }
        let url = URL(fileURLWithPath: name)
        let stem = url.deletingPathExtension().lastPathComponent
        return url.pathExtension.lowercased() == "txt" && stem.utf8.count == 16 && isHex(stem)
    }

    static func normalizedFileName(_ name: String) -> String {
        URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent.uppercased() + ".txt"
    }

    static func decode(_ data: Data) throws -> String {
        guard data.count <= maxFileBytes else { throw LCGameCheatError.tooLarge }
        let encoding: String.Encoding
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) {
            encoding = .utf16
        } else {
            encoding = .utf8
        }
        guard var text = String(data: data, encoding: encoding), !text.contains("\0") else {
            throw LCGameCheatError.invalidContent
        }
        if text.hasPrefix("\u{feff}") { text.removeFirst() }
        return text
    }

    /// Bound reads before allocating; Files providers may report inaccurate sizes.
    static func readData(at url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxFileBytes + 1) ?? Data()
        guard data.count <= maxFileBytes else { throw LCGameCheatError.tooLarge }
        return data
    }

    private static func engineName(_ name: String) -> String {
        // char name[128], truncated at a UTF-8 boundary by the guest engine.
        var result = ""
        for scalar in name.unicodeScalars {
            guard result.utf8.count + scalar.utf8.count <= 127 else { break }
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    static func parseEntries(text: String) -> [CheatEntry] { parse(text: text).entries }

    /// Normalize formatting, never addresses, values, opcodes or header names.
    /// Retain malformed lines for diagnosis instead of silently deleting code.
    static func parse(text: String) -> ParsedFile {
        var input = text
        if input.hasPrefix("\u{feff}") { input.removeFirst() }
        input = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        // Match the VM's repair for a header glued to a complete code word.
        input = input.replacingOccurrences(of: "(?m)(?<![^ \\t\\n])([0-9A-Fa-f]{8})(?=[\\[{])", with: "$1\n", options: .regularExpression)
        var output: [String] = []
        var entries: [CheatEntry] = []
        var counts: [String: Int] = [:]
        var pending: (name: String, master: Bool, key: String, ordinal: Int)?
        var words: [String] = []
        var invalid: [Int] = []
        var headers = 0
        func flush() {
            if let p = pending, !words.isEmpty || !invalid.isEmpty {
                entries.append(CheatEntry(name: p.name, isMaster: p.master, key: p.key,
                                          ordinal: p.ordinal, words: words, invalidLines: invalid))
            }
            words = []; invalid = []
        }
        for (index, raw) in input.components(separatedBy: "\n").enumerated() {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if let first = line.first, first == "[" || first == "{" {
                flush()
                pending = nil
                if let end = line.firstIndex(of: first == "[" ? "]" : "}"), end > line.index(after: line.startIndex) {
                    let rawName = String(line[line.index(after: line.startIndex)..<end])
                    let name = engineName(rawName)
                    let occurrence = (counts[name] ?? 0) + 1
                    counts[name] = occurrence
                    headers += 1
                    pending = (name, first == "{", occurrence == 1 ? name : name + " #\(occurrence)", headers)
                    output.append(String(line[...end]))
                    line = String(line[line.index(after: end)...]).trimmingCharacters(in: .whitespaces)
                }
            }
            let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if !tokens.isEmpty && tokens.allSatisfy({ isHex($0) && $0.utf8.count % 8 == 0 }) {
                let pieces = tokens.flatMap { token -> [String] in
                    let bytes = Array(token.utf8)
                    return stride(from: 0, to: bytes.count, by: 8).map {
                        String(decoding: bytes[$0..<$0 + 8], as: UTF8.self).uppercased()
                    }
                }
                if pending != nil { words.append(contentsOf: pieces) }
                output.append(pieces.joined(separator: " "))
            } else if !line.isEmpty {
                // Pure prose is ignored by the VM. A hex token beside prose,
                // or a short hex token, makes the entry malformed.
                if pending != nil && tokens.contains(where: { isHex($0) }) { invalid.append(index + 1) }
                output.append(line)
            }
        }
        flush()
        return ParsedFile(text: output.joined(separator: "\n") + "\n", entries: entries, headerCount: headers)
    }

    static func validated(_ data: Data) throws -> ParsedFile {
        let parsed = parse(text: try decode(data))
        guard parsed.entries.contains(where: { !$0.words.isEmpty }) else { throw LCGameCheatError.invalidContent }
        guard parsed.text.utf8.count <= maxFileBytes else { throw LCGameCheatError.tooLarge }
        return parsed
    }

    static func readEnabledNames(enabledURL: URL) -> [String] {
        guard let text = try? String(contentsOf: enabledURL, encoding: .utf8) else { return [] }
        // Spaces and case are part of the engine's exact state key.
        return text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }.filter { !$0.isEmpty }
    }

    /// Mirror states_read's exact key lookup, then its legacy repeated-name
    /// fallback. Labels and masters consume duplicate ordinals but no state.
    static func resolvedKeys(entries: [CheatEntry], lines: [String]) -> Set<String> {
        var enabled = Set<String>()
        for line in lines {
            let available = entries.filter { !$0.isMaster && !enabled.contains($0.key) }
            if let entry = available.first(where: { $0.key == line }) ?? available.first(where: { $0.name == line }) {
                enabled.insert(entry.key)
            }
        }
        return enabled
    }

    static func installedFiles(in cheatsDir: URL, _ fm: FileManager = .default) -> [CheatFile] {
        let names = ((try? fm.contentsOfDirectory(atPath: cheatsDir.path)) ?? []).filter(isCheatFileName).sorted()
        return names.map { name in
            let url = cheatsDir.appendingPathComponent(name)
            let build = String(normalizedFileName(name).dropLast(4))
            let parsed = (try? readData(at: url)).flatMap { try? decode($0) }.map { parse(text: $0) }
            let entries = parsed?.entries ?? []
            return CheatFile(buildID: build, fileURL: url, entries: entries,
                             enabledNames: resolvedKeys(entries: entries, lines: readEnabledNames(enabledURL: cheatsDir.appendingPathComponent(build + ".enabled"))),
                             headerCount: parsed?.headerCount ?? 0)
        }
    }

    static func isEnabled(in documents: URL, _ fm: FileManager = .default) -> Bool {
        !fm.fileExists(atPath: documents.appendingPathComponent(disabledMarker).path)
    }

    static func setEnabled(_ enabled: Bool, in documents: URL, _ fm: FileManager = .default) throws {
        let marker = documents.appendingPathComponent(disabledMarker)
        if enabled {
            if fm.fileExists(atPath: marker.path) { try fm.removeItem(at: marker) }
        } else {
            try fm.createDirectory(at: documents, withIntermediateDirectories: true)
            try Data().write(to: marker, options: .atomic)
        }
    }

    static func cheatsEnvValue(in documents: URL, _ fm: FileManager = .default) -> String? {
        if !isEnabled(in: documents, fm) {
            // Marker is a regular file. Nothing below it can be loaded, even
            // by older VMs or a VM that defaults to bundled master cheats.
            return disabledMarker + "/empty"
        }
        let names = (try? fm.contentsOfDirectory(atPath: documents.appendingPathComponent("cheats").path)) ?? []
        return names.contains(where: isCheatFileName) ? envValue : nil
    }

    @discardableResult
    static func setEntry(_ entry: CheatEntry, on: Bool, file: CheatFile, _ fm: FileManager = .default) throws -> CheatFile {
        guard !entry.isMaster else { return file }
        let parsed = parse(text: try decode(readData(at: file.fileURL)))
        let current = parsed.entries
        guard current.contains(where: { $0.key == entry.key && $0.words == entry.words && $0.ordinal == entry.ordinal }) else {
            throw LCGameCheatError.staleFile
        }
        // Read current state rather than a captured SwiftUI snapshot; retain
        // unknown keys used by newer VMs and the game's own settings.
        let previous = readEnabledNames(enabledURL: file.enabledURL)
        var keys = resolvedKeys(entries: current, lines: previous)
        if on { keys.insert(entry.key) } else { keys.remove(entry.key) }
        let known = Set(current.flatMap { [$0.key, $0.name] })
        let lines = current.filter { !$0.isMaster && keys.contains($0.key) }.map(\.key) + previous.filter { !known.contains($0) }
        try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n")
            .write(to: file.enabledURL, atomically: true, encoding: .utf8)
        return CheatFile(buildID: file.buildID, fileURL: file.fileURL, entries: current,
                         enabledNames: resolvedKeys(entries: current, lines: lines), headerCount: parsed.headerCount)
    }

    @discardableResult
    static func importCheatFile(fileName: String, data: Data, into cheatsDir: URL, _ fm: FileManager = .default) throws -> String {
        guard isCheatFileName(fileName) else { throw LCGameCheatError.invalidFileName }
        let parsed = try validated(data)
        let normalized = normalizedFileName(fileName)
        let build = String(normalized.dropLast(4))
        try fm.createDirectory(at: cheatsDir, withIntermediateDirectories: true)
        let existing = installedFiles(in: cheatsDir, fm).filter { $0.buildID == build }
        guard existing.count <= 1 else { throw LCGameCheatError.ambiguousBuild }
        let destination = existing.first?.fileURL ?? cheatsDir.appendingPathComponent(normalized)
        let stateName = build + ".enabled"
        let stateURL = cheatsDir.appendingPathComponent(stateName)
        let staging = cheatsDir.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        try Data(parsed.text.utf8).write(to: staging.appendingPathComponent(destination.lastPathComponent))
        var names = [destination.lastPathComponent]
        if let old = existing.first {
            // Keep a recoverable original before replacement. Changed code
            // under an old name must be explicitly enabled again.
            let backup = cheatsDir.deletingLastPathComponent().appendingPathComponent("cheat-backups/\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: backup, withIntermediateDirectories: true)
            try fm.copyItem(at: old.fileURL, to: backup.appendingPathComponent(old.fileURL.lastPathComponent))
            if fm.fileExists(atPath: stateURL.path) { try fm.copyItem(at: stateURL, to: backup.appendingPathComponent(stateName)) }
            let previous = readEnabledNames(enabledURL: stateURL)
            let known = Set(old.entries.flatMap { [$0.key, $0.name] })
            let keys = resolvedKeys(entries: old.entries, lines: previous)
            let canonical = old.entries.filter { !$0.isMaster && keys.contains($0.key) }.map(\.key) + previous.filter { !known.contains($0) }
            let kept = canonical.filter { key in
                guard let next = parsed.entries.first(where: { $0.key == key }) else { return true }
                return old.entries.contains { $0.key == key && $0.words == next.words && $0.invalidLines.isEmpty && next.invalidLines.isEmpty }
            }
            try (kept.isEmpty ? "" : kept.joined(separator: "\n") + "\n")
                .write(to: staging.appendingPathComponent(stateName), atomically: true, encoding: .utf8)
            names.append(stateName)
        } else {
            // A stray state file from a previously deleted import must not
            // silently enable this new file. Preserve it for recovery first.
            if fm.fileExists(atPath: stateURL.path) {
                let backup = cheatsDir.deletingLastPathComponent().appendingPathComponent("cheat-backups/\(UUID().uuidString)", isDirectory: true)
                try fm.createDirectory(at: backup, withIntermediateDirectories: true)
                try fm.copyItem(at: stateURL, to: backup.appendingPathComponent(stateName))
            }
            try Data().write(to: staging.appendingPathComponent(stateName))
            names.append(stateName)
        }
        try LCFileReplacement.commitDirectory(staging, to: cheatsDir, names: names, fileManager: fm)
        return build
    }

    static func delete(file: CheatFile, _ fm: FileManager = .default) throws {
        try fm.removeItem(at: file.fileURL)
        let remaining = (try fm.contentsOfDirectory(atPath: file.fileURL.deletingLastPathComponent().path))
            .contains { isCheatFileName($0) && normalizedFileName($0) == file.buildID + ".txt" }
        // Case variants share the engine's uppercase state path. Removing one
        // duplicate must not reset the surviving file's choices.
        if !remaining && fm.fileExists(atPath: file.enabledURL.path) { try fm.removeItem(at: file.enabledURL) }
    }

    /// NSO Build ID, not a Mach-O UUID, title ID or iOS app version.
    /// Multiple programs may use different main NSOs; show every known ID.
    static func buildIDs(in bundle: URL, _ fm: FileManager = .default) -> Set<String> {
        let dm = bundle.appendingPathComponent("dm", isDirectory: true)
        var candidates = [dm.appendingPathComponent("main.fixups.tsv")]
        let children = (try? fm.contentsOfDirectory(at: dm, includingPropertiesForKeys: nil)) ?? []
        for child in children where child.lastPathComponent.hasPrefix("p") && child.lastPathComponent.dropFirst().allSatisfy({ $0.isNumber }) {
            candidates.append(child.appendingPathComponent("main.fixups.tsv"))
        }
        var result = Set<String>()
        for url in candidates {
            // Rewriter metadata can be large; BUILD_ID is in its header.
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: 64 * 1024), let text = String(data: data, encoding: .utf8) else { continue }
            for line in text.components(separatedBy: "\n") {
                let fields = line.split(whereSeparator: { $0.isWhitespace })
                if fields.count == 3, fields[0] == "#", fields[1] == "BUILD_ID" {
                    let id = String(fields[2])
                    if id.count >= 16 && isHex(id) && id.contains(where: { $0 != "0" }) { result.insert(String(id.prefix(16)).uppercased()) }
                }
            }
        }
        return result
    }
}
