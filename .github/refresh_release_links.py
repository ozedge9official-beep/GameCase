"""Refresh published feed URLs after the repository owner's account is renamed."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import urlsplit
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("release_source", ROOT / ".github/update_json.py")
source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source)


def api(path, payload=None):
    args = ["gh", "api", path]
    if payload is None:
        return json.loads(subprocess.check_output(args, text=True))
    with tempfile.TemporaryDirectory() as directory:
        body = Path(directory) / "request.json"
        body.write_text(json.dumps(payload, ensure_ascii=False))
        return json.loads(subprocess.check_output(args + ["--method", "PATCH", "--input", str(body)], text=True))


def migrate_feed(data, repo, previous_repo):
    result = source.rehome(data, repo, previous_repo)
    for app in result.get("apps", []):
        screenshots = []
        for value in app.get("screenshotURLs", []):
            url = urlsplit(value)
            prefix = "/" + repo + "/main/"
            if url.netloc == "raw.githubusercontent.com" and url.path.startswith(prefix):
                if not (ROOT / url.path[len(prefix):]).is_file():
                    continue
            screenshots.append(value)
        app["screenshotURLs"] = screenshots
    return result


def main():
    repo = source.repository()
    previous = os.environ["PREVIOUS_OWNER"]
    if not re.fullmatch(r"[A-Za-z0-9-]+", previous):
        raise ValueError("Invalid previous owner")
    previous_repo = previous + "/" + repo.split("/")[1]
    releases = []
    page = 1
    while True:
        batch = api(f"repos/{repo}/releases?per_page=100&page={page}")
        releases.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    with tempfile.TemporaryDirectory() as directory:
        folder = Path(directory)
        for release in releases:
            if release["draft"]:
                continue
            endpoint = f"repos/{repo}/releases/{release['id']}"
            body = source.rehome(release.get("body") or "", repo, previous_repo)
            body = body.replace(previous, repo.split("/")[0])
            if body != release.get("body"):
                api(endpoint, {"body": body})
            for asset in release["assets"]:
                if asset["name"] not in {"apps.json", "apps_nightly.json"}:
                    continue
                with urlopen(asset["browser_download_url"], timeout=60) as response:
                    original = json.load(response)
                updated = migrate_feed(original, repo, previous_repo)
                # This is the same account under a new name, not an upstream author.
                updated = json.loads(json.dumps(updated, ensure_ascii=False).replace(previous, repo.split("/")[0]))
                assert original["identifier"] == updated["identifier"]
                assert [a["bundleIdentifier"] for a in original["apps"]] == [a["bundleIdentifier"] for a in updated["apps"]]
                if original == updated:
                    continue
                candidate = folder / ("feed-refresh-" + asset["name"])
                candidate.write_text(json.dumps(updated, ensure_ascii=False, indent=2) + "\n")
                subprocess.run(["gh", "release", "upload", release["tag_name"], str(candidate), "--repo", repo], check=True)
                current = api(endpoint)
                uploaded = next(a for a in current["assets"] if a["name"] == candidate.name)
                expected = "sha256:" + hashlib.sha256(candidate.read_bytes()).hexdigest()
                if uploaded.get("digest") != expected:
                    raise RuntimeError("Uploaded feed digest mismatch; original retained")
                # Keep the old feed until a verified replacement is present.
                subprocess.run(["gh", "api", "--method", "DELETE", f"repos/{repo}/releases/assets/{asset['id']}"], check=True)
                renamed = api(f"repos/{repo}/releases/assets/{uploaded['id']}", {"name": asset["name"]})
                assert renamed["digest"] == expected
                print("Updated feed:", release["tag_name"], asset["name"], flush=True)
            current = api(endpoint)
            untouched = {a["id"]: a.get("digest") for a in release["assets"] if a["name"] not in {"apps.json", "apps_nightly.json"}}
            assert all(any(a["id"] == key and a.get("digest") == value for a in current["assets"]) for key, value in untouched.items())
            print("Preserved IPA/source/license assets:", release["tag_name"], flush=True)


if __name__ == "__main__":
    main()
