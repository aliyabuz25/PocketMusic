import AppKit
import Combine

@MainActor
final class MenuBarModel: ObservableObject {
    static let shared = MenuBarModel()

    @Published private(set) var trackTitle = "Parça yok"
    @Published private(set) var artistTitle = "Ara → isim yaz → Enter"
    @Published private(set) var playLabel = "Oynat"
    @Published private(set) var playIcon = "play.fill"
    @Published private(set) var hasTrack = false
    @Published private(set) var menuBarImage: NSImage?
    @Published private(set) var progress: Double = 0
    @Published private(set) var elapsedText = "0:00"
    @Published private(set) var durationText = "0:00"
    @Published private(set) var isFavorite = false
    @Published private(set) var isBuffering = false
    @Published private(set) var catalogTrack: Track?

    private var pollTimer: Timer?
    private var trackQueue: [Track] = []
    private var queueIndex = 0
    private var playlistQueue: [PlaylistEntry] = []
    private var playlistQueueIndex = 0
    private enum QueueMode { case tracks, playlist, browse, none }
    private var queueMode: QueueMode = .none
    private var browseQueue: [BrowseItem] = []
    private var browseQueueIndex = 0

    private init() {}

    func start() {
        refresh()
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                if let state = PlaybackEngine.shared.state, PlaybackEngine.shared.isAlive {
                    if MiniPlayerWindowController.shared.window?.isVisible != true {
                        MiniPlayerWindowController.shared.show(
                            state: state,
                            track: PlaybackEngine.shared.currentTrack
                        )
                    }
                }
            }
        }
    }

    func configureTrackQueue(_ tracks: [Track], current: Track) {
        trackQueue = tracks
        queueIndex = tracks.firstIndex(where: { $0.id == current.id }) ?? 0
        queueMode = tracks.count > 1 ? .tracks : .none
    }

    func configurePlaylistQueue(_ entries: [PlaylistEntry], current: PlaylistEntry) {
        playlistQueue = entries
        playlistQueueIndex = entries.firstIndex(where: { $0.id == current.id }) ?? 0
        queueMode = entries.count > 1 ? .playlist : .none
    }

    func configureBrowseQueue(_ items: [BrowseItem], current: BrowseItem) {
        browseQueue = items
        browseQueueIndex = items.firstIndex(where: { $0.id == current.id }) ?? 0
        queueMode = items.count > 1 ? .browse : .none
    }

    func setPending(_ track: Track) {
        catalogTrack = track
        hasTrack = true
        isBuffering = true
        trackTitle = String(track.title.prefix(55))
        artistTitle = String(track.artist.prefix(55))
        playLabel = "Yükleniyor"
        playIcon = "pause.fill"
        progress = 0
        elapsedText = "0:00"
        durationText = "--:--"

        if let thumb = track.thumbnailURL, let url = URL(string: thumb),
           let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
            img.size = NSSize(width: 52, height: 52)
            menuBarImage = img
        }
    }

    func refresh() {
        isBuffering = false
        guard let state = PlaybackEngine.shared.state, PlaybackEngine.shared.isAlive else {
            trackTitle = "Parça yok"
            artistTitle = "Ara → isim yaz → Enter"
            playLabel = "Oynat"
            playIcon = "play.fill"
            hasTrack = false
            menuBarImage = nil
            progress = 0
            elapsedText = "0:00"
            durationText = "0:00"
            isFavorite = false
            catalogTrack = nil
            return
        }

        hasTrack = true
        trackTitle = String(state.title.prefix(55))
        artistTitle = String(state.artist.prefix(55))
        progress = PlaybackEngine.shared.progress()
        elapsedText = PlaybackEngine.shared.timeText(position: true)
        durationText = PlaybackEngine.shared.timeText(position: false)

        if PlaybackEngine.shared.isPaused {
            playLabel = "Oynat"
            playIcon = "play.fill"
        } else {
            playLabel = "Duraklat"
            playIcon = "pause.fill"
        }

        if let track = catalogTrack ?? PlaybackEngine.shared.currentTrack {
            isFavorite = FavoritesStore.shared.isFavorite(track)
        }

        if FileManager.default.fileExists(atPath: state.thumbnailPath),
           let img = NSImage(contentsOfFile: state.thumbnailPath) {
            img.size = NSSize(width: 52, height: 52)
            menuBarImage = img
        } else {
            menuBarImage = nil
        }
    }

    func togglePlay() {
        guard PlaybackEngine.shared.state != nil else { return }
        PlaybackEngine.shared.togglePause()
        refresh()
    }

    func stop() {
        PlaybackEngine.shared.stop()
        MiniPlayerWindowController.shared.hide()
        trackQueue = []
        playlistQueue = []
        browseQueue = []
        catalogTrack = nil
        queueMode = .none
        refresh()
    }

    func seek(to ratio: Double) {
        PlaybackEngine.shared.seek(ratio: ratio)
        refresh()
    }

    func skipBack() {
        PlaybackEngine.shared.skip(by: -15)
        refresh()
    }

    func skipForward() {
        PlaybackEngine.shared.skip(by: 15)
        refresh()
    }

    func toggleFavorite() {
        guard let track = catalogTrack ?? PlaybackEngine.shared.currentTrack else { return }
        FavoritesStore.shared.toggle(track)
        isFavorite = FavoritesStore.shared.isFavorite(track)
    }

    func playNext() async {
        switch queueMode {
        case .tracks:
            guard queueIndex + 1 < trackQueue.count else { return }
            queueIndex += 1
            await PlaylistStore.shared.playTrack(trackQueue[queueIndex], queue: trackQueue)
        case .playlist:
            guard playlistQueueIndex + 1 < playlistQueue.count else { return }
            playlistQueueIndex += 1
            await PlaylistStore.shared.play(playlistQueue[playlistQueueIndex], queue: playlistQueue)
        case .browse:
            guard browseQueueIndex + 1 < browseQueue.count else { return }
            browseQueueIndex += 1
            await BrowseService.play(browseQueue[browseQueueIndex], queue: browseQueue)
        case .none:
            break
        }
    }

    func downloadCurrentTrack() async {
        guard let track = catalogTrack ?? PlaybackEngine.shared.currentTrack else { return }
        _ = await OfflineStore.shared.download(track)
    }
}

extension MenuBarModel {
    func setup() { start() }
}
