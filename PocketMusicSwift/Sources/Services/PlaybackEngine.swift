import Darwin
import Foundation

@MainActor
final class PlaybackEngine {
    static let shared = PlaybackEngine()

    private(set) var state: PlaybackState?
    private var mpvProcess: Process?
    private var tempPlayFile: URL?

    private init() {}

    func play(track: Track) async -> PlaybackState? {
        guard let track = await MusicService.resolveForPlayback(track) else { return nil }
        stop()
        PocketPaths.ensure()
        try? FileManager.default.removeItem(at: PocketPaths.mpvSocket)

        PreviewPrefetcher.prefetch(track)

        async let coverPath: String = Task.detached(priority: .utility) {
            MusicService.downloadCoverLarge(for: track)
                ?? MusicService.downloadCover(for: track)
                ?? ""
        }.value
        async let streamURL = MusicService.resolveStreamURL(for: track.url)

        let source = await streamURL ?? track.url

        guard launchMpv(source: source, useYtdl: streamURL == nil) else { return nil }

        let ok = await waitForPlayback(pid: mpvProcess?.processIdentifier ?? 0)
        guard ok else {
            stop()
            return nil
        }

        let cover = await coverPath
        var previewURL: String?
        var previewIsVideo = false
        if let cached = PreviewPrefetcher.cached(for: track) {
            previewURL = cached.localURL.absoluteString
            previewIsVideo = cached.isVideo
        }

        let playback = PlaybackState(
            trackId: track.id,
            title: track.title,
            artist: track.artist,
            url: track.url,
            thumbnailPath: cover,
            previewVideoURL: previewURL,
            previewIsVideo: previewIsVideo,
            mpvPID: Int32(mpvProcess?.processIdentifier ?? 0),
            paused: false
        )
        state = playback
        currentTrack = track
        saveState(playback)

        Task {
            if let cached = await PreviewPrefetcher.wait(for: track) {
                await MainActor.run {
                    guard self.state?.trackId == track.id else { return }
                    if var s = self.state {
                        s.previewVideoURL = cached.localURL.absoluteString
                        s.previewIsVideo = cached.isVideo
                        self.updateState(s)
                        MiniPlayerWindowController.shared.applyPreview(cached, trackId: track.id)
                    }
                }
            }
        }

        return playback
    }

    func playOffline(_ item: OfflineTrack) async -> PlaybackState? {
        stop()
        PocketPaths.ensure()
        try? FileManager.default.removeItem(at: PocketPaths.mpvSocket)

        do {
            let playURL = try OfflineStore.shared.decryptedPlayURL(for: item)
            tempPlayFile = playURL
            guard launchMpv(source: playURL.path, useYtdl: false) else { return nil }
        } catch {
            return nil
        }

        let ok = await waitForPlayback(pid: mpvProcess?.processIdentifier ?? 0)
        guard ok else {
            stop()
            return nil
        }

        let track = item.asTrack
        let playback = PlaybackState(
            trackId: track.id,
            title: track.title,
            artist: track.artist,
            url: "offline://\(item.id)",
            thumbnailPath: "",
            previewVideoURL: nil,
            previewIsVideo: false,
            mpvPID: Int32(mpvProcess?.processIdentifier ?? 0),
            paused: false
        )
        state = playback
        currentTrack = track
        saveState(playback)
        return playback
    }

    private func launchMpv(source: String, useYtdl: Bool) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ToolLocator.mpv)
        var args = [
            "--no-video",
            "--cache=no",
            "--demuxer-readahead-secs=0.25",
            "--input-ipc-server=\(PocketPaths.mpvSocket.path)",
        ]
        if useYtdl {
            args.insert(contentsOf: ["--ytdl-format=bestaudio[ext=opus]/bestaudio/best"], at: 0)
        } else {
            args.insert("--no-ytdl", at: 0)
        }
        args.append(source)

        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return false
        }
        mpvProcess = proc
        return true
    }

    private(set) var currentTrack: Track?

    func updateState(_ newState: PlaybackState) {
        state = newState
        saveState(newState)
    }

    func timeText(position: Bool) -> String {
        let key = position ? "time-pos" : "duration"
        guard let val = queryIPC(["get_property", key])?["data"] as? Double, val.isFinite else {
            return position ? "0:00" : "--:--"
        }
        let sec = Int(val)
        return String(format: "%d:%02d", sec / 60, sec % 60)
    }

    func stop() {
        sendIPC(["stop"])
        if let proc = mpvProcess, proc.isRunning {
            proc.terminate()
        }
        mpvProcess = nil
        if let temp = tempPlayFile {
            try? FileManager.default.removeItem(at: temp)
            tempPlayFile = nil
        }
        try? FileManager.default.removeItem(at: PocketPaths.mpvSocket)
        state = nil
        currentTrack = nil
        try? FileManager.default.removeItem(at: PocketPaths.stateFile)
    }

    func togglePause() {
        sendIPC(["cycle", "pause"])
        if var s = state {
            s.paused.toggle()
            if let resp = queryIPC(["get_property", "pause"]), let data = resp["data"] as? Bool {
                s.paused = data
            }
            state = s
            saveState(s)
        }
    }

    var isPaused: Bool {
        if let resp = queryIPC(["get_property", "pause"]), let data = resp["data"] as? Bool {
            return data
        }
        return state?.paused ?? false
    }

    var isAlive: Bool {
        guard let proc = mpvProcess else { return false }
        return proc.isRunning
    }

    var isBuffering: Bool {
        guard state != nil, !isAlive else { return false }
        return true
    }

    func progress() -> Double {
        guard let pos = queryIPC(["get_property", "time-pos"])?["data"] as? Double,
              let dur = queryIPC(["get_property", "duration"])?["data"] as? Double,
              dur > 0 else { return 0 }
        return min(1, max(0, pos / dur))
    }

    func seek(ratio: Double) {
        guard let dur = queryIPC(["get_property", "duration"])?["data"] as? Double, dur > 0 else { return }
        sendIPC(["set_property", "time-pos", dur * min(1, max(0, ratio))])
    }

    func skip(by seconds: Double) {
        guard let pos = queryIPC(["get_property", "time-pos"])?["data"] as? Double else { return }
        let dur = queryIPC(["get_property", "duration"])?["data"] as? Double ?? .infinity
        sendIPC(["set_property", "time-pos", min(dur - 0.5, max(0, pos + seconds))])
    }

    private func waitForPlayback(pid: Int32) async -> Bool {
        for _ in 0..<80 {
            if pid > 0, !isProcessAlive(pid) { return false }
            if FileManager.default.fileExists(atPath: PocketPaths.mpvSocket.path) {
                if let resp = queryIPC(["get_property", "playback-state"]),
                   let s = resp["data"] as? String, s == "playing" || s == "paused" {
                    return true
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return pid > 0 && isProcessAlive(pid)
    }

    private func isProcessAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    private func sendIPC(_ command: [Any]) {
        guard FileManager.default.fileExists(atPath: PocketPaths.mpvSocket.path) else { return }
        let payload: [String: Any] = ["command": command]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              var str = String(data: data, encoding: .utf8) else { return }
        str += "\n"
        let socket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { return }
        defer { close(socket) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        PocketPaths.mpvSocket.path.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { dest in
                dest.withMemoryRebound(to: CChar.self, capacity: 104) { $0.assign(from: ptr, count: min(104, PocketPaths.mpvSocket.path.utf8.count + 1)) }
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(socket, $0, size) }
        }
        str.withCString { _ = write(socket, $0, strlen($0)) }
    }

    private func queryIPC(_ command: [Any]) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: PocketPaths.mpvSocket.path) else { return nil }
        let payload: [String: Any] = ["command": command]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              var str = String(data: data, encoding: .utf8) else { return nil }
        str += "\n"
        let socket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { return nil }
        defer { close(socket) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        PocketPaths.mpvSocket.path.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { dest in
                dest.withMemoryRebound(to: CChar.self, capacity: 104) { $0.assign(from: ptr, count: min(104, PocketPaths.mpvSocket.path.utf8.count + 1)) }
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(socket, $0, size) }
        }
        str.withCString { _ = write(socket, $0, strlen($0)) }
        var buf = [UInt8](repeating: 0, count: 8192)
        let n = read(socket, &buf, buf.count)
        guard n > 0, let json = String(bytes: buf.prefix(n), encoding: .utf8)?.split(separator: "\n").first,
              let jd = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jd) as? [String: Any]
        else { return nil }
        return obj
    }

    private func saveState(_ s: PlaybackState) {
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: PocketPaths.stateFile)
        }
    }
}
