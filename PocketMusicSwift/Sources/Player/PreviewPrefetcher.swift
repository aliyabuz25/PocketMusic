import Foundation

struct CachedPreview: Sendable {
    let localURL: URL
    let isVideo: Bool
    let remoteURL: URL
}

enum PreviewPrefetcher {
    private static var cache: [String: CachedPreview] = [:]
    private static var tasks: [String: Task<CachedPreview?, Never>] = [:]
    private static let lock = NSLock()

    static func prefetch(_ track: Track) {
        lock.lock()
        if cache[track.id] != nil || tasks[track.id] != nil {
            lock.unlock()
            return
        }
        let task = Task.detached(priority: .userInitiated) {
            await build(track)
        }
        tasks[track.id] = task
        lock.unlock()
    }

    static func cached(for track: Track) -> CachedPreview? {
        lock.lock()
        defer { lock.unlock() }
        return cache[track.id]
    }

    static func wait(for track: Track) async -> CachedPreview? {
        if let hit = cached(for: track) { return hit }

        lock.lock()
        let existing = tasks[track.id]
        lock.unlock()

        if let existing { return await existing.value }

        prefetch(track)

        lock.lock()
        let task = tasks[track.id]
        lock.unlock()
        return await task?.value
    }

    private static func build(_ track: Track) async -> CachedPreview? {
        let match = await CatalogService.fastMatch(for: track)
        guard let match else {
            finish(trackId: track.id, result: nil)
            return nil
        }

        let streamURL = optimizeURL(match.previewURL, isVideo: match.isVideo)
        guard let local = download(streamURL, trackId: track.id, isVideo: match.isVideo) else {
            finish(trackId: track.id, result: nil)
            return nil
        }

        let item = CachedPreview(localURL: local, isVideo: match.isVideo, remoteURL: match.previewURL)
        finish(trackId: track.id, result: item)
        return item
    }

    private static func finish(trackId: String, result: CachedPreview?) {
        lock.lock()
        if let result { cache[trackId] = result }
        tasks.removeValue(forKey: trackId)
        lock.unlock()
    }

    private static func optimizeURL(_ url: URL, isVideo: Bool) -> URL {
        guard isVideo else { return url }
        let s = url.absoluteString
            .replacingOccurrences(of: "1920w", with: "640w")
            .replacingOccurrences(of: "1280w", with: "640w")
        return URL(string: s) ?? url
    }

    private static func download(_ url: URL, trackId: String, isVideo: Bool) -> URL? {
        PocketPaths.ensure()
        let ext = isVideo ? "m4v" : "m4a"
        let dest = PocketPaths.dir.appendingPathComponent("preview_\(trackId).\(ext)")
        if FileManager.default.fileExists(atPath: dest.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
           let size = attrs[.size] as? Int, size > 8_000 {
            return dest
        }

        var request = URLRequest(url: url)
        request.setValue("PocketMusic/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let sem = DispatchSemaphore(value: 0)
        var data: Data?
        URLSession.shared.dataTask(with: request) { payload, _, _ in
            data = payload
            sem.signal()
        }.resume()
        sem.wait()

        guard let data, data.count > 8_000 else { return nil }
        try? data.write(to: dest, options: .atomic)
        return dest
    }
}
