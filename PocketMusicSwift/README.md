# Pocket Music Swift

Native macOS uygulaması — ana kod burada.

## Yapı

| Klasör | Sorumluluk |
|--------|------------|
| `App/` | `@main`, `AppDelegate` |
| `Core/` | `Track`, `BrowseItem`, `PMTheme` |
| `Services/` | Katalog API, browse, oynatma motoru |
| `Stores/` | Favoriler, playlist, offline, dinleme geçmişi |
| `UI/` | SwiftUI görünümler, ana pencere |
| `Player/` | Mini player, preview prefetch |
| `State/` | `PocketMusicUIState` |
| `Crypto/` | Offline şifreleme |
| `MenuBar/` | `MenuBarModel` |

## Derleme

```bash
./build.sh          # arm64 (Apple Silicon)
./build.sh x86_64-apple-macos13.0   # Intel
./install.sh        # /Applications'a kur
```

## Bağımlılıklar

Sistem araçları (Homebrew):

```bash
brew install yt-dlp mpv
```

Framework'ler (Xcode SDK): AppKit, SwiftUI, AVFoundation, Security, QuartzCore.
