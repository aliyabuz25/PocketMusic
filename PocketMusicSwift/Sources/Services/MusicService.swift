import Foundation

enum MusicService {
    /// Apple Music kataloğunda ara (kapak + metadata)
    static func search(query: String) async -> Track? {
        await searchMultiple(query: query, limit: 1).first
    }

    static func searchMultiple(query: String, limit: Int = 12) async -> [Track] {
        await CatalogService.catalogSearch(query: query, limit: limit)
    }

    /// Katalog parçasını YouTube stream'e çöz — oynatıcı buradan beslenir
    static func resolveForPlayback(_ track: Track) async -> Track? {
        if !track.needsPlaybackResolve { return track }
        guard let yt = await youtubeSearch(query: track.playbackQuery, limit: 1).first else { return nil }
        return Track(
            id: yt.id,
            title: track.title,
            artist: track.artist,
            url: yt.url,
            duration: track.duration ?? yt.duration,
            thumbnailURL: track.thumbnailURL ?? yt.thumbnailURL
        )
    }

    static func catalogPreview(for track: Track) async -> CatalogMatch? {
        await CatalogService.match(for: track)
    }

    static func catalogVideoPreview(for track: Track) async -> CatalogMatch? {
        await CatalogService.videoMatch(for: track)
    }

    static func catalogArtworkURL(for track: Track) async -> URL? {
        if let thumb = track.thumbnailURL, let url = URL(string: thumb) { return url }
        if let video = await CatalogService.videoMatch(for: track) { return video.artworkURL }
        return await CatalogService.songMatch(for: track)?.artworkURL
    }

    static func downloadCatalogCover(for track: Track) async -> String? {
        if let thumb = track.thumbnailURL, let url = URL(string: thumb),
           let data = try? Data(contentsOf: url), !data.isEmpty {
            PocketPaths.ensure()
            let out = PocketPaths.dir.appendingPathComponent("\(track.id)_am_cover.jpg")
            try? data.write(to: out)
            return out.path
        }

        guard let url = await catalogArtworkURL(for: track),
              let data = try? Data(contentsOf: url),
              !data.isEmpty
        else { return nil }

        PocketPaths.ensure()
        let out = PocketPaths.dir.appendingPathComponent("\(track.id)_am_cover.jpg")
        try? data.write(to: out)
        return out.path
    }

    private static func youtubeSearch(query: String, limit: Int) async -> [Track] {
        await Task.detached(priority: .userInitiated) {
            runYouTubeSearch(query: query, limit: limit)
        }.value
    }

    private static func runYouTubeSearch(query: String, limit: Int) -> [Track] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ToolLocator.ytDlp)
        proc.arguments = [
            "ytsearch\(limit):\(query)",
            "--flat-playlist",
            "--dump-single-json",
            "--no-warnings",
            "--quiet",
        ]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return []
        }
        guard proc.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return parseYouTubeJSONLines(text)
    }

    private static func parseYouTubeJSONLines(_ text: String) -> [Track] {
        var tracks: [Track] = []
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if json["_type"] as? String == "playlist", let entries = json["entries"] as? [[String: Any]] {
                for entry in entries {
                    if let t = parseYouTubeEntry(entry) { tracks.append(t) }
                }
            } else if let t = parseYouTubeEntry(json) {
                tracks.append(t)
            }
        }
        return tracks
    }

    private static func parseYouTubeEntry(_ entry: [String: Any]) -> Track? {
        let id = (entry["id"] as? String)
            ?? ((entry["url"] as? String)?.split(separator: "=").last.map(String.init))
        guard let id, !id.isEmpty else { return nil }
        let title = entry["title"] as? String ?? "Bilinmeyen"
        let artist = (entry["uploader"] as? String) ?? (entry["channel"] as? String) ?? "?"
        var thumb = entry["thumbnail"] as? String
        if thumb == nil, let thumbs = entry["thumbnails"] as? [[String: Any]] {
            thumb = thumbs.compactMap { $0["url"] as? String }.max(by: { $0.count < $1.count })
        }
        return Track(
            id: id,
            title: title,
            artist: artist,
            url: "https://www.youtube.com/watch?v=\(id)",
            duration: entry["duration"] as? Int,
            thumbnailURL: thumb ?? "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg"
        )
    }

    /// Doğrudan stream URL — mpv ytdl beklemez, daha hızlı başlar
    static func resolveStreamURL(for youtubeURL: String) async -> String? {
        await Task.detached(priority: .userInitiated) {
            runStreamURL(youtubeURL: youtubeURL)
        }.value
    }

    static func downloadAudioData(for track: Track) async -> Data? {
        await Task.detached(priority: .utility) {
            runDownloadAudio(for: track)
        }.value
    }

    private static func runStreamURL(youtubeURL: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ToolLocator.ytDlp)
        proc.arguments = [
            "-g",
            "-f", "bestaudio[ext=opus]/bestaudio/best",
            "--no-warnings", "--quiet",
            youtubeURL,
        ]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch { return nil }
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let url = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n").first
        else { return nil }
        return String(url)
    }

    private static func runDownloadAudio(for track: Track) -> Data? {
        PocketPaths.ensure()
        let base = PocketPaths.dir.appendingPathComponent("dl_\(UUID().uuidString)")
        let template = base.path + ".%(ext)s"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ToolLocator.ytDlp)
        proc.arguments = [
            "-x", "--audio-format", "m4a", "--audio-quality", "0",
            "-o", template,
            "--no-playlist", "--no-warnings", "--quiet",
            track.url,
        ]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch { return nil }
        guard proc.terminationStatus == 0 else { return nil }

        let dir = PocketPaths.dir
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]),
              let newest = files
                .filter({ $0.lastPathComponent.hasPrefix(base.lastPathComponent) })
                .max(by: { a, b in
                    let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return da < db
                })
        else { return nil }

        defer { try? FileManager.default.removeItem(at: newest) }
        return try? Data(contentsOf: newest)
    }

    static func downloadCover(for track: Track) -> String? {
        downloadImage(track: track, filename: "\(track.id)_icon.png", size: 22)
    }

    static func downloadCoverLarge(for track: Track) -> String? {
        if let thumb = track.thumbnailURL, !thumb.isEmpty,
           let url = URL(string: thumb),
           let data = try? Data(contentsOf: url),
           !data.isEmpty {
            PocketPaths.ensure()
            let out = PocketPaths.dir.appendingPathComponent("\(track.id)_cover.jpg")
            try? data.write(to: out)
            return out.path
        }
        return downloadImage(track: track, filename: "\(track.id)_cover.jpg", size: nil)
    }

    private static func downloadImage(track: Track, filename: String, size: Int?) -> String? {
        PocketPaths.ensure()
        let out = PocketPaths.dir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: out.path) { return out.path }

        let thumb = track.bestThumbnailURL
        guard !thumb.isEmpty else { return nil }

        let candidates = [
            thumb,
            "https://i.ytimg.com/vi/\(track.id)/maxresdefault.jpg",
            "https://i.ytimg.com/vi/\(track.id)/hqdefault.jpg",
        ]

        for thumbURL in candidates where !thumbURL.isEmpty {
            guard let url = URL(string: thumbURL),
                  let data = try? Data(contentsOf: url),
                  !data.isEmpty
            else { continue }

            let raw = PocketPaths.dir.appendingPathComponent("\(track.id)_tmp.jpg")
            do {
                try data.write(to: raw)
                if let size {
                    let sips = Process()
                    sips.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
                    sips.arguments = ["-z", "\(size)", "\(size)", raw.path, "--out", out.path]
                    sips.standardOutput = Pipe()
                    sips.standardError = Pipe()
                    try sips.run()
                    sips.waitUntilExit()
                    try? FileManager.default.removeItem(at: raw)
                    if FileManager.default.fileExists(atPath: out.path) { return out.path }
                } else {
                    try FileManager.default.moveItem(at: raw, to: out)
                    return out.path
                }
            } catch {
                continue
            }
        }
        return nil
    }
}
