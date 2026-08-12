import Combine
import SwiftUI

@MainActor
final class PocketMusicUIState: ObservableObject {
    static let shared = PocketMusicUIState()

    @Published var tab: SidebarTab = .search
    @Published var topSongs: [BrowseItem] = []
    @Published var topAlbums: [BrowseItem] = []
    @Published var isLoading = true
    @Published var chartsLoadFailed = false
    @Published var isLoadingCharts = false
    @Published var searchText = ""
    @Published var searchResults: [Track] = []
    @Published var isSearching = false
    @Published var windowVisible = false

    private var searchTask: Task<Void, Never>?

    private init() {}

    func loadIfNeeded() async {
        guard topSongs.isEmpty else { return }
        await reloadCharts()
    }

    func reloadCharts() async {
        isLoadingCharts = true
        isLoading = true
        chartsLoadFailed = false

        async let songs = BrowseService.fetchTopSongs()
        async let albums = BrowseService.fetchTopAlbums()
        let fetchedSongs = await songs
        let fetchedAlbums = await albums

        topSongs = fetchedSongs
        topAlbums = fetchedAlbums
        isLoading = false
        isLoadingCharts = false
        chartsLoadFailed = fetchedSongs.isEmpty
    }

    func refreshNowPlaying() {
        MenuBarModel.shared.refresh()
    }

    func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let results = await MusicService.searchMultiple(query: query, limit: 12)
            guard !Task.isCancelled else { return }
            searchResults = results
            isSearching = false
        }
    }

    func playSearch(_ track: Track) async {
        await PlaylistStore.shared.playTrack(track, queue: searchResults)
    }
}
