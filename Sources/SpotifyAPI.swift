import AppKit
import CryptoKit
import Network
import Security

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ m: String) { message = m }
}

/// Config lookup: process environment, then the .env copied into the app bundle by build.sh,
/// then ~/.config/NowPlayingChip/.env.
enum Env {
    static let paths = [(Bundle.main.resourcePath ?? "") + "/.env",
                        NSHomeDirectory() + "/.config/NowPlayingChip/.env"]
    static func value(_ key: String) -> String? {
        if let v = ProcessInfo.processInfo.environment[key], !v.isEmpty { return v }
        for path in paths {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, parts[0] == key {
                    return parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
            }
        }
        return nil
    }
}

enum Keychain {
    private static let service = "dev.nowplayingchip.app"
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ key: String, _ value: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        SecItemAdd(base.merging([kSecValueData as String: Data(value.utf8)]) { $1 } as CFDictionary, nil)
    }
}

/// One-shot HTTP listener on 127.0.0.1:8888 that captures the OAuth redirect.
private final class CallbackServer {
    private var listener: NWListener?
    private var done = false

    func waitForCode(expectedState: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            func finish(_ result: Result<String, Error>) {
                guard !done else { return }
                done = true
                listener?.cancel()
                cont.resume(with: result)
            }
            do {
                let params = NWParameters.tcp
                params.requiredInterfaceType = .loopback
                listener = try NWListener(using: params, on: 8888)
            } catch { return finish(.failure(error)) }
            listener?.newConnectionHandler = { conn in
                conn.start(queue: .global())
                conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
                    let line = request.components(separatedBy: "\r\n").first ?? ""
                    let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                    let items = URLComponents(string: "http://x" + path)?.queryItems ?? []
                    let code = items.first { $0.name == "code" }?.value
                    let state = items.first { $0.name == "state" }?.value
                    let ok = code != nil && state == expectedState
                    let body = ok ? "Connected to Spotify. You can close this tab." : "Spotify login failed."
                    let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n\(body)"
                    conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
                    if ok, let code { finish(.success(code)) } else if path.hasPrefix("/callback") { finish(.failure(APIError("Spotify login was denied"))) }
                }
            }
            listener?.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 120) { finish(.failure(APIError("Spotify login timed out"))) }
        }
    }
}

/// Spotify Web API (Authorization Code + PKCE) — only what "add to playlist" needs.
final class SpotifyAPI {
    static let shared = SpotifyAPI()
    /// Name of the playlist tracks are added to (SPOTIFY_PLAYLIST_NAME).
    static var playlistName: String { Env.value("SPOTIFY_PLAYLIST_NAME") ?? "" }
    private static var playlistCacheKey: String { "playlistID:\(playlistName)" }

    private let redirect = "http://127.0.0.1:8888/callback"
    private let scopes = "playlist-read-private playlist-modify-private playlist-modify-public"
    private var accessToken: String?
    private var expiry = Date.distantPast

    private var clientID: String {
        get throws {
            guard let id = Env.value("SPOTIFY_CLIENT_ID"), !id.isEmpty else {
                throw APIError("SPOTIFY_CLIENT_ID not set (see README: Configuration)")
            }
            return id
        }
    }

    /// Adds the track unless it's already on the playlist. Returns false if it was already there.
    @discardableResult
    func addToPlaylist(uri: String) async throws -> Bool {
        let id = try await playlistID()
        let token = try await validToken()
        if try await playlistContains(uri: uri, playlistID: id, token: token) { return false }
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/playlists/\(id)/tracks")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["uris": [uri]])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { UserDefaults.standard.removeObject(forKey: Self.playlistCacheKey) }
        guard (200..<300).contains(status) else {
            throw APIError("Add failed (\(status)): \(String(data: data, encoding: .utf8) ?? "")")
        }
        return true
    }

    private func playlistContains(uri: String, playlistID: String, token: String) async throws -> Bool {
        var next: String? = "https://api.spotify.com/v1/playlists/\(playlistID)/tracks?limit=100&fields=items(track(uri)),next"
        while let url = next {
            var req = URLRequest(url: URL(string: url)!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                throw APIError("Could not read playlist: \(String(data: data, encoding: .utf8) ?? "")")
            }
            if items.contains(where: { ($0["track"] as? [String: Any])?["uri"] as? String == uri }) { return true }
            next = json["next"] as? String
        }
        return false
    }

    private func playlistID() async throws -> String {
        guard !Self.playlistName.isEmpty else { throw APIError("SPOTIFY_PLAYLIST_NAME not set (see README: Configuration)") }
        if let cached = UserDefaults.standard.string(forKey: Self.playlistCacheKey) { return cached }
        let token = try await validToken()
        var next: String? = "https://api.spotify.com/v1/me/playlists?limit=50"
        while let url = next {
            var req = URLRequest(url: URL(string: url)!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                throw APIError("Could not list playlists: \(String(data: data, encoding: .utf8) ?? "")")
            }
            if let hit = items.first(where: { ($0["name"] as? String)?.caseInsensitiveCompare(Self.playlistName) == .orderedSame }),
               let id = hit["id"] as? String {
                UserDefaults.standard.set(id, forKey: Self.playlistCacheKey)
                return id
            }
            next = json["next"] as? String
        }
        throw APIError("No playlist named \"\(Self.playlistName)\" found")
    }

    // MARK: Auth

    private func validToken() async throws -> String {
        if let t = accessToken, expiry > Date().addingTimeInterval(30) { return t }
        if let refresh = Keychain.get("refreshToken") {
            if let t = try? await tokenRequest(["grant_type": "refresh_token", "refresh_token": refresh]) { return t }
        }
        return try await authorize()
    }

    /// Signs in (silently if a refresh token exists) and resolves the playlist, so the first click is instant.
    func warmUp() async {
        do { _ = try await playlistID() } catch { NSLog("Spotify warm-up failed: \(error.localizedDescription)") }
    }

    private var authTask: Task<String, Error>?

    private func authorize() async throws -> String {
        if let t = authTask { return try await t.value }   // a login is already in flight
        let t = Task { try await runAuthorization() }
        authTask = t
        defer { authTask = nil }
        return try await t.value
    }

    /// Opens the URL in the Chrome profile named by CHROME_PROFILE_NAME (if set and found), otherwise
    /// in the default browser.
    private func openInChrome(_ url: URL) {
        guard let profileName = Env.value("CHROME_PROFILE_NAME") else { NSWorkspace.shared.open(url); return }
        let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        let statePath = NSHomeDirectory() + "/Library/Application Support/Google/Chrome/Local State"
        guard FileManager.default.isExecutableFile(atPath: chrome),
              let data = FileManager.default.contents(atPath: statePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (json["profile"] as? [String: Any])?["info_cache"] as? [String: [String: Any]],
              let dir = cache.first(where: { $0.value["name"] as? String == profileName })?.key else {
            NSWorkspace.shared.open(url); return
        }
        // Chrome hands this off to the running instance (or starts one) and opens a tab in that profile.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: chrome)
        p.arguments = ["--profile-directory=\(dir)", url.absoluteString]
        do { try p.run() } catch { NSWorkspace.shared.open(url) }
    }

    /// Clicks Spotify's "Agree" button in the Chrome tab. Needs Chrome > View > Developer >
    /// "Allow JavaScript from Apple Events" (one-time) plus the Automation prompt for Chrome.
    private static func autoAccept() async {
        let js = "var b=document.querySelector(\"[data-testid='auth-accept']\"); if(b){b.click(); 'clicked'} else {'none'}"
        let source = """
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t contains "accounts.spotify.com" then
                        return execute t javascript "\(js.replacingOccurrences(of: "\"", with: "\\\""))"
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
        var warned = false
        for _ in 0..<40 {
            if Task.isCancelled { return }
            var error: NSDictionary?
            let out = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
            if let error, !warned { warned = true; NSLog("Auto-accept unavailable: \(error)") }
            if out == "clicked" { return }
            try? await Task.sleep(nanoseconds: 750_000_000)
        }
    }

    private func runAuthorization() async throws -> String {
        let verifier = Self.randomString(64)
        let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomString(16)
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [.init(name: "client_id", value: try clientID), .init(name: "response_type", value: "code"),
                        .init(name: "redirect_uri", value: redirect), .init(name: "scope", value: scopes),
                        .init(name: "state", value: state), .init(name: "code_challenge_method", value: "S256"),
                        .init(name: "code_challenge", value: challenge)]
        let server = CallbackServer()
        async let code = server.waitForCode(expectedState: state)
        try await Task.sleep(nanoseconds: 200_000_000)   // let the listener bind before the browser redirects
        openInChrome(c.url!)
        // Auto-click "Agree" only when a Chrome profile is configured.
        let clicker = Env.value("CHROME_PROFILE_NAME") == nil ? nil : Task.detached { await Self.autoAccept() }
        defer { clicker?.cancel() }
        return try await tokenRequest(["grant_type": "authorization_code", "code": try await code,
                                       "redirect_uri": redirect, "code_verifier": verifier])
    }

    private func tokenRequest(_ params: [String: String]) async throws -> String {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = (params.merging(["client_id": try clientID]) { $1 }).map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw APIError("Token request failed: \(String(data: data, encoding: .utf8) ?? "")")
        }
        accessToken = token
        expiry = Date().addingTimeInterval((json["expires_in"] as? Double) ?? 3600)
        if let refresh = json["refresh_token"] as? String { Keychain.set("refreshToken", refresh) }
        return token
    }

    private static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
    private static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
