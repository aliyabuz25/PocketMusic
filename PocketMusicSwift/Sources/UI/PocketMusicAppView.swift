import SwiftUI

struct PocketMusicAppView: View {
    @ObservedObject private var ui = PocketMusicUIState.shared
    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var playlist = PlaylistStore.shared
    @ObservedObject private var playHistory = PlayHistoryStore.shared
    @ObservedObject private var offline = OfflineStore.shared
    @ObservedObject private var menu = MenuBarModel.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                sidebar
                mainContent
            }
            playerBar
        }
        .background(pmColor(PMTheme.bg))
        .preferredColorScheme(.dark)
        .task { await ui.loadIfNeeded() }
        .onAppear { ui.refreshNowPlaying() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [pmColor(PMTheme.accent), pmColor(PMTheme.accentAlt)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pocket Music")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Dinle. Keşfet. Sakla.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(pmColor(PMTheme.secondary))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 28)
            .padding(.bottom, 22)

            ForEach(SidebarTab.allCases) { tab in
                sidebarRow(tab)
            }

            Spacer()

            Button {
                MainWindowController.shared.collapseToMiniPlayer()
            } label: {
                Label("Mini Player", systemImage: "rectangle.compress.vertical")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(pmColor(PMTheme.secondary))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .padding(.bottom, menu.hasTrack ? 100 : 20)
        }
        .frame(width: 228)
        .background(pmColor(PMTheme.sidebar))
    }

    private func sidebarRow(_ tab: SidebarTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                ui.tab = tab
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
                Text(tab.rawValue)
                    .font(.system(size: 14, weight: ui.tab == tab ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(ui.tab == tab ? pmColor(PMTheme.accent) : .white.opacity(0.85))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        ui.tab == tab
                            ? LinearGradient(
                                colors: [
                                    Color.pm(PMTheme.accent, opacity: 0.18),
                                    Color.pm(PMTheme.accentAlt, opacity: 0.08),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            : LinearGradient(colors: [.clear], startPoint: .leading, endPoint: .trailing)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }

    // MARK: - Main

    @ViewBuilder
    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                switch ui.tab {
                case .search: searchView
                case .playlist: playlistView
                case .discover: discoverView
                case .popular: popularList
                case .favorites: favoritesView
                case .local: localView
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
            .padding(.bottom, menu.hasTrack ? 110 : 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pmColor(PMTheme.bg))
    }

    // MARK: - Search

    private var searchView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Ara")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(pmColor(PMTheme.secondary))
                TextField("Apple Music'te ara", text: $ui.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .onChange(of: ui.searchText) { _ in ui.scheduleSearch() }
                if ui.isSearching {
                    ProgressView().controlSize(.small).tint(pmColor(PMTheme.accent))
                } else if !ui.searchText.isEmpty {
                    Button {
                        ui.searchText = ""
                        ui.searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(pmColor(PMTheme.secondary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.pm(PMTheme.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                    )
            )

            if ui.searchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                searchHints
            } else if ui.isSearching {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { _ in PMGhostTrackRow() }
                }
            } else if ui.searchResults.isEmpty {
                emptyState(icon: "magnifyingglass", title: "Sonuç bulunamadı", subtitle: "Farklı bir arama dene")
            } else {
                trackResultsList(ui.searchResults)
            }
        }
    }

    private var searchHints: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hızlı başlangıç")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(pmColor(PMTheme.secondary))
                .textCase(.uppercase)
                .tracking(0.6)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(PocketGenres.all) { genre in
                    Button {
                        ui.searchText = genre.name
                        ui.scheduleSearch()
                    } label: {
                        genreChip(genre)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }

    private func genreChip(_ genre: GenreTile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: genre.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(genre.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: genre.colors.0, green: genre.colors.1, blue: genre.colors.2).opacity(0.55))
        )
    }

    // MARK: - Playlist

    private var playlistView: some View {
        VStack(alignment: .leading, spacing: 20) {
            if playlist.isLoadingArtwork && playlist.artworkByEntryID.isEmpty {
                PMGhostPlaylistHeader()
            } else {
                HStack(alignment: .bottom, spacing: 20) {
                    playlistCoverArt.frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Çalma listesi")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(pmColor(PMTheme.accent))
                            .textCase(.uppercase)
                            .tracking(0.8)
                        Text(playlist.pocketMix.name)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white)
                        Text("\(playlist.pocketMix.entries.count) parça")
                            .font(.system(size: 14))
                            .foregroundStyle(pmColor(PMTheme.secondary))
                        if let cover = activeCoverEntry, playHistory.count(for: cover) > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(pmColor(PMTheme.accentAlt))
                                Text("En çok dinlenen: \(cover.title)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer()
                }
            }

            Button {
                Task {
                    if let top = activeCoverEntry {
                        await playlist.play(top, queue: playlist.pocketMix.entries)
                    }
                }
            } label: {
                Label("Tümünü Çal", systemImage: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Capsule(style: .continuous).fill(pmColor(PMTheme.accent)))
            }
            .buttonStyle(.plain)

            playlistEntriesList
        }
        .task { playlist.prefetchArtwork() }
    }

    private var activeCoverEntry: PlaylistEntry? {
        if let top = playHistory.topEntry(in: playlist.pocketMix.entries), playHistory.count(for: top) > 0 {
            return top
        }
        return playlist.pocketMix.entries.first
    }

    @ViewBuilder
    private var playlistCoverArt: some View {
        if let entry = activeCoverEntry, let url = playlist.artwork(for: entry) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure: playlistCoverPlaceholder
                default: PMGhostBlock(width: 120, height: 120, radius: 16)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.pm(PMTheme.accent, opacity: 0.2), radius: 20, y: 8)
        } else if playlist.isLoadingArtwork {
            PMGhostBlock(width: 120, height: 120, radius: 16)
        } else {
            playlistCoverPlaceholder
        }
    }

    private var playlistCoverPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(
                    colors: [pmColor(PMTheme.accent), pmColor(PMTheme.accentAlt)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: playlist.pocketMix.icon)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
        }
    }

    private var playlistEntriesList: some View {
        VStack(spacing: 0) {
            ForEach(Array(playlist.pocketMix.entries.enumerated()), id: \.element.id) { idx, entry in
                Button {
                    Task { await playlist.play(entry) }
                } label: {
                    HStack(spacing: 14) {
                        Text("\(idx + 1)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(pmColor(PMTheme.secondary))
                            .frame(width: 24, alignment: .trailing)
                        playlistEntryArtwork(entry)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(entry.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                if activeCoverEntry?.id == entry.id, playHistory.count(for: entry) > 0 {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(pmColor(PMTheme.accentAlt))
                                }
                            }
                            HStack(spacing: 8) {
                                Text(entry.artist)
                                    .font(.system(size: 12))
                                    .foregroundStyle(pmColor(PMTheme.secondary))
                                if playHistory.count(for: entry) > 0 {
                                    Text("\(playHistory.count(for: entry)) dinleme")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(pmColor(PMTheme.accent).opacity(0.85))
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func playlistEntryArtwork(_ entry: PlaylistEntry) -> some View {
        if let url = playlist.artwork(for: entry) {
            PMArtworkImage(url: url, size: 48, radius: 8)
        } else if playlist.isLoadingArtwork {
            PMGhostBlock(width: 48, height: 48, radius: 8)
        } else {
            PMArtworkImage(url: nil, size: 48, radius: 8)
        }
    }

    // MARK: - Discover

    private var discoverView: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Keşfet")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            if ui.isLoadingCharts && ui.topSongs.isEmpty {
                PMGhostHero()
                sectionHeader("Türler")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(PocketGenres.all) { genre in genreTile(genre) }
                }
                sectionHeader("Popüler")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) { ForEach(0..<6, id: \.self) { _ in PMGhostAlbumCard() } }
                }
                VStack(spacing: 0) { ForEach(0..<8, id: \.self) { _ in PMGhostTrackRow() } }
            } else {
                if let hero = ui.topSongs.first { heroCard(hero, queue: ui.topSongs) }
                sectionHeader("Türler")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(PocketGenres.all) { genreTile($0) }
                }
                sectionHeader("Popüler")
                horizontalRow(Array(ui.topSongs.prefix(12)))
                sectionHeader("Top 50 — Türkiye")
                browseSongList(Array(ui.topSongs.prefix(50)))
            }
        }
        .task(id: ui.tab) {
            if ui.tab == .discover && ui.topSongs.isEmpty && !ui.isLoadingCharts {
                await ui.reloadCharts()
            }
        }
    }

    private func genreTile(_ genre: GenreTile) -> some View {
        Button {
            ui.tab = .search
            ui.searchText = genre.name
            ui.scheduleSearch()
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: genre.colors.0, green: genre.colors.1, blue: genre.colors.2),
                            Color(red: genre.colors.0 * 0.6, green: genre.colors.1 * 0.6, blue: genre.colors.2 * 0.6),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 110)
                HStack {
                    Spacer()
                    Image(systemName: genre.icon)
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.white.opacity(0.25))
                        .padding(16)
                }
                Text(genre.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(16)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Popular

    private var popularList: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Popüler")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Türkiye · En çok dinlenen 50")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.pm(PMTheme.textSecondary))
                }
                Spacer()
                if !ui.topSongs.isEmpty {
                    Button {
                        Task {
                            if let first = ui.topSongs.first {
                                await BrowseService.play(first, queue: ui.topSongs)
                            }
                        }
                    } label: {
                        Label("Tümünü Çal", systemImage: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule(style: .continuous).fill(Color.pm(PMTheme.accent)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if ui.isLoadingCharts && ui.topSongs.isEmpty {
                VStack(spacing: 0) { ForEach(0..<12, id: \.self) { _ in PMGhostTrackRow() } }
            } else if ui.topSongs.isEmpty {
                emptyState(icon: "chart.line.uptrend.xyaxis", title: "Liste yüklenemedi", subtitle: "Bağlantını kontrol et")
                Button { Task { await ui.reloadCharts() } } label: {
                    Label("Yeniden Yükle", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule(style: .continuous).fill(Color.pm(PMTheme.accent)))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            } else {
                browseSongList(ui.topSongs)
            }
        }
        .task(id: ui.tab) {
            if ui.tab == .popular && ui.topSongs.isEmpty && !ui.isLoadingCharts {
                await ui.reloadCharts()
            }
        }
    }

    // MARK: - Local

    private var localView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Yerel")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            Text("İndirilen parçalar AES ile şifreli — sadece Pocket Music çalabilir.")
                .font(.system(size: 13))
                .foregroundStyle(Color.pm(PMTheme.textSecondary))

            if offline.items.isEmpty {
                emptyState(icon: "arrow.down.circle", title: "Henüz indirme yok", subtitle: "Parça satırından veya oynatıcıdan indir")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(offline.items) { item in
                        HStack(spacing: 14) {
                            PMArtworkImage(url: item.thumbnailURL.flatMap(URL.init(string:)), size: 52, radius: 8)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(item.artist)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.pm(PMTheme.textSecondary))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button { Task { await offline.play(item) } } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            Button { offline.remove(item) } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.pm(PMTheme.textTertiary))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    // MARK: - Favorites

    private var favoritesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Favoriler")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            if favorites.items.isEmpty {
                emptyState(icon: "heart", title: "Henüz favori yok", subtitle: "Kalp ikonuyla ekle")
            } else {
                trackResultsList(favorites.items)
            }
        }
    }

    // MARK: - Components

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(pmColor(PMTheme.secondary))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(pmColor(PMTheme.secondary))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white)
    }

    private func heroCard(_ item: BrowseItem, queue: [BrowseItem]) -> some View {
        Button {
            Task { await BrowseService.play(item, queue: queue) }
        } label: {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: item.artworkURL) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: PMGhostBlock(height: 280, radius: 14)
                    }
                }
                .frame(height: 280)
                .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 280)
                VStack(alignment: .leading, spacing: 6) {
                    Text("ÖNE ÇIKAN")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(pmColor(PMTheme.accent))
                    Text(item.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(item.artist)
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(24)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func horizontalRow(_ items: [BrowseItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(items) { item in
                    Button { Task { await BrowseService.play(item, queue: items) } } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            PMArtworkImage(url: item.artworkURL, size: 150, radius: 8)
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .frame(width: 150, alignment: .leading)
                            Text(item.artist)
                                .font(.system(size: 12))
                                .foregroundStyle(pmColor(PMTheme.secondary))
                                .lineLimit(1)
                                .frame(width: 150, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func browseSongList(_ items: [BrowseItem]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                Button {
                    Task { await BrowseService.play(item, queue: items) }
                } label: {
                    PMBrowseSongRow(rank: idx + 1, item: item)
                }
                .buttonStyle(.plain)
                if idx < items.count - 1 {
                    Divider().background(Color.white.opacity(0.05)).padding(.leading, 94)
                }
            }
        }
    }

    private func trackResultsList(_ tracks: [Track]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                HStack(spacing: 0) {
                    Button { Task { await ui.playSearch(track) } } label: {
                        HStack(spacing: 14) {
                            Text("\(idx + 1)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(pmColor(PMTheme.secondary))
                                .frame(width: 24, alignment: .trailing)
                            PMArtworkImage(url: URL(string: track.bestThumbnailURL), size: 48, radius: 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(track.artist)
                                        .font(.system(size: 12))
                                        .foregroundStyle(pmColor(PMTheme.secondary))
                                        .lineLimit(1)
                                    if track.duration != nil {
                                        Text("·").foregroundStyle(Color.pm(PMTheme.textTertiary))
                                        Text(track.durationText)
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(Color.pm(PMTheme.textTertiary))
                                    }
                                }
                            }
                            Spacer(minLength: 8)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    trackActionButtons(track)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func trackActionButtons(_ track: Track) -> some View {
        HStack(spacing: 10) {
            Button { favorites.toggle(track) } label: {
                Image(systemName: favorites.isFavorite(track) ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(favorites.isFavorite(track) ? Color.pm(PMTheme.accentAlt) : .white.opacity(0.55))
            }
            .buttonStyle(.plain)

            Button { Task { _ = await offline.download(track) } } label: {
                Group {
                    if offline.isDownloading(stableKey: track.stableKey) {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: offline.hasOffline(stableKey: track.stableKey) ? "checkmark.circle.fill" : "arrow.down.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(offline.hasOffline(stableKey: track.stableKey) ? Color.pm(PMTheme.accent) : .white.opacity(0.55))
                    }
                }
                .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(offline.hasOffline(stableKey: track.stableKey) || offline.isDownloading(stableKey: track.stableKey))
        }
        .padding(.trailing, 4)
    }

    private var playerBar: some View {
        Group {
            if menu.hasTrack { PMPlayerBar() }
        }
    }
}
