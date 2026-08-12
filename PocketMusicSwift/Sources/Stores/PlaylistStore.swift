import Combine
import Foundation

@MainActor
final class PlaylistStore: ObservableObject {
    static let shared = PlaylistStore()

    @Published private(set) var pocketMix: Playlist
    @Published private(set) var artworkByEntryID: [String: URL] = [:]
    @Published private(set) var isLoadingArtwork = false

    private var artworkTask: Task<Void, Never>?

    private init() {
        pocketMix = Self.defaultMix
        load()
    }

    static let defaultMix = Playlist(
        id: "pocketmix",
        name: "En Favorimiz",
        icon: "heart.fill",
        entries: [
            .init(id: "1", title: "Palagi", artist: "TJ Monterde"),
            .init(id: "2", title: "Şımarık", artist: "Tarkan"),
            .init(id: "3", title: "Levitating", artist: "Dua Lipa"),
            .init(id: "4", title: "Blinding Lights", artist: "The Weeknd"),
            .init(id: "5", title: "Anti-Hero", artist: "Taylor Swift"),
            .init(id: "6", title: "Flowers", artist: "Miley Cyrus"),
            .init(id: "7", title: "Geceler", artist: "Ceza"),
            .init(id: "8", title: "Yalan", artist: "Hadise"),
            .init(id: "9", title: "Starboy", artist: "The Weeknd"),
            .init(id: "10", title: "As It Was", artist: "Harry Styles"),
        ]
    )

    var coverEntry: PlaylistEntry? {
        let history = PlayHistoryStore.shared
        if let top = history.topEntry(in: pocketMix.entries), history.count(for: top) > 0 {
            return top
        }
        return pocketMix.entries.first
    }

    func artwork(for entry: PlaylistEntry) -> URL? {
        artworkByEntryID[entry.id]
    }

    var coverArtworkURL: URL? {
        guard let entry = coverEntry else { return nil }
        return artwork(for: entry)
    }

    func prefetchArtwork() {
        artworkTask?.cancel()
        artworkTask = Task {
            isLoadingArtwork = true
            defer { isLoadingArtwork = false }

            await withTaskGroup(of: (String, URL?).self) { group in
                for entry in pocketMix.entries {
                    if artworkByEntryID[entry.id] != nil { continue }
                    group.addTask {
                        let url = await CatalogService.artworkURL(artist: entry.artist, title: entry.title)
                        return (entry.id, url)
                    }
                }

                for await (id, url) in group {
                    guard !Task.isCancelled, let url else { continue }
                    artworkByEntryID[id] = url
                }
            }
        }
    }

    func addToMix(title: String, artist: String) {
        let entry = PlaylistEntry(id: UUID().uuidString, title: title, artist: artist)
        guard !pocketMix.entries.contains(where: { $0.title == title && $0.artist == artist }) else { return }
        pocketMix.entries.insert(entry, at: 0)
        save()
        prefetchArtwork()
    }

    func removeFromMix(id: String) {
        pocketMix.entries.removeAll { $0.id == id }
        artworkByEntryID.removeValue(forKey: id)
        save()
    }

    func play(_ entry: PlaylistEntry, queue: [PlaylistEntry]? = nil) async {
        let catalog = Track(
            id: "am-pl-\(entry.id)",
            title: entry.title,
            artist: entry.artist,
            url: "",
            duration: nil,
            thumbnailURL: artwork(for: entry)?.absoluteString
        )
        let q = queue ?? pocketMix.entries
        MenuBarModel.shared.configurePlaylistQueue(q, current: entry)
        await playTrack(catalog)
    }

    func playTrack(_ track: Track, queue: [Track]? = nil) async {
        await PlaybackLauncher.play(track, queue: queue)
    }

    private func load() {
        guard let data = try? Data(contentsOf: PocketPaths.playlistsFile),
              let saved = try? JSONDecoder().decode(Playlist.self, from: data)
        else { return }
        pocketMix = saved
    }

    private func save() {
        PocketPaths.ensure()
        if let data = try? JSONEncoder().encode(pocketMix) {
            try? data.write(to: PocketPaths.playlistsFile)
        }
    }
}
