#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "→ PocketMusic Swift derleniyor..."
chmod +x "$ROOT/build.sh"
"$ROOT/build.sh"

echo "→ Eski sürüm durduruluyor..."
pkill -f "PocketMusic/bar.py" 2>/dev/null || true
pkill -f "PocketMusic.app/Contents/MacOS/PocketMusic" 2>/dev/null || true
sleep 1

echo "→ /Applications'a kuruluyor..."
rm -rf /Applications/PocketMusic.app
cp -R "$ROOT/PocketMusic.app" /Applications/PocketMusic.app
xattr -cr /Applications/PocketMusic.app 2>/dev/null || true

# Spotlight + Launch Services kaydı
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f -R -trusted /Applications/PocketMusic.app 2>/dev/null || true
mdimport /Applications/PocketMusic.app 2>/dev/null || true

echo "→ Başlatılıyor..."
open /Applications/PocketMusic.app

# CLI kısayolu
mkdir -p "$HOME/bin"
cat > "$HOME/bin/pocketmusic" <<'EOF'
#!/bin/bash
case "${1:-}" in
  stop)
    pkill -x PocketMusic 2>/dev/null
    pkill mpv 2>/dev/null
    ;;
  *)
    open pocketmusic://search 2>/dev/null || open -a /Applications/PocketMusic.app
    ;;
esac
EOF
chmod +x "$HOME/bin/pocketmusic"

echo ""
echo "✓ PocketMusic Swift kuruldu!"
echo "  Menü çubuğunda ♪ ikonu → Ara"
echo "  veya: pocketmusic search"
