# Pocket Music

> **Apple Music kalitesinde keşfet. Pocket Music hızında çal.**

Native macOS müzik deneyimi — menü çubuğu, tam ekran uygulama, mini player, şifreli offline indirme.

**[Ali Yabuza](https://github.com/aliyabuz25)** tarafından geliştirildi.

### Ekosistem paketleri

| Paket | Açıklama |
|-------|----------|
| [AppleMusicCharts](https://github.com/aliyabuz25/AppleMusicCharts) | iTunes arama + Apple RSS listeleri |
| [SwiftUIGhost](https://github.com/aliyabuz25/SwiftUIGhost) | Shimmer skeleton loading bileşenleri |
| [PocketCrypto](https://github.com/aliyabuz25/PocketCrypto) | AES-GCM + Keychain şifreleme |
| [macos-dev-kit](https://github.com/aliyabuz25/macos-dev-kit) | macOS / Swift geliştirme scriptleri |

---

## Özellikler

| Özellik | Açıklama |
|---------|----------|
| **Apple Music katalog** | Arama, Popüler, Keşfet — resmi kapak ve metadata |
| **Anında mini player** | Parça seçilir seçilmez açılır, Apple Music preview ile akıcı geçiş |
| **Hızlı stream** | yt-dlp + mpv, önceden çözülmüş stream URL |
| **Playlistimiz** | PocketMix — en çok dinlenen kapak, dinleme geçmişi |
| **Favoriler** | Uygulama içi ♡, satır ve oynatıcı barından |
| **Yerel (şifreli)** | AES-GCM + Keychain — `.pmenc` dosyaları dışarıdan çalınamaz |
| **Ghost UI** | Shimmer skeleton loading, koyu tema, SF Symbols |

## Ekran görüntüsü

```
┌─────────────────────────────────────────────────────────┐
│  Pocket Music          │  Ara · Keşfet · Popüler        │
│  ─────────────         │  ────────────────────────────  │
│  ♪ Ara                 │  [Apple Music arama sonuçları]│
│  ♪ Playlistimiz        │                                │
│  ♪ Keşfet              │                                │
│  ♪ Popüler             │                                │
│  ♪ Favoriler           │                                │
│  ♪ Yerel               │                                │
│                        │  ▶ ⏮ ⏭ ♡ ↓  [player bar]     │
└─────────────────────────────────────────────────────────┘
```

## Kurulum

### Gereksinimler

- macOS 13.0+
- Xcode Command Line Tools (`xcode-select --install`)
- [Homebrew](https://brew.sh) ile:

```bash
brew install yt-dlp mpv
```

### Hızlı kurulum

```bash
git clone https://github.com/aliyabuz25/PocketMusic.git
cd PocketMusic/PocketMusicSwift
chmod +x install.sh
./install.sh
```

Uygulama `/Applications/PocketMusic.app` olarak kurulur ve başlar.

### Manuel derleme

```bash
cd PocketMusicSwift
./build.sh
open PocketMusic.app
```

## Kullanım

| Kısayol | İşlev |
|---------|-------|
| Menü çubuğu `waveform` | Ana menü |
| `⌘K` | Pocket Music aç (Ara sekmesi) |
| Mini player `↗` | Tam uygulamaya geç |
| `pocketmusic` | CLI — uygulamayı aç |
| `pocketmusic stop` | Oynatmayı durdur |

### URL scheme

```
pocketmusic://search
```

## Mimari

```
PocketMusicSwift/Sources/
├── App/           # Giriş noktası, AppDelegate
├── Core/          # Modeller, tema, sabitler
├── Services/      # Catalog, Browse, Music, Playback
├── Stores/        # Favoriler, playlist, offline, geçmiş
├── UI/            # SwiftUI ana pencere, tasarım sistemi
├── Player/        # Mini player, preview cache
├── State/         # UI state (Combine)
├── Crypto/        # AES-GCM şifreleme
└── MenuBar/       # Menü çubuğu modeli
```

### Veri akışı

```
Apple Music API ──► Arama / Keşfet / Popüler (metadata + kapak)
                         │
                         ▼
              PlaybackLauncher (anında mini player)
                         │
            YouTube stream resolve (yt-dlp)
                         │
                         ▼
                    mpv (ses oynatma)
                         │
            Apple Music preview (mini player görsel)
```

## Teknolojiler

- **Swift 5** — AppKit + SwiftUI hibrit UI
- **mpv** — Düşük gecikmeli ses oynatma
- **yt-dlp** — Stream çözümleme
- **iTunes Search API** — Katalog ve kapak
- **Apple RSS** — Türkiye Top 50
- **CryptoKit + Keychain** — Offline şifreleme
- **AVFoundation** — 30sn preview video/audio

## Legacy (Python)

Eski Python menü çubuğu ve Spotlight prototipi `legacy/python/` altında saklanır. Aktif geliştirme **Swift** sürümündedir.

## Katkı

1. Fork
2. Feature branch (`git checkout -b feature/amazing`)
3. Commit (`git commit -m 'Add amazing feature'`)
4. Push + Pull Request

## Lisans

[MIT](LICENSE) © 2026 Ali Yabuza

---

<p align="center">
  <strong>Pocket Music</strong> — Dinle. Keşfet. Sakla.
  <br>
  <a href="https://github.com/aliyabuz25">@aliyabuz25</a>
</p>
