import AppKit
import Combine

struct Track: Equatable {
    let name: String
    let artist: String
    let artworkURL: URL?
    let uri: String
}

/// Reads the current Spotify track via AppleScript, refreshing on Spotify's
/// distributed notification (no polling).
final class SpotifyWatcher: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?   // last loaded image, kept between tracks

    enum AddState { case idle, working, done, failed }
    @Published private(set) var addState = AddState.idle

    @Published private(set) var onPlaylist = false   // current track already on the selected playlist
    @Published private(set) var playlistName = SpotifyAPI.playlistName

    private let queue = DispatchQueue(label: "SpotifyWatcher")
    private var artworkTask: URLSessionDataTask?
    private var loadedArtworkURL: URL?
    private static let bundleID = "com.spotify.client"

    init() {
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(refresh),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"), object: nil)
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        ws.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        refresh()
    }

    private var spotifyRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    @objc func refresh() {
        // Never run the script if Spotify is closed — `tell application` would launch it.
        guard spotifyRunning else { return apply(nil) }
        queue.async { [weak self] in
            let track = Self.fetchTrack()
            DispatchQueue.main.async { self?.apply(track) }
        }
    }

    @MainActor func addToPlaylist() {
        guard let uri = track?.uri, addState != .working else { return }
        addState = .working
        Task { @MainActor in
            do {
                if try await !SpotifyAPI.shared.addToPlaylist(uri: uri) { NSLog("Already in playlist, skipped") }
                addState = .done
                if track?.uri == uri { onPlaylist = true }
            }
            catch { NSLog("Add to playlist failed: \(error.localizedDescription)"); addState = .failed }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            addState = .idle
        }
    }

    /// Switches the target playlist; returns an error message if the query doesn't pick exactly one.
    @MainActor @discardableResult
    func selectPlaylist(name: String?, description: String?) -> String? {
        switch Playlists.find(name: name, description: description) {
        case .found(let entry):
            Playlists.select(entry)
            playlistName = entry.name
            onPlaylist = false
            refreshOnPlaylist()
            Task { await SpotifyAPI.shared.warmUp() }
            return nil
        case .none: return "No playlist matches"
        case .ambiguous(let hits): return "Ambiguous, matches: " + hits.map(\.name).joined(separator: ", ")
        }
    }

    /// Looks up whether the current track is on the selected playlist. Stale answers (track or playlist
    /// changed meanwhile) are dropped; unknown counts as "not on it" so "+" stays usable.
    func refreshOnPlaylist() {
        guard let uri = track?.uri else { return }
        let name = playlistName
        Task { @MainActor [weak self] in
            let result = await SpotifyAPI.shared.isOnPlaylist(uri: uri)
            guard let self, self.track?.uri == uri, self.playlistName == name else { return }
            self.onPlaylist = result ?? false
        }
    }

    func nextTrack() { send("next track") }
    func previousTrack() { send("previous track") }

    private func send(_ command: String) {
        // Same guard as refresh(): don't let `tell application` launch Spotify.
        guard spotifyRunning else { return }
        queue.async {
            var error: NSDictionary?
            NSAppleScript(source: "tell application \"Spotify\" to \(command)")?.executeAndReturnError(&error)
            if let error { NSLog("AppleScript error: \(error)") }
        }
    }

    private static func fetchTrack() -> Track? {
        let source = """
        tell application "Spotify"
            if player state is playing then
                set art to ""
                try
                    set art to artwork url of current track
                end try
                return (name of current track) & "||" & (artist of current track) & "||" & art & "||" & (id of current track)
            end if
            return ""
        end tell
        """
        var error: NSDictionary?
        guard let out = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue,
              !out.isEmpty else {
            if let error { NSLog("AppleScript error: \(error)") }
            return nil
        }
        let parts = out.components(separatedBy: "||")
        guard parts.count >= 4 else { return nil }
        return Track(name: parts[0], artist: parts[1], artworkURL: URL(string: parts[2]), uri: parts[3])
    }

    private func apply(_ new: Track?) {
        let trackChanged = new?.uri != track?.uri
        if new != track { track = new }
        if trackChanged { onPlaylist = false; refreshOnPlaylist() }
        guard let url = new?.artworkURL, url != loadedArtworkURL else { return }
        loadedArtworkURL = url
        artworkTask?.cancel()
        artworkTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async { self?.artwork = image }
        }
        artworkTask?.resume()
    }
}
