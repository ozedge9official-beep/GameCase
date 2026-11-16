"""Compile the production storage backends with small macOS model stand-ins."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory() as directory:
    build = Path(directory)
    cloud = (ROOT / "LiveContainerSwiftUI/Views/AppList/GameSettings/LCGameCloudSaves.swift").read_text()
    cloud = cloud[cloud.index("enum LCGameCloudSaves {"):cloud.index("// MARK: - 设置页")]
    prefs = (ROOT / "LiveContainerSwiftUI/Views/AppList/GameSettings/LCGameProfile.swift").read_text()
    prefs = prefs[prefs.index("final class LCGamePrefs {"):]
    saves = (ROOT / "LiveContainerSwiftUI/Views/AppList/GameSettings/LCSaveDataTransfer.swift").read_text()
    saves = saves[saves.index("enum LCSaveDataError:"):saves.index("/// 每游戏设置页")]
    support = '''import Foundation
struct LCContainer { let containerURL: URL }
struct LCAppInfo { let containers: [LCContainer] }
struct LCAppModel { let bundleIdentifier: String; let appInfo: LCAppInfo }
struct LCLauncherSetting {
    let env: String
    func isDefault(_ value: String) -> Bool { value == "default" }
}
extension LCContainer {
    static func sanitizedFolderBase(_ name: String, fallback: String) -> String { name }
}
extension LCAppModel { var displayName: String { bundleIdentifier } }
enum LCUtils { static func zipData(forDirectory url: URL) -> Data? { nil } }
enum LCGameLibraryInfo {
    static func defaultContainer(for app: LCAppModel) -> LCContainer? { app.appInfo.containers.first }
}
enum LCDatapackImportView {
    static func topEntries(of url: URL) -> (files: [URL], directories: [URL]) {
        let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return (children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true },
                children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
    }
    static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
    static func chunkedCopyFile(from: URL, to: URL, isCancelled: () -> Bool, onProgress: (Int64) async -> Void) async throws -> Int64 {
        try await LCFileCopy.copy(from: from, to: to, isCancelled: isCancelled, onProgress: onProgress)
    }
}
enum LCPath { static let docPath = URL(fileURLWithPath: CommandLine.arguments[1]) }
'''
    (build / "Support.swift").write_text(support + cloud + prefs + saves)
    (build / "main.swift").write_text((ROOT / "tests/storage_regressions.swift").read_text() + "\n" + (ROOT / "tests/reliability_regressions.swift").read_text())
    binary = build / "storage-tests"
    subprocess.run(["swiftc", "-swift-version", "5", str(build / "Support.swift"),
                    str(ROOT / "LiveContainerSwiftUI/Utilities/LCFileReplacement.swift"),
                    *[str(ROOT / "LiveContainerSwiftUI/Utilities" / (name + ".swift")) for name in
                      ["LCRecoverableFileWriter", "LCFileTree", "LCFileCopy", "LCFileValueCache", "LCAppInstallTransaction"]],
                    str(build / "main.swift"), "-o", str(binary)], check=True)
    subprocess.run([str(binary), str(build / "data")], check=True)
