import SwiftUI

/// Remote media and system controls for the connected Mac: volume, playback,
/// display brightness, and screen lock. Each button maps to an NX_KEYTYPE_*
/// system key (or key chord) injected by AirBridge.
struct MediaControlsView: View {
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @State private var confirmLock = false

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
