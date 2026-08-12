import Foundation

struct CatalogMatch: Sendable {
    enum PreviewKind: Sendable {
        case video
        case audio
    }

    let previewURL: URL
    let previewKind: PreviewKind
    let artworkURL: URL
    let trackName: String
    let artistName: String

    var isVideo: Bool { previewKind == .video }
}

enum CatalogService {
    private static var videoCache: [String: CatalogMatch] = [:]
    private static var songCache: [String: CatalogMatch] = [:]
    private static let lock = NSLock()

    static func match(for track: Track) async -> CatalogMatch? {
        await fastMatch(for: track)
    }

    /// Paralel TR+US arama, video öncelikli
    static func fastMatch(for track: Track) async -> CatalogMatch? {
        if let video = await videoMatch(for: track) { return video }
        return await songMatch(for: track)
    }

    static func videoMatch(for track: Track) async -> CatalogMatch? {
        let key = cacheKey(track)
        lock.lock()
        if let hit = videoCache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let result = await Task.detached(priority: .utility) {
            runVideoLookup(track: track)
        }.value

        if let result {
            lock.lock()
            videoCache[key] = result
            lock.unlock()
        }
        return result
    }

    static func songMatch(for track: Track) async -> CatalogMatch? {
        let key = cacheKey(track)
        lock.lock()
        if let hit = songCache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let result = await Task.detached(priority: .utility) {
            runSongLookup(track: track)
        }.value

        if let result {
            lock.lock()
            songCache[key] = result
            lock.unlock()
        }
        return result
    }

    static func artworkURL(artist: String, title: String) async -> URL? {
        let stub = Track(
            id: "lookup",
            title: title,
            artist: artist,
            url: "",
            duration: nil,
            thumbnailURL: nil
        )
        return await songMatch(for: stub)?.artworkURL
    }

    /// Apple Music katalog araması — sadece metadata/kapak, oynatma değil
    static func catalogSearch(query: String, limit: Int = 25) async -> [Track] {
        await Task.detached(priority: .userInitiated) {
            runCatalogSearch(query: query, limit: limit)
        }.value
    }

    private static func runCatalogSearch(query: String, limit: Int) -> [Track] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=\(limit)&country=TR")
        else { return [] }

        var request = URLRequest(url: url)
        request.setValue("PocketMusic/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        guard let data = syncFetch(request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]]
        else { return [] }

        return results.compactMap { parseCatalogItem($0) }
    }

    private static func parseCatalogItem(_ item: [String: Any]) -> Track? {
        guard (item["kind"] as? String) == "song" || item["wrapperType"] as? String == "track",
              let title = item["trackName"] as? String,
              let artist = item["artistName"] as? String,
              !title.isEmpty
        else { return nil }

        let trackId = (item["trackId"] as? Int)
            ?? (item["trackId"] as? NSNumber)?.intValue
            ?? abs("\(artist)-\(title)".hashValue)

        let art100 = item["artworkUrl100"] as? String ?? ""
        let art600 = art100
            .replacingOccurrences(of: "100x100bb", with: "600x600bb")
            .replacingOccurrences(of: "100x100", with: "600x600")

        let durationMs = (item["trackTimeMillis"] as? Int)
            ?? (item["trackTimeMillis"] as? NSNumber)?.intValue

        return Track(
            id: "am-\(trackId)",
            title: title,
            artist: artist,
            url: "",
            duration: durationMs.map { $0 / 1000 },
            thumbnailURL: art600.isEmpty ? nil : art600
        )
    }

    static func track(from item: BrowseItem) -> Track {
        Track(
            id: "am-\(item.id)",
            title: item.title,
            artist: item.artist,
            url: "",
            duration: nil,
            thumbnailURL: item.artworkURL.absoluteString
        )
    }

    private static func cacheKey(_ track: Track) -> String {
        "\(track.artist)|\(track.title)".lowercased()
    }

    private static func runVideoLookup(track: Track) -> CatalogMatch? {
        let terms = Array(searchTerms(for: track).prefix(2))
        let countries = ["TR", "US"]

        // Paralel: tüm ülke+terim kombinasyonları
        let group = DispatchGroup()
        let lock = NSLock()
        var best: CatalogMatch?

        for country in countries {
            for term in terms {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    defer { group.leave() }
                    if let match = search(track: track, term: term, entity: "musicVideo", country: country, kind: .video, minScore: 18) {
                        lock.lock()
                        if best == nil { best = match }
                        lock.unlock()
                    }
                }
            }
        }
        group.wait()
        return best
    }

    private static func runSongLookup(track: Track) -> CatalogMatch? {
        let terms = searchTerms(for: track)
        for term in terms {
            if let match = search(track: track, term: term, entity: "song", country: "TR", kind: .audio, minScore: 28) {
                return match
            }
        }
        return nil
    }

    private static func searchTerms(for track: Track) -> [String] {
        let clean = cleanTitle(track.title)
        var terms = ["\(track.artist) \(clean)", "\(track.artist) \(track.title)", clean]
        if clean != track.title {
            terms.append(track.title)
        }
        var seen = Set<String>()
        return terms.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func cleanTitle(_ title: String) -> String {
        var t = title
        for sep in [" | ", " – ", " — "] {
            if let range = t.range(of: sep) {
                t = String(t[..<range.lowerBound])
            }
        }
        for suffix in [" Official Video", " Official Music Video", " Lyric Video", " LIVE SESSIONS", " Live"] {
            if t.hasSuffix(suffix) {
                t = String(t.dropLast(suffix.count))
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func search(
        track: Track,
        term: String,
        entity: String,
        country: String,
        kind: CatalogMatch.PreviewKind,
        minScore: Int
    ) -> CatalogMatch? {
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=\(entity)&limit=15&country=\(country)")
        else { return nil }

        var request = URLRequest(url: url)
        request.setValue("PocketMusic/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        guard let data = syncFetch(request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]]
        else { return nil }

        let targetTitle = normalize(cleanTitle(track.title))
        let targetArtist = normalize(track.artist)

        var bestScore = -1
        var bestItem: [String: Any]?

        for item in results {
            if kind == .video, (item["kind"] as? String) != "music-video" { continue }
            guard let previewStr = item["previewUrl"] as? String,
                  let previewURL = URL(string: previewStr)
            else { continue }
            if kind == .video, !isVideoPreviewURL(previewURL) { continue }

            let name = normalize(item["trackName"] as? String ?? "")
            let artist = normalize(item["artistName"] as? String ?? "")
            let score = scoreMatch(title: name, artist: artist, targetTitle: targetTitle, targetArtist: targetArtist)

            if score > bestScore {
                bestScore = score
                bestItem = item
            }
        }

        guard bestScore >= minScore,
              let bestItem,
              let previewStr = bestItem["previewUrl"] as? String,
              let previewURL = URL(string: previewStr)
        else { return nil }

        return CatalogMatch(
            previewURL: previewURL,
            previewKind: kind,
            artworkURL: bestArtwork(from: bestItem),
            trackName: bestItem["trackName"] as? String ?? term,
            artistName: bestItem["artistName"] as? String ?? ""
        )
    }

    private static func syncFetch(_ request: URLRequest) -> Data? {
        let sem = DispatchSemaphore(value: 0)
        var payload: Data?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            payload = data
            sem.signal()
        }.resume()
        sem.wait()
        return payload
    }

    private static func isVideoPreviewURL(_ url: URL) -> Bool {
        let path = url.absoluteString.lowercased()
        return path.contains(".m4v") || path.contains("mzvf_") || path.contains("video-ssl.itunes.apple.com")
    }

    private static func scoreMatch(title: String, artist: String, targetTitle: String, targetArtist: String) -> Int {
        var score = 0
        if !targetTitle.isEmpty {
            if title == targetTitle { score += 50 }
            else if title.contains(targetTitle) || targetTitle.contains(title) { score += 28 }
        }
        if !targetArtist.isEmpty {
            if artist == targetArtist { score += 40 }
            else if artist.contains(targetArtist) || targetArtist.contains(artist) { score += 22 }
        }
        return score
    }

    private static func bestArtwork(from item: [String: Any]) -> URL {
        if let url600 = item["artworkUrl600"] as? String, let u = URL(string: url600) { return u }
        if let url100 = item["artworkUrl100"] as? String {
            let hi = url100.replacingOccurrences(of: "100x100bb", with: "600x600bb")
            return URL(string: hi) ?? URL(string: url100)!
        }
        return URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music/0/0/0/600x600bb.jpg")!
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}
