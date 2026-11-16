"""Generate the external AltStore/SideStore source for this repository's IPA."""
import json
import os
from pathlib import Path
import plistlib
import re
from datetime import datetime, timezone
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_REPOSITORY = "ozedge9official-beep/GameCase"


def repository():
    value = os.environ.get("GITHUB_REPOSITORY", DEFAULT_REPOSITORY)
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise ValueError("Invalid GITHUB_REPOSITORY")
    return value


def fetch_json(url):
    headers = {"Accept": "application/vnd.github+json"}
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    with urlopen(Request(url, headers=headers), timeout=30) as response:
        return json.load(response)


def fetch_release(repo, tag=None):
    if tag:
        from urllib.parse import quote
        return fetch_json(f"https://api.github.com/repos/{repo}/releases/tags/{quote(tag, safe='')}")
    releases = fetch_json(f"https://api.github.com/repos/{repo}/releases?per_page=100")
    return next((r for r in releases if not r["draft"] and not r["prerelease"] and r["tag_name"] != "nightly"), None)


def prepare_description(text):
    text = re.sub(r"<[^<]+?>", "", text or "")
    return re.sub(r"#{1,6}\s?|\*\*|`", "", text)


def rehome(value, repo):
    if isinstance(value, str):
        return value.replace("Tiaoge-tou/GameCase", repo).replace(DEFAULT_REPOSITORY, repo)
    if isinstance(value, list):
        return [rehome(item, repo) for item in value]
    if isinstance(value, dict):
        return {key: rehome(item, repo) for key, item in value.items()}
    return value


def build_source(seed, repo, release, version, nightly=False):
    data = rehome(seed, repo)
    asset = next((a for a in release.get("assets", []) if a["name"] == "GameCase.ipa"), None)
    if not asset or asset["size"] <= 0:
        raise ValueError("The selected release has no non-empty GameCase.ipa")
    app = data["apps"][0]
    description = prepare_description(release.get("body"))
    entry = {"version": version, "date": release["published_at"],
             "localizedDescription": description,
             "downloadURL": asset["browser_download_url"], "size": asset["size"]}
    if nightly:
        entry.update(commit=os.environ.get("commit_sha", "")[:7],
                     headline=os.environ.get("commit_msg", "").strip())
    # Preserve other valid versions when regenerating a stable source.
    versions = [] if nightly else [v for v in app.get("versions", []) if v["version"] != version]
    app["versions"] = [entry] + versions
    app.update(version=version, versionDate=entry["date"], versionDescription=description,
               downloadURL=entry["downloadURL"], size=entry["size"])
    # The removed embedded app had its own channels. Only the ordinary IPA is published.
    app.pop("releaseChannels", None)
    data["news"] = []
    return data


def write_source(path, data):
    encoded = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    previous = path.read_text() if path.exists() else ""
    changed = encoded != previous
    if changed:
        temporary = path.with_suffix(".tmp.json")
        temporary.write_text(encoded)
        temporary.replace(path)
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a") as stream:
            stream.write(f"changes={str(changed).lower()}\n")
    return changed


def main():
    repo = repository()
    nightly = bool(os.environ.get("NIGHTLY_LINK"))
    seed = json.loads((ROOT / ".github/apps.json").read_text())
    if nightly:
        # Generate from the build being published, including the very first nightly.
        # Looking up the old release here used its previous date and IPA size.
        ipa = ROOT / "GameCase.ipa"
        with (ROOT / "LiveContainer/Info.plist").open("rb") as stream:
            version = plistlib.load(stream)["CFBundleShortVersionString"]
        release = {
            "published_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "body": f"{os.environ.get('commit_msg', '').strip()}\n{os.environ['NIGHTLY_LINK']}",
            "assets": [{"name": "GameCase.ipa", "size": ipa.stat().st_size,
                        "browser_download_url": f"https://github.com/{repo}/releases/download/nightly/GameCase.ipa"}],
        }
    else:
        release = fetch_release(repo, os.environ.get("RELEASE_TAG"))
        if not release:
            raise ValueError("No stable release found")
        match = re.fullmatch(r"v?(\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?)", release["tag_name"])
        if not match:
            raise ValueError("Release tag must contain the released semantic version")
        version = match[1]
    path = ROOT / (".github/apps_nightly.json" if nightly else ".github/apps.json")
    write_source(path, build_source(seed, repo, release, version, nightly))


if __name__ == "__main__":
    main()
