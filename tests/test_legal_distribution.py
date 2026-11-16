"""Exercise actual notice staging and release validation failure paths."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import shutil
import tarfile
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / ".github" / (name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class LegalDistributionTests(unittest.TestCase):
    def test_staged_notices_preserve_full_texts(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = module("package_legal").stage(directory)
            entries = manifest["entries"]
            self.assertEqual((Path(directory) / entries[0]["file"]).read_bytes(), (ROOT / "LICENSE").read_bytes())
            for source in (ROOT / "docs/licenses").glob("*.txt"):
                matches = [entry for entry in entries if source.name in entry["file"]]
                self.assertEqual(len(matches), 1)
                self.assertEqual((Path(directory) / matches[0]["file"]).read_bytes(), source.read_bytes())
            self.assertEqual(len(manifest["sourceTree"]), 40)
            self.assertIn("/releases/download/v" + manifest["version"], manifest["sourceURL"])

    def test_source_archive_build_needs_no_git_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "source"
            for name in ["LICENSE", "THIRD_PARTY_NOTICES.md", "docs", "LiveContainer/Info.plist",
                         "Resources/Frameworks/CydiaSubstrate.framework/LICENSE",
                         "LiveContainerSwiftUI/Utilities/archive.h", "LiveContainerSwiftUI/Utilities/archive_entry.h"]:
                original = ROOT / name
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                if original.is_dir():
                    shutil.copytree(original, target)
                else:
                    shutil.copyfile(original, target)
            version = plistlib.loads((root / "LiveContainer/Info.plist").read_bytes())["CFBundleShortVersionString"]
            (root / "SOURCE-MANIFEST.json").write_text(json.dumps({"version": version, "sourceTree": "a" * 40}))
            manifest = module("package_legal").stage(Path(directory) / "notices", root=root)
            self.assertEqual(manifest["sourceTree"], "a" * 40)

    def fixture(self, root, missing_notice=False, wrong_tree=False):
        legal = root / "legal"
        manifest = module("package_legal").stage(legal)
        version, tree = manifest["version"], manifest["sourceTree"]
        info = {"CFBundleShortVersionString": version, "CFBundleVersion": version,
                "CFBundleIdentifier": "com.tiaoge.gamecase"}
        with zipfile.ZipFile(root / "GameCase.ipa", "w") as ipa:
            base = "Payload/LiveContainer.app/"
            ipa.writestr(base + "Info.plist", plistlib.dumps(info))
            for file in legal.iterdir():
                if missing_notice and file.name == manifest["entries"][0]["file"]:
                    continue
                ipa.write(file, base + "GameCaseLegal/" + file.name)
        fake_ssl = b"fixture OpenSSL source"
        source_manifest = {"version": version, "sourceTree": "0" * 40 if wrong_tree else tree,
                           "opensslSourceSHA256": hashlib.sha256(fake_ssl).hexdigest()}
        files = {"SOURCE-MANIFEST.json": json.dumps(source_manifest).encode(),
                 "LICENSE": (ROOT / "LICENSE").read_bytes(), "litehook/src/litehook.c": b"fixture",
                 "OpenSSL/scripts/build.sh": b"fixture", "OpenSSL/openssl-3.3.3.tar.gz": fake_ssl,
                 "docs/BUILDING.md": b"fixture instructions"}
        with tarfile.open(root / "GameCase-source.tar.gz", "w:gz") as archive:
            for name, data in files.items():
                entry = tarfile.TarInfo("GameCase-source/" + name)
                entry.size = len(data)
                archive.addfile(entry, io.BytesIO(data))
        (root / "LICENSE").write_bytes((ROOT / "LICENSE").read_bytes())
        (root / "THIRD_PARTY_NOTICES.md").write_bytes((ROOT / "THIRD_PARTY_NOTICES.md").read_bytes())
        return version, tree

    def test_checksums_cover_all_distributed_materials(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            version, tree = self.fixture(root)
            module("validate_release").validate(root, version, tree)
            sums = (root / "SHA256SUMS").read_text().splitlines()
            self.assertEqual(len(sums), 4)
            self.assertTrue(any(line.endswith("  GameCase-source.tar.gz") for line in sums))

    def test_missing_license_blocks_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            version, tree = self.fixture(root, missing_notice=True)
            with self.assertRaises(KeyError):
                module("validate_release").validate(root, version, tree)
            self.assertFalse((root / "SHA256SUMS").exists())

    def test_mismatched_source_blocks_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            version, tree = self.fixture(root, wrong_tree=True)
            with self.assertRaises(AssertionError):
                module("validate_release").validate(root, version, tree)
            self.assertFalse((root / "SHA256SUMS").exists())
