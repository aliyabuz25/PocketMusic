#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "→ Swift Spotlight uygulaması derleniyor..."
chmod +x "$ROOT/SpotlightApp/build.sh"
"$ROOT/SpotlightApp/build.sh" "$ROOT/PocketMusicSpotlight.app"

echo "→ /Applications'a kuruluyor..."
cp -R "$ROOT/PocketMusicSpotlight.app" "/Applications/PocketMusic.app"
xattr -cr "/Applications/PocketMusic.app" 2>/dev/null || true

echo "→ Uygulama başlatılıyor (Spotlight kaydı için)..."
open -a "/Applications/PocketMusic.app" || true

echo ""
echo "✓ Kuruldu: /Applications/PocketMusic.app"
echo ""
echo "Spotlight kullanımı:"
echo "  1. pocketmusic spotlight \"palagi\"     → sonuçları Spotlight'a ekler"
echo "  2. ⌘+Space → \"palagi\" yaz             → parçalar görünür"
echo "  3. Sonuca tıkla                         → anında stream oynar"
echo ""
echo "Veya Spotlight'ta: \"PocketMusic oynat\" de"
