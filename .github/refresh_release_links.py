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


def migrate_feed(data, repo, previous_repo, retired_tag=""):
    result = source.rehome(data, repo, previous_repo)
    for app in result.get("apps", []):
        if retired_tag:
            retired_path = "/releases/download/" + retired_tag + "/"
            app["versions"] = [v for v in app.get("versions", []) if retired_path not in v.get("downloadURL", "")]
            if retired_path in app.get("downloadURL", ""):
                raise ValueError("Feed still selects the retired release")
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


def retire_release(repo, retired_tag, replacement_tag):
    if not all(re.fullmatch(r"v\d+\.\d+\.\d+", tag) for tag in [retired_tag, replacement_tag]) or retired_tag == replacement_tag:
        raise ValueError("Retirement requires two distinct stable version tags")
    replacement = api(f"repos/{repo}/releases/tags/{replacement_tag}")
    if replacement["draft"] or replacement["prerelease"] or api(f"repos/{repo}/releases/latest")["tag_name"] != replacement_tag:
        raise ValueError("Replacement must be the published latest stable release")
    old = next((r for r in api(f"repos/{repo}/releases?per_page=100") if r["tag_name"] == retired_tag), None)
    archive_name = f"GameCase-{retired_tag}-source.tar.gz"
    if old is None:
        if not any(a["name"] == archive_name for a in replacement["assets"]):
            raise ValueError("Retired release and archived source are both missing")
        return
    original = next(a for a in old["assets"] if a["name"] == "GameCase-source.tar.gz")
    archived = next((a for a in replacement["assets"] if a["name"] == archive_name), None)
    if archived is None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / archive_name
            with urlopen(original["browser_download_url"], timeout=60) as response:
                path.write_bytes(response.read())
            if original.get("digest") != "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest():
                raise ValueError("Source download digest mismatch; old release retained")
            subprocess.run(["gh", "release", "upload", replacement_tag, str(path), "--repo", repo], check=True)
        replacement = api(f"repos/{repo}/releases/{replacement['id']}")
        archived = next(a for a in replacement["assets"] if a["name"] == archive_name)
    if not archived.get("digest") or archived["digest"] != original.get("digest"):
        raise ValueError("Archived source digest mismatch; old release retained")
    archive_url = f"https://github.com/{repo}/releases/download/{replacement_tag}/{archive_name}"
    body = replacement.get("body") or ""
    body = body.replace("历史安装包与标签保留原样；", f"历史标签和对应源码保留；{retired_tag} 安装包下架。")
    body = body.replace("Historical installation packages and tags are preserved;",
                        f"Historical tags and corresponding source are retained; the {retired_tag} installation package is withdrawn.")
    if archive_url not in body:
        body += (f"\n\n### 历史源码 / Archived source\n\n"
                 f"{retired_tag} 已下架，Git 标签保留；[对应源码归档]({archive_url})（含该版本许可资料）。\n\n"
                 f"{retired_tag} has been withdrawn; its Git tag is retained. [Archived corresponding source]({archive_url}) includes its license materials.\n")
        api(f"repos/{repo}/releases/{replacement['id']}", {"body": body})
    subprocess.run(["gh", "api", "--method", "DELETE", f"repos/{repo}/releases/{old['id']}"], check=True)
    print("Retired release; preserved tag and verified archived source:", retired_tag, flush=True)


def main():
    repo = source.repository()
    previous = os.environ["PREVIOUS_OWNER"]
    if not re.fullmatch(r"[A-Za-z0-9-]+", previous):
        raise ValueError("Invalid previous owner")
    previous_repo = previous + "/" + repo.split("/")[1]
    retired = os.environ.get("RETIRE_TAG", "")
    replacement = os.environ.get("REPLACEMENT_TAG", "")
    if retired or replacement:
        retire_release(repo, retired, replacement)
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
                updated = migrate_feed(original, repo, previous_repo, retired)
                if replacement and release["tag_name"] == replacement:
                    release = api(endpoint)
                    description = source.prepare_description(release.get("body"))
                    for app in updated.get("apps", []):
                        app["versionDescription"] = description
                        for version in app.get("versions", []):
                            if version["version"] == app["version"]:
                                version["localizedDescription"] = description
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
