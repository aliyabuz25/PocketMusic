import Foundation

struct PlaylistEntry: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let title: String
    let artist: String

    var searchQuery: String { "\(artist) \(title)" }
}

struct Playlist: Identifiable, Codable, Sendable {
    let id: String
    var name: String
    var icon: String
    var entries: [PlaylistEntry]
}

struct BrowseItem: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL
    let genre: String
    let appleMusicURL: URL?

    var searchQuery: String { "\(artist) \(title)" }
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case search = "Ara"
    case playlist = "Playlistimiz"
    case discover = "Keşfet"
    case popular = "Popüler"
    case favorites = "Favoriler"
    case local = "Yerel"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .playlist: return "music.note.list"
        case .discover: return "sparkles"
        case .popular: return "chart.line.uptrend.xyaxis"
        case .favorites: return "heart.fill"
        case .local: return "arrow.down.circle.fill"
        }
    }
}

enum PMTheme {
    static let bg = ColorTuple(0.04, 0.04, 0.055)
    static let bgElevated = ColorTuple(0.07, 0.07, 0.085)
    static let sidebar = ColorTuple(0.055, 0.055, 0.07)
    static let card = ColorTuple(0.10, 0.10, 0.12)
    static let surface = ColorTuple(0.12, 0.12, 0.14)
    static let playerBar = ColorTuple(0.07, 0.07, 0.085)
    static let ghost = ColorTuple(0.14, 0.14, 0.16)
    static let accent = ColorTuple(0.58, 0.45, 1.0)
    static let accentAlt = ColorTuple(1.0, 0.38, 0.62)
    static let secondary = ColorTuple(0.58, 0.58, 0.62)
    static let textSecondary = ColorTuple(0.62, 0.62, 0.66)
    static let textTertiary = ColorTuple(0.42, 0.42, 0.46)
    static let pink = accent
}

struct ColorTuple {
    let r, g, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
}

struct GenreTile: Identifiable {
    let id: String
    let name: String
    let icon: String
    let colors: (Double, Double, Double)
}

enum PocketGenres {
    static let all: [GenreTile] = [
        .init(id: "pop", name: "Pop", icon: "waveform", colors: (0.58, 0.45, 1.0)),
        .init(id: "rock", name: "Rock", icon: "guitars.fill", colors: (0.88, 0.36, 0.38)),
        .init(id: "hiphop", name: "Hip-Hop", icon: "mic.fill", colors: (0.42, 0.52, 0.95)),
        .init(id: "dance", name: "Dance", icon: "bolt.fill", colors: (0.30, 0.72, 0.88)),
        .init(id: "rnb", name: "R&B", icon: "heart.fill", colors: (0.92, 0.34, 0.58)),
        .init(id: "turkce", name: "Türkçe", icon: "star.fill", colors: (0.92, 0.68, 0.28)),
    ]
}
