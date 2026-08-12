import Foundation

@MainActor
enum PlaybackLauncher {
    static func play(_ track: Track, queue: [Track]? = nil) async {
        if let queue {
            MenuBarModel.shared.configureTrackQueue(queue, current: track)
        }
        PlayHistoryStore.shared.record(artist: track.artist, title: track.title)
        PreviewPrefetcher.prefetch(track)

        MiniPlayerWindowController.shared.showPending(track: track)
        MenuBarModel.shared.setPending(track)

        guard let state = await PlaybackEngine.shared.play(track: track) else {
            MiniPlayerWindowController.shared.hide()
            MenuBarModel.shared.refresh()
            return
        }

        MiniPlayerWindowController.shared.show(state: state, track: track, morph: false)
        MenuBarModel.shared.refresh()
        PocketMusicUIState.shared.refreshNowPlaying()
    }

    static func playOffline(_ item: OfflineTrack) async {
        let display = item.asTrack
        MiniPlayerWindowController.shared.showPending(track: display)
        MenuBarModel.shared.setPending(display)

        guard let state = await PlaybackEngine.shared.playOffline(item) else {
            MiniPlayerWindowController.shared.hide()
            MenuBarModel.shared.refresh()
            return
        }

        MiniPlayerWindowController.shared.show(state: state, track: display)
        MenuBarModel.shared.refresh()
        PocketMusicUIState.shared.refreshNowPlaying()
    }
}
