import Combine
import Foundation

@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var items: [Track] = []

    private init() {
        load()
    }

    func isFavorite(id: String) -> Bool {
        items.contains { $0.id == id }
    }

    func isFavorite(_ track: Track) -> Bool {
        items.contains { $0.id == track.id || $0.stableKey == track.stableKey }
    }

    func toggle(_ track: Track) {
        if let idx = items.firstIndex(where: { $0.id == track.id || $0.stableKey == track.stableKey }) {
            items.remove(at: idx)
        } else {
            items.insert(track, at: 0)
        }
        save()
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
        save()
    }

    func play(_ track: Track) async {
        await PlaybackLauncher.play(track, queue: items)
    }

    private func load() {
        PocketPaths.ensure()
        guard let data = try? Data(contentsOf: PocketPaths.favoritesFile),
              let decoded = try? JSONDecoder().decode([Track].self, from: data)
        else { return }
        items = decoded
    }

    private func save() {
        PocketPaths.ensure()
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: PocketPaths.favoritesFile)
        }
    }
}
