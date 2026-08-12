import AppIntents
import CoreSpotlight
import Foundation

struct MusicTrackEntity: AppEntity, IndexedEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Müzik")
    static var defaultQuery = MusicTrackQuery()

    var id: String
    var title: String
    var artist: String
    var url: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(artist)")
    }
}

struct MusicTrackQuery: EntityStringQuery {
    func entities(for identifiers: [MusicTrackEntity.ID]) async throws -> [MusicTrackEntity] {
        var result: [MusicTrackEntity] = []
        for id in identifiers {
            guard let track = await TrackStore.shared.track(id: id) else { continue }
            result.append(MusicTrackEntity(id: track.id, title: track.title, artist: track.artist, url: track.url))
        }
        return result
    }

    func entities(matching string: String) async throws -> [MusicTrackEntity] {
        let tracks = try await YouTubeSearch.search(query: string, limit: 10)
        await TrackStore.shared.save(tracks)
        try await SpotlightIndexer.index(tracks)
        return tracks.map {
            MusicTrackEntity(id: $0.id, title: $0.title, artist: $0.artist, url: $0.url)
        }
    }

    func suggestedEntities() async throws -> [MusicTrackEntity] {
        let recent = await TrackStore.shared.recent()
        return recent.map {
            MusicTrackEntity(id: $0.id, title: $0.title, artist: $0.artist, url: $0.url)
        }
    }
}

struct OpenMusicTrackIntent: OpenIntent {
    static var title: LocalizedStringResource = "Müziği Aç"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Parça")
    var target: MusicTrackEntity

    func perform() async throws -> some IntentResult {
        await PlayerBridge.play(trackID: target.id)
        return .result()
    }
}

struct PlayMusicIntent: AppIntent {
    static var title: LocalizedStringResource = "Müzik Oynat"
    static var description = IntentDescription("Spotlight'tan müzik ara ve anında oynat.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Parça", requestValueDialog: "Hangi müziği oynatmak istiyorsun?")
    var track: MusicTrackEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Oynat \(\.$track)")
    }

    func perform() async throws -> some IntentResult {
        await PlayerBridge.play(trackID: track.id)
        return .result(dialog: "Oynatılıyor: \(track.title)")
    }
}

struct SearchMusicIntent: AppIntent {
    static var title: LocalizedStringResource = "Müzik Ara"
    static var description = IntentDescription("YouTube'da müzik ara ve Spotlight'a ekle.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Arama")
    var query: String

    func perform() async throws -> some IntentResult {
        let tracks = try await YouTubeSearch.search(query: query, limit: 10)
        await TrackStore.shared.save(tracks)
        try await SpotlightIndexer.index(tracks)
        return .result(dialog: "\(tracks.count) sonuç Spotlight'a eklendi.")
    }
}

struct PocketMusicShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayMusicIntent(),
            phrases: [
                "\(.applicationName) oynat",
                "\(.applicationName) ile oynat",
                "Oynat \(\.$track) \(.applicationName) ile",
            ],
            shortTitle: "Müzik Oynat",
            systemImageName: "music.note"
        )
        AppShortcut(
            intent: SearchMusicIntent(),
            phrases: [
                "\(.applicationName) ara",
                "\(.applicationName) müzik ara",
            ],
            shortTitle: "Müzik Ara",
            systemImageName: "magnifyingglass"
        )
    }
}
