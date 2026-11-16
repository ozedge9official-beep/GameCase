"""Stage unmodified license texts before Xcode signs the application."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "https://github.com/ozedge9official-beep/GameCase"


def stage(destination, root=ROOT):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    info = plistlib.loads((root / "LiveContainer/Info.plist").read_bytes())
    version = info["CFBundleShortVersionString"]
    entries = []
    files = [("GameCase / LiveContainer — GNU AGPL v3", root / "LICENSE"),
             ("第三方归属索引", root / "THIRD_PARTY_NOTICES.md"),
             ("修改说明", root / f"docs/releases/v{version}.md"),
             ("构建与安装说明", root / "docs/BUILDING.md"),
             ("ElleKit — BSD", root / "Resources/Frameworks/CydiaSubstrate.framework/LICENSE")]
    files += [(p.stem, p) for p in sorted((root / "docs/licenses").glob("*.txt"))]
    for index, (title, source) in enumerate(files):
        name = f"{index:02d}-{source.name}.txt"
        shutil.copyfile(source, destination / name)
        entries.append({"title": title, "file": name})
    # Include exact copyright notices from both shipped libarchive headers.
    for header in ["archive.h", "archive_entry.h"]:
        data = (root / "LiveContainerSwiftUI/Utilities" / header).read_bytes()
        name = header + ".txt"
        (destination / name).write_bytes(data[:data.index(b"*/") + 2] + b"\n")
        entries.append({"title": "libarchive — " + header, "file": name})
    source_manifest = root / "SOURCE-MANIFEST.json"
    if source_manifest.is_file():
        # A published source archive has no .git directory.
        source_info = json.loads(source_manifest.read_text())
        if source_info["version"] != version:
            raise ValueError("Source manifest version does not match Info.plist")
        tree = source_info["sourceTree"]
    else:
        tree = subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=root, text=True).strip()
    manifest = {"version": version, "sourceTree": tree,
                "sourceURL": f"{REPOSITORY}/releases/download/v{version}/GameCase-source.tar.gz",
                "repositoryURL": REPOSITORY, "entries": entries}
    (destination / "index.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    stage(parser.parse_args().destination)
