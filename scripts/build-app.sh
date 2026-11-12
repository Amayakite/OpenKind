#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="${OPENKIND_VERSION:-0.2.0}"
BUILD_NUMBER="${OPENKIND_BUILD_NUMBER:-1}"
UNIVERSAL="${OPENKIND_UNIVERSAL:-0}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "OPENKIND_VERSION must be X.Y.Z and OPENKIND_BUILD_NUMBER must be numeric" >&2
    exit 1
fi
if [[ "$UNIVERSAL" != 0 && "$UNIVERSAL" != 1 ]]; then
    echo "OPENKIND_UNIVERSAL must be 0 or 1" >&2
    exit 1
fi
APP="$ROOT/build/OpenKind.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "$UNIVERSAL" == 1 ]]; then
    for ARCH in arm64 x86_64; do
        TRIPLE="${ARCH}-apple-macosx14.0"
        swift build -c release --triple "$TRIPLE" --product OpenKind
    done
    ARM_BIN="$(swift build -c release --triple arm64-apple-macosx14.0 --show-bin-path)/OpenKind"
    INTEL_BIN="$(swift build -c release --triple x86_64-apple-macosx14.0 --show-bin-path)/OpenKind"
    lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$APP/Contents/MacOS/OpenKind"
else
    swift build -c release --product OpenKind
    cp "$(swift build -c release --show-bin-path)/OpenKind" "$APP/Contents/MacOS/OpenKind"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>OpenKind</string>
<key>CFBundleIdentifier</key><string>local.default-app-manager</string>
<key>CFBundleName</key><string>OpenKind</string>
<key>CFBundleDisplayName</key><string>OpenKind</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP" >/dev/null
printf 'Built: %s\n' "$APP"
