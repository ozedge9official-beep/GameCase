#!/bin/sh
set -eu

: "${archive_path:?archive_path must name the Xcode archive}"
# Build in an isolated directory so a previous Payload cannot contaminate the IPA.
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT HUP INT TERM
cp -R "$archive_path.xcarchive/Products/Applications" "$staging/Payload"
test -d "$staging/Payload/LiveContainer.app"
output="$PWD/GameCase.ipa"
rm -f "$output"
(cd "$staging" && zip -qr "$output" Payload -x '*/._*' '*/.DS_Store' '*/__MACOSX/*')
