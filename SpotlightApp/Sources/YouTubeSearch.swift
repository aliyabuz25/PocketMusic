import Foundation

struct TrackRecord: Codable, Sendable {
    let id: String
    let title: String
    let artist: String
    let url: String
    let thumbnailURL: String?
}

enum YouTubeSearch {
    static func search(query: String, limit: Int = 10) async throws -> [TrackRecord] {
        let ytdlp = ToolPath.ytDlp
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlp)
        process.arguments = [
            "ytsearch\(limit):\(query)",
            "--flat-playlist",
            "--dump-single-json",
            "--no-warnings",
            "--quiet",
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var tracks: [TrackRecord] = []
        for line in text.split(separator: "\n") {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                continue
            }
            if json["_type"] as? String == "playlist", let entries = json["entries"] as? [[String: Any]] {
                for entry in entries {
                    if let track = parseEntry(entry) { tracks.append(track) }
                }
            } else if let track = parseEntry(json) {
                tracks.append(track)
            }
        }
        return tracks
    }

    private static func parseEntry(_ entry: [String: Any]) -> TrackRecord? {
        let id = (entry["id"] as? String) ?? (entry["url"] as? String)?.split(separator: "=").last.map(String.init)
        guard let id, !id.isEmpty else { return nil }
        let title = entry["title"] as? String ?? "Bilinmeyen"
        let artist = (entry["uploader"] as? String) ?? (entry["channel"] as? String) ?? "?"
        var thumb = entry["thumbnail"] as? String
        if thumb == nil, let thumbs = entry["thumbnails"] as? [[String: Any]], let last = thumbs.last {
            thumb = last["url"] as? String
        }
        return TrackRecord(
            id: id,
            title: title,
            artist: artist,
            url: "https://www.youtube.com/watch?v=\(id)",
            thumbnailURL: thumb
        )
    }
}

enum ToolPath {
    static var ytDlp: String {
        for path in ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/opt/homebrew/bin/yt-dlp"
    }

    static var python: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let venv = "\(home)/PocketMusic/.venv/bin/python3"
        if FileManager.default.isExecutableFile(atPath: venv) { return venv }
        return "/usr/bin/python3"
    }

    static var playScript: String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/PocketMusic/play_id.py"
    }
}

actor TrackStore {
    static let shared = TrackStore()
    private let cacheURL: URL

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pocketmusic")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheURL = dir.appendingPathComponent("spotlight-tracks.json")
    }

    func save(_ tracks: [TrackRecord]) {
        var map = loadMap()
        for t in tracks { map[t.id] = t }
        persist(map)
    }

    func track(id: String) -> TrackRecord? {
        loadMap()[id]
    }

    func recent(limit: Int = 10) -> [TrackRecord] {
        Array(loadMap().values.prefix(limit))
    }

    private func loadMap() -> [String: TrackRecord] {
        guard let data = try? Data(contentsOf: cacheURL),
              let map = try? JSONDecoder().decode([String: TrackRecord].self, from: data) else {
            return [:]
        }
        return map
    }

    private func persist(_ map: [String: TrackRecord]) {
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: cacheURL)
        }
    }
}

enum PlayerBridge {
    static func play(trackID: String) async {
        let python = ToolPath.python
        let script = ToolPath.playScript
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [script, trackID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
