import Foundation

enum BrowseService {
    private static let base = "https://rss.applemarketingtools.com/api/v2/tr/music/most-played"

    static func fetchTopSongs(limit: Int = 50) async -> [BrowseItem] {
        await fetchFeed(path: "\(limit)/songs")
    }

    static func fetchTopAlbums(limit: Int = 25) async -> [BrowseItem] {
        await fetchFeed(path: "\(limit)/albums")
    }

    private static func fetchFeed(path: String) async -> [BrowseItem] {
        await Task.detached(priority: .userInitiated) {
            runFetch(path: path)
        }.value
    }

    private static func runFetch(path: String) -> [BrowseItem] {
        guard let url = URL(string: "\(base)/\(path).json") else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("PocketMusic/2.0", forHTTPHeaderField: "User-Agent")

        let sem = DispatchSemaphore(value: 0)
        var data: Data?
        URLSession.shared.dataTask(with: request) { payload, _, _ in
            data = payload
            sem.signal()
        }.resume()
        sem.wait()

        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = json["feed"] as? [String: Any],
              let results = feed["results"] as? [[String: Any]]
        else { return [] }

        return results.enumerated().compactMap { idx, item in
            parseItem(item, index: idx)
        }
    }

    private static func parseItem(_ item: [String: Any], index: Int) -> BrowseItem? {
        let title = (item["name"] as? String) ?? (item["collectionName"] as? String)
        let artist = item["artistName"] as? String
        guard let title, let artist, !title.isEmpty else { return nil }

        let art = (item["artworkUrl100"] as? String) ?? ""
        let hiRes = art
            .replacingOccurrences(of: "100x100bb", with: "600x600bb")
            .replacingOccurrences(of: "100x100", with: "600x600")
        let artURL = URL(string: hiRes) ?? URL(string: art) ?? URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music/0/0/0/600x600bb.jpg")!

        let genre = (item["genres"] as? [[String: Any]])?.first?["name"] as? String ?? "Pop"
        let link = (item["url"] as? String).flatMap(URL.init(string:))
        let appleId = item["id"] as? String ?? "\(index)"
        let kind = item["kind"] as? String ?? "song"

        return BrowseItem(
            id: "\(kind)-\(appleId)",
            title: title,
            artist: artist,
            artworkURL: artURL,
            genre: genre,
            appleMusicURL: link
        )
    }

    static func play(_ item: BrowseItem, queue: [BrowseItem]? = nil) async {
        let catalog = CatalogService.track(from: item)
        let q = queue ?? [item]
        await MainActor.run {
            MenuBarModel.shared.configureBrowseQueue(q, current: item)
        }
        await PlaylistStore.shared.playTrack(catalog)
    }
}