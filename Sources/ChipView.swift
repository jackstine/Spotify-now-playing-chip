import SwiftUI
import AppKit

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.alphaValue = Settings.backgroundOpacity
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.alphaValue = Settings.backgroundOpacity   // picks up settings.json edits on the next track change
    }
}

struct ChipView: View {
    @ObservedObject var watcher: SpotifyWatcher
    private var buttonSymbol: String {
        switch watcher.addState {
        case .idle: return watcher.onPlaylist ? "checkmark" : "plus"
        case .working: return "ellipsis"
        case .done: return "checkmark"
        case .failed: return "exclamationmark"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let art = watcher.artwork {
                    Image(nsImage: art).resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.3)
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 0) {
                Text(watcher.track?.name ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(watcher.playlistName)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            Text(watcher.track?.artist ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 140, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)

            Button(action: watcher.addToPlaylist) {
                Image(systemName: buttonSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.black))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(watcher.onPlaylist)
            .opacity(watcher.onPlaylist ? 0.4 : 1)
            .help(watcher.onPlaylist ? "Already on \(watcher.playlistName)" : "Add to \(watcher.playlistName)")

            Button(action: watcher.previousTrack) {
                Image(systemName: "chevron.left.2")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.black))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Previous track")

            Button(action: watcher.nextTrack) {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.black))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Next track")
        }
        .padding(.horizontal, 10)
        .frame(width: ChipPanel.size.width, height: ChipPanel.size.height)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
