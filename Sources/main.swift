import AppKit
import SwiftUI
import Combine
import ServiceManagement

final class ChipPanel: NSPanel {
    static let size = NSSize(width: 420, height: 42)

    init(watcher: SpotifyWatcher) {
        super.init(contentRect: NSRect(origin: .zero, size: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true   // drag anywhere on the chip
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        contentView = NSHostingView(rootView: ChipView(watcher: watcher))
        alphaValue = 0
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) { [weak self] _ in
            guard let self, !self.repositioning else { return }
            UserDefaults.standard.set(NSStringFromPoint(self.frame.origin), forKey: "chipOrigin")
        }
    }

    private var repositioning = false

    /// Centered just above the Dock (visibleFrame's bottom edge is the Dock's top).
    func reposition() {
        repositioning = true
        defer { repositioning = false }
        // Use the dragged position if it's still on a connected screen.
        if let saved = UserDefaults.standard.string(forKey: "chipOrigin") {
            let origin = NSPointFromString(saved)
            if NSScreen.screens.contains(where: { $0.frame.contains(origin) }) {
                return setFrameOrigin(origin)
            }
        }
        guard let screen = NSScreen.main else { return }
        let v = screen.visibleFrame
        setFrameOrigin(NSPoint(x: v.midX - Self.size.width / 2, y: v.minY + 8))
    }

    private var wantsVisible = false

    func setVisible(_ show: Bool) {
        wantsVisible = show
        if show {
            reposition()
            orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; animator().alphaValue = show ? 1 : 0 },
                                             completionHandler: { if !self.wantsVisible { self.orderOut(nil) } })
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let watcher = SpotifyWatcher()
    var panel: ChipPanel!
    var statusItem: NSStatusItem!
    var loginItem: NSMenuItem!
    var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { await SpotifyAPI.shared.warmUp() }
        panel = ChipPanel(watcher: watcher)

        cancellable = watcher.$track.receive(on: DispatchQueue.main).sink { [weak self] track in
            self?.panel.setVisible(track != nil)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.panel.reposition() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Now Playing")
        let menu = NSMenu()
        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        let reset = NSMenuItem(title: "Reset Position", action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    /// nowplayingchip://add | next | previous | playlists | select?name=...|description=...
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "nowplayingchip" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func param(_ n: String) -> String? { query.first { $0.name == n }?.value }
            switch url.host {
            case "playlists": showPlaylists()
            case "select":
                if let error = watcher.selectPlaylist(name: param("name"), description: param("description")) {
                    NSLog("Select playlist failed: \(error)")
                    NSSound.beep()
                }
            case "add": watcher.addToPlaylist()
            case "next": watcher.nextTrack()
            case "previous": watcher.previousTrack()
            default: NSLog("Unknown command URL: \(url)")
            }
        }
    }

    func showPlaylists() {
        let current = Playlists.selected?.name
        let list = Playlists.all()
        let alert = NSAlert()
        alert.messageText = "Playlists"
        alert.informativeText = list.isEmpty ? "None. Add them to \(Playlists.path)" : list.map {
            let mark = $0.name == current ? "▶ " : "    "
            return mark + $0.name + ($0.description.map { " — " + $0 } ?? "")
        }.joined(separator: "\n")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc func resetPosition() {
        UserDefaults.standard.removeObject(forKey: "chipOrigin")
        panel.reposition()
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSLog("Login item error: \(error)") }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
