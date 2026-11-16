"""Compile and exercise the actual Foundation cheat store on the macOS CI runner."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as directory:
    build = Path(directory)
    (build / "main.swift").write_text((ROOT / "tests/cheat_regressions.swift").read_text())
    binary = build / "cheat-tests"
    subprocess.run(["swiftc", "-swift-version", "5",
                    str(ROOT / "LiveContainerSwiftUI/Views/AppList/GameSettings/LCGameCheatStore.swift"),
                    str(ROOT / "LiveContainerSwiftUI/Utilities/LCFileReplacement.swift"),
                    str(build / "main.swift"), "-o", str(binary)], check=True)
    subprocess.run([str(binary), str(build / "data")], check=True)
