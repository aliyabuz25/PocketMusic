import Combine
import Foundation

struct OfflineTrack: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let title: String
    let artist: String
    let thumbnailURL: String?
    let downloadedAt: Date
    let fileName: String

    var asTrack: Track {
        Track(
            id: "offline-\(id)",
            title: title,
            artist: artist,
            url: "",
            duration: nil,
            thumbnailURL: thumbnailURL
        )
    }
}

@MainActor
final class OfflineStore: ObservableObject {
    static let shared = OfflineStore()

    @Published private(set) var items: [OfflineTrack] = []
    @Published private(set) var downloadingIDs: Set<String> = []

    private init() { load() }

    func hasOffline(stableKey: String) -> Bool {
        items.contains { $0.id == stableKey }
    }

    func isDownloading(stableKey: String) -> Bool {
        downloadingIDs.contains(stableKey)
    }

    func download(_ track: Track) async -> Bool {
        let key = track.stableKey
        guard !hasOffline(stableKey: key), !downloadingIDs.contains(key) else { return false }

        downloadingIDs.insert(key)
        defer { downloadingIDs.remove(key) }

        guard let resolved = await MusicService.resolveForPlayback(track),
              let audio = await MusicService.downloadAudioData(for: resolved)
        else { return false }

        do {
            let encrypted = try PocketCrypto.encrypt(audio)
            PocketPaths.ensure()
            try FileManager.default.createDirectory(at: PocketPaths.offlineDir, withIntermediateDirectories: true)

            let fileName = "\(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key).pmenc"
            let fileURL = PocketPaths.offlineDir.appendingPathComponent(fileName)
            try encrypted.write(to: fileURL, options: .atomic)

            let entry = OfflineTrack(
                id: key,
                title: track.title,
                artist: track.artist,
                thumbnailURL: track.thumbnailURL,
                downloadedAt: Date(),
                fileName: fileName
            )
            items.insert(entry, at: 0)
            save()
            return true
        } catch {
            return false
        }
    }

    func decryptedPlayURL(for item: OfflineTrack) throws -> URL {
        let encURL = PocketPaths.offlineDir.appendingPathComponent(item.fileName)
        let encrypted = try Data(contentsOf: encURL)
        let plain = try PocketCrypto.decrypt(encrypted)

        let temp = PocketPaths.offlineDir.appendingPathComponent(".play_\(UUID().uuidString).m4a")
        try plain.write(to: temp, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
        return temp
    }

    func remove(_ item: OfflineTrack) {
        let path = PocketPaths.offlineDir.appendingPathComponent(item.fileName)
        try? FileManager.default.removeItem(at: path)
        items.removeAll { $0.id == item.id }
        save()
    }

    func play(_ item: OfflineTrack) async {
        await PlaybackLauncher.playOffline(item)
    }

    private func load() {
        guard let data = try? Data(contentsOf: PocketPaths.offlineIndexFile),
              let decoded = try? JSONDecoder().decode([OfflineTrack].self, from: data)
        else { return }
        items = decoded.filter {
            FileManager.default.fileExists(atPath: PocketPaths.offlineDir.appendingPathComponent($0.fileName).path)
        }
    }

    private func save() {
        PocketPaths.ensure()
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: PocketPaths.offlineIndexFile)
        }
    }
}
