#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="PocketMusicSpotlight"
BUILD_DIR="$ROOT/build"
APP_DIR="${1:-$BUILD_DIR/$APP_NAME.app}"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macos15.0"
SOURCES=(
    "$ROOT/Sources/PocketMusicSpotlightApp.swift"
    "$ROOT/Sources/MusicIntents.swift"
    "$ROOT/Sources/YouTubeSearch.swift"
    "$ROOT/Sources/SpotlightIndexer.swift"
)

mkdir -p "$MACOS"

echo "→ Swift derleniyor..."
swiftc -O \
    -sdk "$SDK" \
    -target "$TARGET" \
    -parse-as-library \
    "${SOURCES[@]}" \
    -o "$MACOS/$APP_NAME" \
    -framework SwiftUI \
    -framework AppKit \
    -framework AppIntents \
    -framework CoreSpotlight \
    -framework Foundation

cat > "$CONTENTS/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>tr</string>
    <key>CFBundleExecutable</key>
    <string>PocketMusicSpotlight</string>
    <key>CFBundleIdentifier</key>
    <string>com.pocketmusic.spotlight</string>
    <key>CFBundleName</key>
    <string>PocketMusic</string>
    <key>CFBundleDisplayName</key>
    <string>PocketMusic</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>pocketmusic</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "✓ $APP_DIR"
