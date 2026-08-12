import SwiftUI

// MARK: - Color

func pmColor(_ c: ColorTuple) -> Color {
    Color(red: c.r, green: c.g, blue: c.b)
}

extension Color {
    static func pm(_ t: ColorTuple, opacity: Double = 1) -> Color {
        Color(red: t.r, green: t.g, blue: t.b, opacity: opacity)
    }
}

// MARK: - Shimmer / Ghost

struct PMShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.10),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.55)
                    .offset(x: geo.size.width * phase)
                }
                .clipped()
            }
            .onAppear {
                withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
    }
}

extension View {
    func pmShimmer() -> some View {
        modifier(PMShimmerModifier())
    }
}

struct PMGhostBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var radius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.pm(PMTheme.ghost))
            .frame(width: width, height: height)
            .pmShimmer()
    }
}

struct PMGhostLine: View {
    var width: CGFloat
    var height: CGFloat = 12
    var radius: CGFloat = 6

    var body: some View {
        PMGhostBlock(width: width, height: height, radius: radius)
    }
}

struct PMGhostTrackRow: View {
    var body: some View {
        HStack(spacing: 14) {
            PMGhostLine(width: 20, height: 14, radius: 4)
            PMGhostBlock(width: 48, height: 48, radius: 8)
            VStack(alignment: .leading, spacing: 8) {
                PMGhostLine(width: 180, height: 13)
                PMGhostLine(width: 120, height: 11)
            }
            Spacer()
            PMGhostBlock(width: 24, height: 24, radius: 12)
        }
        .padding(.vertical, 8)
    }
}

struct PMGhostHero: View {
    var body: some View {
        PMGhostBlock(height: 280, radius: 14)
    }
}

struct PMGhostAlbumCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PMGhostBlock(width: 150, height: 150, radius: 8)
            PMGhostLine(width: 120, height: 12)
            PMGhostLine(width: 90, height: 10)
        }
    }
}

struct PMBrowseSongRow: View {
    let rank: Int
    let item: BrowseItem
    var showGenre = false

    var body: some View {
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(rank <= 3 ? Color.pm(PMTheme.accent) : Color.pm(PMTheme.textSecondary))
                .frame(width: 28, alignment: .trailing)

            PMArtworkImage(url: item.artworkURL, size: 52, radius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.pm(PMTheme.textSecondary))
                        .lineLimit(1)
                    if showGenre {
                        Text("·")
                            .foregroundStyle(Color.pm(PMTheme.textTertiary))
                        Text(item.genre)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.pm(PMTheme.textTertiary))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "play.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct PMGhostPlaylistHeader: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            PMGhostBlock(width: 120, height: 120, radius: 16)
            VStack(alignment: .leading, spacing: 10) {
                PMGhostLine(width: 80, height: 10)
                PMGhostLine(width: 200, height: 28, radius: 8)
                PMGhostLine(width: 60, height: 12)
            }
            Spacer()
        }
    }
}

// MARK: - Async image with ghost

struct PMArtworkImage: View {
    let url: URL?
    var size: CGFloat = 48
    var radius: CGFloat = 8

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        artworkFallback
                    default:
                        PMGhostBlock(width: size, height: size, radius: radius)
                    }
                }
            } else {
                artworkFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private var artworkFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.pm(PMTheme.surface))
            Image(systemName: "music.note")
                .font(.system(size: size * 0.38))
                .foregroundStyle(Color.pm(PMTheme.accent, opacity: 0.7))
        }
    }
}

// MARK: - Player bar

struct PMPlayerBar: View {
    @ObservedObject private var player = MenuBarModel.shared
    @ObservedObject private var offline = OfflineStore.shared
    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    private var displayProgress: Double {
        isDragging ? dragProgress : player.progress
    }

    var body: some View {
        VStack(spacing: 0) {
            progressScrubber
                .padding(.horizontal, 16)
                .padding(.top, 10)

            HStack(spacing: 14) {
                artwork
                trackInfo
                Spacer(minLength: 8)
                controls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background {
            ZStack {
                Color.pm(PMTheme.playerBar)
                LinearGradient(
                    colors: [
                        Color.pm(PMTheme.accent, opacity: 0.08),
                        .clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var progressScrubber: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 4)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.pm(PMTheme.accent), Color.pm(PMTheme.accentAlt)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * displayProgress), height: 4)

                Circle()
                    .fill(Color.white)
                    .frame(width: isDragging ? 12 : 0, height: isDragging ? 12 : 0)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: max(0, geo.size.width * displayProgress - 6))
                    .animation(.easeOut(duration: 0.12), value: isDragging)
            }
            .frame(height: 14)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        dragProgress = min(1, max(0, value.location.x / geo.size.width))
                    }
                    .onEnded { value in
                        let ratio = min(1, max(0, value.location.x / geo.size.width))
                        player.seek(to: ratio)
                        isDragging = false
                    }
            )
        }
        .frame(height: 14)
    }

    @ViewBuilder
    private var artwork: some View {
        if let art = player.menuBarImage {
            Image(nsImage: art)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            PMGhostBlock(width: 52, height: 52, radius: 8)
        }
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(player.trackTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(player.artistTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.pm(PMTheme.textSecondary))
                    .lineLimit(1)
                Text("·")
                    .foregroundStyle(Color.pm(PMTheme.textTertiary))
                Text("\(player.elapsedText) / \(player.durationText)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.pm(PMTheme.textTertiary))
            }
        }
        .frame(maxWidth: 280, alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button { player.toggleFavorite() } label: {
                Image(systemName: player.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(player.isFavorite ? Color.pm(PMTheme.accentAlt) : .white.opacity(0.85))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Button {
                Task { await player.downloadCurrentTrack() }
            } label: {
                let key = player.catalogTrack?.stableKey ?? ""
                Image(systemName: offline.hasOffline(stableKey: key) ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(offline.hasOffline(stableKey: key) ? Color.pm(PMTheme.accent) : .white.opacity(0.85))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(player.catalogTrack == nil || offline.hasOffline(stableKey: player.catalogTrack?.stableKey ?? ""))

            controlButton("backward.fill", size: 15) { player.skipBack() }

            Button { player.togglePlay() } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.pm(PMTheme.accent), Color.pm(PMTheme.accentAlt)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Image(systemName: player.playIcon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            controlButton("forward.fill", size: 15) { player.skipForward() }

            controlButton("forward.end.fill", size: 15) {
                Task { await player.playNext() }
            }
        }
    }

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}
