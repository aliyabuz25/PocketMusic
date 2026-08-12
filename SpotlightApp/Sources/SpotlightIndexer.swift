import CoreSpotlight
import Foundation

enum SpotlightIndexer {
    static func index(_ tracks: [TrackRecord]) async throws {
        let entities = tracks.map { track in
            MusicTrackEntity(id: track.id, title: track.title, artist: track.artist, url: track.url)
        }
        try await CSSearchableIndex.default().indexAppEntities(entities)
    }
}
