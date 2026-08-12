import Foundation

struct Track: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let title: String
    let artist: String
    let url: String
    let duration: Int?
    let thumbnailURL: String?

    var durationText: String {
        guard let duration else { return "?:??" }
        return String(format: "%d:%02d", duration / 60, duration % 60)
    }

    var bestThumbnailURL: String {
        if let thumbnailURL, !thumbnailURL.isEmpty { return thumbnailURL }
        guard !id.hasPrefix("am-") else { return "" }
        return "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg"
    }

    var needsPlaybackResolve: Bool { url.isEmpty }

    var playbackQuery: String { "\(artist) \(title)" }

    var stableKey: String { "\(artist)|\(title)".lowercased() }
}

struct PlaybackState: Codable, Sendable {
    var trackId: String
    var title: String
    var artist: String
    var url: String
    var thumbnailPath: String
    var previewVideoURL: String?
    var previewIsVideo: Bool
    var mpvPID: Int32
    var paused: Bool
}

enum PocketPaths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let dir = home.appendingPathComponent(".pocketmusic", isDirectory: true)
    static let mpvSocket = dir.appendingPathComponent("mpv.sock")
    static let stateFile = dir.appendingPathComponent("state.json")
    static let favoritesFile = dir.appendingPathComponent("favorites.json")
    static let playlistsFile = dir.appendingPathComponent("pocketmix.json")
    static let playHistoryFile = dir.appendingPathComponent("play_history.json")
    static let offlineDir = dir.appendingPathComponent("offline", isDirectory: true)
    static let offlineIndexFile = dir.appendingPathComponent("offline.json")

    static func ensure() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

enum ToolLocator {
    static func path(_ names: [String]) -> String {
        for name in names {
            let brew = "/opt/homebrew/bin/\(name)"
            if FileManager.default.isExecutableFile(atPath: brew) { return brew }
            let usr = "/usr/local/bin/\(name)"
            if FileManager.default.isExecutableFile(atPath: usr) { return usr }
        }
        return "/opt/homebrew/bin/\(names[0])"
    }

    static var ytDlp: String { path(["yt-dlp"]) }
    static var mpv: String { path(["mpv"]) }
}
