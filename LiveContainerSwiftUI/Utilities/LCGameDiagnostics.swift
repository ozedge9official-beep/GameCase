import Foundation

/// A structured report, never a dump of guest preferences, env values, paths
/// or raw logs. Only fixed error categories are derived from the log text.
enum LCGameDiagnostics {
    static func errorCategories(in log: String) -> [String] {
        let text = log.lowercased()
        let patterns: [(String, [String])] = [
            ("cheat_build_mismatch", ["no file for build"]),
            ("cheat_code_page_write", ["signed code pages", "code writes are not possible"]),
            ("cheat_unsupported_opcode", ["unsupported opcode"]),
            ("cheat_malformed_code", ["malformed line", "not whole words"]),
            ("game_files_missing", ["game files not found", "romfs not found"]),
            ("storage_full", ["no space left", "disk full"]),
            ("permission_error", ["permission denied", "operation not permitted"])
        ]
        return patterns.compactMap { key, phrases in phrases.contains(where: text.contains) ? key : nil }
    }

    static func logTail(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(), (try? handle.seek(toOffset: end > 256 * 1024 ? end - 256 * 1024 : 0)) != nil,
              let data = try? handle.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func build(documents: URL?, bundle: URL?, metadata: [String: String]) throws -> Data {
        let builds = bundle.map { LCGameCheats.buildIDs(in: $0) } ?? []
        var report: [String: Any] = [
            "format_version": 1,
            "generated_at": ISO8601DateFormatter().string(from: Date()),
            "metadata": metadata.filter { ["gamecase_version", "game_identifier", "game_version", "os_version"].contains($0.key) },
            "nso_build_ids": builds.sorted(),
            "container_available": documents != nil
        ]
        if let documents {
            let cheats = LCGameCheats.installedFiles(in: documents.appendingPathComponent("cheats"))
            report["cheats_enabled"] = LCGameCheats.isEnabled(in: documents)
            report["cheat_files"] = cheats.map { file -> [String: Any] in
                ["build_id": file.buildID, "entries": file.entries.count,
                 "selected_entries": file.entries.filter { !$0.isMaster && file.isOn($0) }.count,
                 "masters": file.entries.filter(\.isMaster).count,
                 "malformed_entries": file.entries.filter { !$0.invalidLines.isEmpty }.count,
                 "matches_known_program": builds.isEmpty ? NSNull() as Any : builds.contains(file.buildID)]
            }
            let fm = FileManager.default
            report["save_present"] = fm.fileExists(atPath: documents.appendingPathComponent("save").path)
            report["dlc_present"] = fm.fileExists(atPath: documents.appendingPathComponent("aoc").path)
            let imageAttributes = try? fm.attributesOfItem(atPath: documents.appendingPathComponent("romfs.img").path)
            report["romfs_image_bytes"] = imageAttributes?[.size] ?? NSNull()
            report["available_bytes"] = LCStorageCapacity.available(at: documents).map { NSNumber(value: $0) as Any } ?? NSNull()
            report["backup_count"] = (try? LCSaveBackupStore.list(in: documents).count).map { NSNumber(value: $0) as Any } ?? NSNull()
            let logURL = documents.appendingPathComponent("log.txt")
            if let log = logTail(logURL) {
                report["previous_run_error_categories"] = errorCategories(in: log)
                let date = (try? fm.attributesOfItem(atPath: logURL.path)[.modificationDate]) as? Date
                report["previous_run_log_date"] = date.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
            }
        }
        return try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    }
}
