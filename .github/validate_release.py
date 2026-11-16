"""Fail publication if licenses or corresponding build materials are missing."""
import hashlib
import json
from pathlib import Path
import plistlib
import tarfile
import zipfile


def validate(directory, version, expected_tree):
    directory = Path(directory)
    with zipfile.ZipFile(directory / "GameCase.ipa") as ipa:
        assert ipa.testzip() is None, "Corrupt IPA"
        base = "Payload/LiveContainer.app/"
        info = plistlib.loads(ipa.read(base + "Info.plist"))
        assert info["CFBundleShortVersionString"] == version
        assert info["CFBundleVersion"] == version
        assert info["CFBundleIdentifier"] == "com.tiaoge.gamecase"
        assert not any("SideStoreApp.framework" in n or "SideStoreSupport.framework" in n for n in ipa.namelist())
        assert not any("cover-010013C00E930000.jpg" in n or "cover-0100A00019DE0000.jpg" in n for n in ipa.namelist())
        legal = base + "GameCaseLegal/"
        manifest = json.loads(ipa.read(legal + "index.json"))
        assert manifest["version"] == version and manifest["sourceTree"] == expected_tree
        for entry in manifest["entries"]:
            assert ipa.read(legal + entry["file"]), "Empty notice"
        assert ipa.read(legal + manifest["entries"][0]["file"]) == (directory / "LICENSE").read_bytes()
    with tarfile.open(directory / "GameCase-source.tar.gz", "r:gz") as source:
        prefix = "GameCase-source/"
        manifest = json.load(source.extractfile(prefix + "SOURCE-MANIFEST.json"))
        assert manifest["version"] == version and manifest["sourceTree"] == expected_tree
        assert source.extractfile(prefix + "LICENSE").read() == (directory / "LICENSE").read_bytes()
        assert source.getmember(prefix + "litehook/src/litehook.c").size > 0
        assert source.getmember(prefix + "OpenSSL/scripts/build.sh").size > 0
        openssl = source.extractfile(prefix + "OpenSSL/openssl-3.3.3.tar.gz").read()
        assert hashlib.sha256(openssl).hexdigest() == manifest["opensslSourceSHA256"]
        assert source.getmember(prefix + "docs/BUILDING.md").size > 0
    assets = ["GameCase.ipa", "GameCase-source.tar.gz", "LICENSE", "THIRD_PARTY_NOTICES.md"]
    (directory / "SHA256SUMS").write_text("".join(
        hashlib.sha256((directory / name).read_bytes()).hexdigest() + "  " + name + "\n" for name in assets))


if __name__ == "__main__":
    import os
    import subprocess
    tree = subprocess.check_output(["git", "rev-parse", os.environ["TARGET_SHA"] + "^{tree}"], text=True).strip()
    validate(Path.cwd(), os.environ["TAG"][1:], tree)
