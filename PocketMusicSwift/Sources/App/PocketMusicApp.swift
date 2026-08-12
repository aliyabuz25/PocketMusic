import SwiftUI

@main
struct PocketMusicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = MenuBarModel.shared
    @ObservedObject private var favorites = FavoritesStore.shared

    var body: some Scene {
        MenuBarExtra {
            Button {
                MainWindowController.shared.present()
                PocketMusicUIState.shared.tab = .search
            } label: {
                Label("Pocket Music", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("k", modifiers: .command)

            Divider()

            Text(model.trackTitle)
                .foregroundStyle(.secondary)
                .disabled(true)
            Text(model.artistTitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .disabled(true)

            Divider()

            if favorites.items.isEmpty {
                Text("Henüz favori yok")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            } else {
                Menu("Favoriler") {
                    ForEach(favorites.items) { track in
                        Button {
                            Task { await favorites.play(track) }
                        } label: {
                            Text("\(track.title) — \(track.artist)")
                        }
                    }
                }
            }

            Divider()

            Button {
                MainWindowController.shared.present()
            } label: {
                Label("Pocket Music Aç", systemImage: "waveform.circle.fill")
            }

            Divider()

            Button {
                model.togglePlay()
            } label: {
                Label(model.playLabel, systemImage: model.playIcon)
            }
            .disabled(!model.hasTrack)

            Button {
                model.stop()
            } label: {
                Label("Durdur", systemImage: "stop.fill")
            }
            .disabled(!model.hasTrack)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Çıkış", systemImage: "power")
            }
            .keyboardShortcut("q")
        } label: {
            if let img = model.menuBarImage {
                Image(nsImage: img)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
