import io
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class ArchiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory()
        cls.runner = Path(cls.build.name) / "extract"
        library = "-larchive" if sys.platform == "darwin" else "-Wl,-l:libarchive.so.13"
        subprocess.run(["cc", "-Wall", "-Wextra", "-Werror", "-I", str(ROOT / "LiveContainerSwiftUI/Utilities"),
                        str(ROOT / "tests/archive_runner.c"), library, "-o", str(cls.runner)], check=True)
        cls.full_runner = Path(cls.build.name) / "extract-full"
        subprocess.run(["cc", "-Wall", "-Wextra", "-Werror", "-DLC_ARCHIVE_TEST_AVAILABLE_BYTES=0",
                        "-I", str(ROOT / "LiveContainerSwiftUI/Utilities"), str(ROOT / "tests/archive_runner.c"),
                        library, "-o", str(cls.full_runner)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.destination = self.root / "extracted"
        self.destination.mkdir()

    def extract_zip(self, entries):
        source = self.root / "input.zip"
        with zipfile.ZipFile(source, "w") as archive:
            for name, value in entries:
                archive.writestr(name, value)
        return subprocess.run([str(self.runner), str(source), str(self.destination)], capture_output=True).returncode

    def test_normal_zip_and_unicode(self):
        self.assertEqual(self.extract_zip([("save/存档.dat", b"complete")]), 0)
        self.assertEqual((self.destination / "save/存档.dat").read_bytes(), b"complete")

    def test_space_preflight_prevents_any_writes(self):
        source = self.root / "input.zip"
        with zipfile.ZipFile(source, "w") as archive:
            archive.writestr("save.dat", b"new")
        (self.destination / "keep").write_bytes(b"original")
        result = subprocess.run([str(self.full_runner), str(source), str(self.destination)], capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual([p.name for p in self.destination.iterdir()], ["keep"])
        self.assertEqual((self.destination / "keep").read_bytes(), b"original")

    def test_archive_validation_precedes_capacity_error(self):
        source = self.root / "input.zip"
        with zipfile.ZipFile(source, "w") as archive:
            archive.writestr("../outside", b"bad")
        result = subprocess.run([str(self.full_runner), str(source), str(self.destination)], capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.root / "outside").exists())

    def test_reject_parent_traversal_before_writing_any_entry(self):
        self.assertNotEqual(self.extract_zip([("good", b"ok"), ("../outside", b"bad")]), 0)
        self.assertFalse((self.root / "outside").exists())
        self.assertFalse((self.destination / "good").exists())

    def test_reject_absolute_path(self):
        outside = self.root / "outside"
        self.assertNotEqual(self.extract_zip([(str(outside), b"bad")]), 0)
        self.assertFalse(outside.exists())

    def test_report_partial_write_failure(self):
        self.assertNotEqual(self.extract_zip([("valid", b"ok"), ("blocked/keep", b"keep"),
                                               ("blocked", b"cannot replace directory")]), 0)

    def test_do_not_follow_preexisting_symlink(self):
        outside = self.root / "outside"
        outside.mkdir()
        (self.destination / "link").symlink_to(outside, target_is_directory=True)
        self.extract_zip([("link/file", b"bad")])
        self.assertFalse((outside / "file").exists())

    def test_reject_symlink_escape(self):
        source = self.root / "input.tar"
        with tarfile.open(source, "w") as archive:
            link = tarfile.TarInfo("link")
            link.type = tarfile.SYMTYPE
            link.linkname = "../outside"
            archive.addfile(link)
        result = subprocess.run([str(self.runner), str(source), str(self.destination)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.destination / "link").is_symlink())

    def test_preserve_internal_framework_symlink(self):
        source = self.root / "input.tar"
        with tarfile.open(source, "w") as archive:
            file = tarfile.TarInfo("Framework/Versions/A/Binary")
            file.size = 4
            archive.addfile(file, io.BytesIO(b"data"))
            link = tarfile.TarInfo("Framework/Binary")
            link.type = tarfile.SYMTYPE
            link.linkname = "Versions/A/Binary"
            archive.addfile(link)
        result = subprocess.run([str(self.runner), str(source), str(self.destination)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.destination / "Framework/Binary").read_bytes(), b"data")

    def test_corrupted_zip_is_an_error(self):
        source = self.root / "input.zip"
        with zipfile.ZipFile(source, "w") as archive:
            archive.writestr("save.dat", b"unique-content-marker")
        source.write_bytes(source.read_bytes().replace(b"unique-content-marker", b"BROKEN-content-marker"))
        result = subprocess.run([str(self.runner), str(source), str(self.destination)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
