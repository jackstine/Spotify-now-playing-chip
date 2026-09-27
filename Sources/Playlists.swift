import Foundation

struct PlaylistEntry: Codable, Equatable {
    let name: String
    let description: String?
}

/// Playlist list lives in ~/.config/NowPlayingChip/playlists.json (re-read on every use, no rebuild needed):
/// {"default": "Workout", "playlists": [{"name": "Workout", "description": "high energy"}]}
/// The active one is chosen only through nowplayingchip://select and remembered across launches;
/// with nothing chosen (or a stale choice) `default` is used, and if that is unset or unknown, the first entry.
enum Playlists {
    static let path = NSHomeDirectory() + "/.config/NowPlayingChip/playlists.json"
    private static let selectedKey = "selectedPlaylist"

    enum Match { case found(PlaylistEntry), none, ambiguous([PlaylistEntry]) }

    private struct File: Codable {
        let `default`: String?
        let playlists: [PlaylistEntry]
    }

    private static func load() -> File? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        do { return try JSONDecoder().decode(File.self, from: data) }
        catch { NSLog("Could not read \(path): \(error)"); return nil }
    }

    static func all() -> [PlaylistEntry] { load()?.playlists ?? [] }

    static var selected: PlaylistEntry? {
        guard let file = load() else { return nil }
        func entry(_ name: String?) -> PlaylistEntry? {
            guard let name else { return nil }
            return file.playlists.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
        return entry(UserDefaults.standard.string(forKey: selectedKey)) ?? entry(file.default) ?? file.playlists.first
    }

    /// Exact name (case-insensitive) wins; otherwise the description must contain `description` for exactly one entry.
    static func find(name: String?, description: String?) -> Match {
        let list = all()
        if let name, let hit = list.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return .found(hit) }
        guard let needle = description ?? name, !needle.isEmpty else { return .none }
        let hits = list.filter { ($0.description ?? "").range(of: needle, options: .caseInsensitive) != nil }
        switch hits.count {
        case 0: return .none
        case 1: return .found(hits[0])
        default: return .ambiguous(hits)
        }
    }

    static func select(_ entry: PlaylistEntry) { UserDefaults.standard.set(entry.name, forKey: selectedKey) }
}
