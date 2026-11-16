"""Archive the tested source, pinned dependencies and verified OpenSSL sources."""
import hashlib
import io
import json
from pathlib import Path
import plistlib
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "GameCase-source/"
OPENSSL_SHA256 = "712590fd20aaa60ec75d778fe5b810d6b829ca7fb1e530577917a131f9105539"


def git(*args, root=ROOT):
    return subprocess.check_output(["git", *args], cwd=root, text=True).strip()


def add_checkout(bundle, root, prefix, openssl=False):
    # git archive preserves executable bits and symlinks, and excludes .git,
    # build products, untracked files and local certificates automatically.
    with tempfile.TemporaryFile() as stream:
        subprocess.run(["git", "archive", "--format=tar", "HEAD"], cwd=root, stdout=stream, check=True)
        stream.seek(0)
        with tarfile.open(fileobj=stream) as archive:
            for member in archive:
                name = member.name
                if openssl:
                    # Only iOS arm64 is used by this project's archive command.
                    if name.startswith("Frameworks/") and not (
                        name.startswith("Frameworks/OpenSSL.xcframework/ios-arm64/") or
                        name == "Frameworks/OpenSSL.xcframework/Info.plist"
                    ):
                        continue
                    if name.split("/")[0] in {"appletvos", "appletvsimulator", "iphoneos", "iphonesimulator",
                                                "macosx", "macosx_catalyst", "visionos", "visionsimulator", "watchos", "watchsimulator"}:
                        continue
                source = archive.extractfile(member) if member.isfile() else None
                member.name = prefix + name
                bundle.addfile(member, source)


def build(output=ROOT / "GameCase-source.tar.gz"):
    version = plistlib.loads((ROOT / "LiveContainer/Info.plist").read_bytes())["CFBundleShortVersionString"]
    manifest = {"version": version, "sourceCommit": git("rev-parse", "HEAD"),
                "sourceTree": git("rev-parse", "HEAD^{tree}"), "submodules": {},
                "opensslSourceSHA256": OPENSSL_SHA256,
                "opensslSourceVersion": "3.3.3"}
    for path in ["litehook", "OpenSSL"]:
        expected = git("rev-parse", "HEAD:" + path)
        actual = git("rev-parse", "HEAD", root=ROOT / path)
        if actual != expected:
            raise RuntimeError("Submodule mismatch: " + path)
        manifest["submodules"][path] = expected
    with tempfile.TemporaryDirectory() as directory:
        source = Path(directory) / "openssl-3.3.3.tar.gz"
        urllib.request.urlretrieve("https://github.com/openssl/openssl/releases/download/openssl-3.3.3/openssl-3.3.3.tar.gz", source)
        if hashlib.sha256(source.read_bytes()).hexdigest() != OPENSSL_SHA256:
            raise RuntimeError("OpenSSL source digest mismatch")
        with tarfile.open(output, "w:gz") as bundle:
            add_checkout(bundle, ROOT, PREFIX)
            for path in ["litehook", "OpenSSL"]:
                add_checkout(bundle, ROOT / path, PREFIX + path + "/", openssl=path == "OpenSSL")
            bundle.add(source, arcname=PREFIX + "OpenSSL/openssl-3.3.3.tar.gz")
            data = (json.dumps(manifest, indent=2) + "\n").encode()
            entry = tarfile.TarInfo(PREFIX + "SOURCE-MANIFEST.json")
            entry.size = len(data)
            bundle.addfile(entry, io.BytesIO(data))
    print("Source bundle:", output, manifest["sourceTree"])


if __name__ == "__main__":
    build()
