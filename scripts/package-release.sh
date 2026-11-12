#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TAG="${1:?Usage: package-release.sh <version-tag>}"
if [[ ! "$TAG" =~ ^(v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?|dry-run)$ ]]; then
    echo "Invalid release tag" >&2
    exit 1
fi
APP="$ROOT/build/OpenKind.app"
[[ -d "$APP" ]] || { echo "Build OpenKind.app first" >&2; exit 1; }
mkdir -p "$ROOT/dist" "$ROOT/build"
STAGING="$(mktemp -d "$ROOT/build/dmg-staging.XXXXXX")"
MOUNTPOINT="$(mktemp -d "$ROOT/build/dmg-verify.XXXXXX")"
MOUNTED=0
cleanup() {
    if [[ "$MOUNTED" == 1 ]]; then hdiutil detach -quiet "$MOUNTPOINT" || true; fi
    rm -rf "$STAGING"
    rmdir "$MOUNTPOINT" 2>/dev/null || true
}
trap cleanup EXIT
# A normal Finder window shows both the app and an Applications shortcut.
ditto "$APP" "$STAGING/OpenKind.app"
ln -s /Applications "$STAGING/Applications"
ARCHIVE="OpenKind-${TAG}-macOS-universal.zip"
DISK_IMAGE="OpenKind-${TAG}-macOS-universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/$ARCHIVE"
hdiutil create -quiet -ov -volname OpenKind -srcfolder "$STAGING" -fs HFS+ -format UDZO "$ROOT/dist/$DISK_IMAGE"
hdiutil verify -quiet "$ROOT/dist/$DISK_IMAGE"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNTPOINT" "$ROOT/dist/$DISK_IMAGE"
MOUNTED=1
[[ -d "$MOUNTPOINT/OpenKind.app" && "$(readlink "$MOUNTPOINT/Applications")" == /Applications ]]
codesign --verify --deep --strict "$MOUNTPOINT/OpenKind.app"
hdiutil detach -quiet "$MOUNTPOINT"
MOUNTED=0
(cd "$ROOT/dist" && shasum -a 256 "$ARCHIVE" "$DISK_IMAGE" > SHA256SUMS.txt && shasum -a 256 -c SHA256SUMS.txt)
printf 'Built: %s\n' "$ROOT/dist/$DISK_IMAGE"
