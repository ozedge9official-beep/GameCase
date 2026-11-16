import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("release_source", ROOT / ".github/update_json.py")
source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source)


class ReleaseSourceTests(unittest.TestCase):
    def setUp(self):
        self.seed = json.loads((ROOT / ".github/apps.json").read_text())
        self.release = {"tag_name": "v2.3.4", "published_at": "2026-11-17T00:00:00Z", "body": None,
                        "assets": [{"name": "GameCase.ipa", "size": 42,
                                    "browser_download_url": "https://github.com/example/fork/releases/download/v2.3.4/GameCase.ipa"}]}

    def test_fork_source_uses_its_own_urls_and_asset(self):
        data = source.build_source(self.seed, "example/fork", self.release, "2.3.4")
        encoded = json.dumps(data)
        self.assertNotIn("https://github.com/whodaregg/GameCase", encoded)
        self.assertNotIn("https://raw.githubusercontent.com/whodaregg/GameCase", encoded)
        self.assertEqual(data["apps"][0]["versions"][0]["size"], 42)
        self.assertEqual(data["apps"][0]["version"], "2.3.4")

    def test_account_rename_updates_urls_and_retains_upstream_attribution(self):
        seed = copy.deepcopy(self.seed)
        seed["website"] = "https://github.com/previous-owner/GameCase"
        app = seed["apps"][0]
        app["iconURL"] = "https://raw.githubusercontent.com/previous-owner/GameCase/main/icon.png"
        app["versions"] = [{"version": "1.0.0", "downloadURL": "https://github.com/previous-owner/GameCase/releases/download/v1.0.0/GameCase.ipa",
                            "localizedDescription": "Based on Tiaoge-tou/GameCase; https://github.com/Tiaoge-tou/GameCase"}]
        data = source.build_source(seed, "example/new-name", self.release, "2.3.4")
        self.assertEqual(data["website"], "https://github.com/example/new-name")
        self.assertIn("example/new-name/main/icon.png", data["apps"][0]["iconURL"])
        previous = data["apps"][0]["versions"][1]
        self.assertIn("example/new-name/releases/download/v1.0.0/", previous["downloadURL"])
        self.assertEqual(previous["localizedDescription"], app["versions"][0]["localizedDescription"])

    def test_draft_asset_url_is_replaced_with_the_stable_tag(self):
        self.release["assets"][0]["browser_download_url"] = "https://github.com/example/fork/releases/download/untagged-temporary/GameCase.ipa"
        data = source.build_source(self.seed, "example/fork", self.release, "2.3.4")
        expected = "https://github.com/example/fork/releases/download/v2.3.4/GameCase.ipa"
        self.assertEqual(data["apps"][0]["downloadURL"], expected)
        self.assertEqual(data["apps"][0]["versions"][0]["downloadURL"], expected)

    def test_missing_or_empty_ipa_fails(self):
        for assets in [[], [{"name": "GameCase.ipa", "size": 0}]]:
            with self.subTest(assets=assets), self.assertRaises(ValueError):
                source.build_source(self.seed, "example/fork", {**self.release, "assets": assets}, "2.3.4")

    def test_nightly_build_does_not_need_an_existing_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".github").mkdir()
            (root / "LiveContainer").mkdir()
            (root / ".github/apps.json").write_text(json.dumps(self.seed))
            (root / "LiveContainer/Info.plist").write_bytes((ROOT / "LiveContainer/Info.plist").read_bytes())
            (root / "GameCase.ipa").write_bytes(b"new-build")
            env = {"NIGHTLY_LINK": "https://example.com/build", "GITHUB_REPOSITORY": "example/fork"}
            with patch.object(source, "ROOT", root), patch.dict(os.environ, env), patch.object(source, "fetch_release") as fetch:
                source.main()
                fetch.assert_not_called()
            result = json.loads((root / ".github/apps_nightly.json").read_text())
            self.assertEqual(result["apps"][0]["size"], len(b"new-build"))
            self.assertIn("example/fork/releases/download/nightly/", result["apps"][0]["downloadURL"])

    def test_source_write_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {}, clear=True):
            path = Path(directory) / "apps.json"
            self.assertTrue(source.write_source(path, self.seed))
            self.assertFalse(source.write_source(path, self.seed))
