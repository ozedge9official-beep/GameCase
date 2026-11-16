import importlib.util
import io
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("refresh_links", ROOT / ".github/refresh_release_links.py")
refresh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(refresh)


class ReleaseRetirementTests(unittest.TestCase):
    def test_corrupt_source_cannot_delete_old_release(self):
        replacement = {"id": 2, "draft": False, "prerelease": False, "assets": []}
        old = {"id": 1, "tag_name": "v1.0.0", "assets": [
            {"name": "GameCase-source.tar.gz", "digest": "sha256:" + "0" * 64,
             "browser_download_url": "https://example.invalid/source"}]}
        with patch.object(refresh, "api", side_effect=[replacement, {"tag_name": "v2.0.0"}, [old]]) as api, \
             patch.object(refresh, "urlopen", return_value=io.BytesIO(b"corrupted source")), \
             patch.object(refresh.subprocess, "run") as mutation:
            with self.assertRaisesRegex(ValueError, "digest mismatch"):
                refresh.retire_release("example/project", "v1.0.0", "v2.0.0")
            mutation.assert_not_called()
            self.assertTrue(all(len(call.args) == 1 for call in api.call_args_list))

    def test_draft_replacement_cannot_retire_published_release(self):
        with patch.object(refresh, "api", return_value={"draft": True}) as api, \
             patch.object(refresh, "urlopen") as download, \
             patch.object(refresh.subprocess, "run") as mutation:
            with self.assertRaisesRegex(ValueError, "published latest stable"):
                refresh.retire_release("example/project", "v1.0.0", "v2.0.0")
            self.assertEqual(api.call_count, 1)
            download.assert_not_called()
            mutation.assert_not_called()

    def test_retirement_removes_stable_download_but_preserves_nightly(self):
        root = "https://github.com/example/project/releases/download/"
        seed = {"website": "https://github.com/example/project", "apps": [{
            "downloadURL": root + "nightly/GameCase.ipa", "version": "1.0.0",
            "versions": [
                {"version": "2.0.0", "downloadURL": root + "v2.0.0/GameCase.ipa"},
                {"version": "1.0.0", "downloadURL": root + "v1.0.0/GameCase.ipa"},
                {"version": "1.0.0", "downloadURL": root + "nightly/GameCase.ipa"}]}]}
        result = refresh.migrate_feed(seed, "example/project", "example/project", "v1.0.0")
        app = result["apps"][0]
        self.assertEqual(app["downloadURL"], root + "nightly/GameCase.ipa")
        self.assertEqual([v["version"] for v in app["versions"]], ["2.0.0", "1.0.0"])
        self.assertTrue(app["versions"][-1]["downloadURL"].endswith("nightly/GameCase.ipa"))
