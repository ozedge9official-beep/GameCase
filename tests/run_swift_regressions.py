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
    support = '''import Foundation
struct LCContainer { let containerURL: URL }
struct LCAppInfo { let containers: [LCContainer] }
struct LCAppModel { let bundleIdentifier: String; let appInfo: LCAppInfo }
struct LCLauncherSetting {
    let env: String
    func isDefault(_ value: String) -> Bool { value == "default" }
}
enum LCPath { static let docPath = URL(fileURLWithPath: CommandLine.arguments[1]) }
'''
    (build / "Support.swift").write_text(support + cloud + prefs)
    (build / "main.swift").write_text((ROOT / "tests/storage_regressions.swift").read_text())
    binary = build / "storage-tests"
    subprocess.run(["swiftc", "-swift-version", "5", str(build / "Support.swift"),
                    str(ROOT / "LiveContainerSwiftUI/Utilities/LCFileReplacement.swift"),
                    str(build / "main.swift"), "-o", str(binary)], check=True)
    subprocess.run([str(binary), str(build / "data")], check=True)
