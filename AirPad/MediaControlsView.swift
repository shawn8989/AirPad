import SwiftUI

/// Remote media and system controls for the connected Mac: volume, playback,
/// display brightness, presentation remote, clipboard sync, and screen lock.
/// Media keys map to NX_KEYTYPE_* system events injected by AirBridge.
struct MediaControlsView: View {
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @StateObject private var network = NetworkManager.shared
    @State private var confirmLock = false
    @State private var clipboardStatus: String?

    var body: some View {
        List {
            Section("Volume") {
                HStack(spacing: 12) {
                    mediaButton("speaker.slash.fill", "Mute", "mute")
                    mediaButton("speaker.wave.1.fill", "Down", "volume_down")
                    mediaButton("speaker.wave.3.fill", "Up", "volume_up")
                }
            }
            Section("Playback") {
                HStack(spacing: 12) {
                    mediaButton("backward.fill", "Previous", "previous")
                    mediaButton("playpause.fill", "Play/Pause", "play_pause")
                    mediaButton("forward.fill", "Next", "next")
                }
            }
            Section("Display") {
                HStack(spacing: 12) {
                    mediaButton("sun.min.fill", "Dimmer", "brightness_down")
                    mediaButton("sun.max.fill", "Brighter", "brightness_up")
                }
            }
            Section("Presentation") {
                HStack(spacing: 12) {
                    keyButton("chevron.left.circle.fill", "Previous", keyCode: 123)
                    keyButton("chevron.right.circle.fill", "Next", keyCode: 124)
                    keyButton("b.circle", "Blank", keyCode: 11) // "B" blanks most slide apps
                }
                Text("Works in Keynote, PowerPoint, and Google Slides once the presentation is running. Pair with Air Mouse for a laser-style pointer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Clipboard") {
                Button {
                    if let text = UIPasteboard.general.string, !text.isEmpty {
                        NetworkManager.shared.sendClipboardSet(text)
                        clipboardStatus = "Sent to Mac clipboard — press ⌘V there to paste."
                    } else {
                        clipboardStatus = "iPhone clipboard has no text."
                    }
                    if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                } label: {
                    Label("Send iPhone Clipboard to Mac", systemImage: "arrow.up.doc.on.clipboard")
                }
                Button {
                    if let text = UIPasteboard.general.string, !text.isEmpty {
                        NetworkManager.shared.sendTypeText(text)
                        clipboardStatus = "Typing clipboard text on the Mac…"
                    } else {
                        clipboardStatus = "iPhone clipboard has no text."
                    }
                    if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                } label: {
                    Label("Type iPhone Clipboard on Mac", systemImage: "keyboard.badge.ellipsis")
                }
                Button {
                    NetworkManager.shared.requestMacClipboard()
                    clipboardStatus = "Fetching Mac clipboard…"
                    if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                } label: {
                    Label("Copy Mac Clipboard to iPhone", systemImage: "arrow.down.doc.on.clipboard")
                }
                if let status = clipboardStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let fetched = network.lastFetchedClipboard, !fetched.isEmpty {
                    Text("From Mac: \(fetched.prefix(120))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Section("System") {
                Button(role: .destructive) {
                    confirmLock = true
                } label: {
                    Label("Lock Mac Screen", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                }
                .confirmationDialog("Lock the Mac's screen?", isPresented: $confirmLock, titleVisibility: .visible) {
                    Button("Lock Screen", role: .destructive) {
                        NetworkManager.shared.sendMedia(action: "lock_screen")
                        if hapticsEnabled { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
                    }
                }
            }
        }
        .navigationTitle("Media & System")
    }

    private func keyButton(_ icon: String, _ title: String, keyCode: UInt16) -> some View {
        Button {
            NetworkManager.shared.sendKeyDown(keyCode: keyCode)
            NetworkManager.shared.sendKeyUp(keyCode: keyCode)
            if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
    }

    private func mediaButton(_ icon: String, _ title: String, _ action: String) -> some View {
        Button {
            NetworkManager.shared.sendMedia(action: action)
            if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
    }
}

#Preview {
    NavigationStack { MediaControlsView() }
}
