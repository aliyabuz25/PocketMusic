#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/Sources"
BUILD="$ROOT/build"
APP="$ROOT/PocketMusic.app"
SDK="$(xcrun --show-sdk-path)"
TARGET="${1:-arm64-apple-macos13.0}"

mkdir -p "$BUILD"
mkdir -p "$APP/Contents/MacOS"

SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$file")
done < <(find "$SRC" -name '*.swift' | sort)

echo "→ Swift derleniyor (${#SOURCES[@]} dosya)..."
swiftc -O \
    -sdk "$SDK" \
    -target "$TARGET" \
    "${SOURCES[@]}" \
    -o "$APP/Contents/MacOS/PocketMusic" \
    -framework AppKit \
    -framework QuartzCore \
    -framework SwiftUI \
    -framework AVKit \
    -framework AVFoundation \
    -framework Security

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>tr</string>
    <key>CFBundleExecutable</key>
    <string>PocketMusic</string>
    <key>CFBundleIdentifier</key>
    <string>com.pocketmusic.app</string>
    <key>CFBundleName</key>
    <string>PocketMusic</string>
    <key>CFBundleDisplayName</key>
    <string>PocketMusic</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>PocketMusic</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>pocketmusic</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "✓ $APP"
