import Foundation

/// Display settings live in ~/.config/NowPlayingChip/settings.json (re-read on every use, no rebuild needed):
/// {"backgroundOpacity": 0.5}
/// `backgroundOpacity` is 0 (fully see-through) to 1 (solid); text and buttons stay fully opaque.
enum Settings {
    static let path = NSHomeDirectory() + "/.config/NowPlayingChip/settings.json"
    static let defaultBackgroundOpacity = 0.5

    private struct File: Codable {
        let backgroundOpacity: Double?
    }

    static var backgroundOpacity: Double {
        guard let data = FileManager.default.contents(atPath: path) else { return defaultBackgroundOpacity }
        do {
            let value = try JSONDecoder().decode(File.self, from: data).backgroundOpacity
            return min(max(value ?? defaultBackgroundOpacity, 0), 1)
        } catch {
            NSLog("Could not read \(path): \(error)")
            return defaultBackgroundOpacity
        }
    }
}
