import Combine
import Foundation

@MainActor
final class PlayHistoryStore: ObservableObject {
    static let shared = PlayHistoryStore()

    @Published private(set) var counts: [String: Int] = [:]

    private init() {
        load()
    }

    static func key(artist: String, title: String) -> String {
        "\(artist)|\(title)".lowercased()
    }

    func count(for entry: PlaylistEntry) -> Int {
        counts[Self.key(artist: entry.artist, title: entry.title), default: 0]
    }

    func record(artist: String, title: String) {
        let key = Self.key(artist: artist, title: title)
        counts[key, default: 0] += 1
        save()
    }

    func topEntry(in entries: [PlaylistEntry]) -> PlaylistEntry? {
        entries.max { count(for: $0) < count(for: $1) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: PocketPaths.playHistoryFile),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return }
        counts = decoded
    }

    private func save() {
        PocketPaths.ensure()
        if let data = try? JSONEncoder().encode(counts) {
            try? data.write(to: PocketPaths.playHistoryFile)
        }
    }
}
