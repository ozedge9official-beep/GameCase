import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class PackagingTests(unittest.TestCase):
    def test_package_is_isolated_and_contains_only_the_ordinary_app(self):
        with tempfile.TemporaryDirectory(prefix="gamecase package ") as directory:
            root = Path(directory)
            app = root / "archive.xcarchive/Products/Applications/LiveContainer.app"
            app.mkdir(parents=True)
            (app / "Info.plist").write_text("test app")
            (app / ".DS_Store").write_text("ignore")
            (root / "Payload").mkdir()
            (root / "Payload/old-file").write_text("must not ship")
            env = {**os.environ, "archive_path": str(root / "archive")}
            subprocess.run(["sh", str(ROOT / ".github/build_github.sh")], cwd=root, env=env, check=True)
            with zipfile.ZipFile(root / "GameCase.ipa") as archive:
                names = archive.namelist()
            self.assertIn("Payload/LiveContainer.app/Info.plist", names)
            self.assertFalse(any("old-file" in name or ".DS_Store" in name or "SideStore" in name for name in names))
            self.assertTrue((app / "Info.plist").exists(), "archive remains available for inspection")

    def test_missing_archive_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            env = {**os.environ, "archive_path": "missing"}
            result = subprocess.run(["sh", str(ROOT / ".github/build_github.sh")], cwd=directory,
                                    env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((Path(directory) / "GameCase.ipa").exists())
