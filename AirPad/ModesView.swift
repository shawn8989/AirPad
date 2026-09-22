//
//  ModesView.swift
//  AirPad
//
//  Everything that isn't the trackpad.
//
//  These used to be nine equal-weight tiles crammed under the trackpad on the
//  main screen, which cost the pad half its height and still made nothing easy
//  to find — Live Screen sat next to Help, and the desktop switcher was
//  indistinguishable from Settings. On their own screen they get room to be
//  grouped and described, and the trackpad gets its space back.
//

import SwiftUI

struct ModesView: View {
    @ObservedObject private var proStore = ProStore.shared

    var body: some View {
        List {
            Section("Control") {
                row("Keyboard", "keyboard",
                    "Type on the Mac, with a trackpad and click buttons") { KeyboardModeView() }
                row("Air Mouse", "dot.circle.and.hand.point.up.left.fill",
                    "Point the phone like a remote", pro: true) { AirMouseView() }
                row("Hand Mouse", "hand.point.up.left",
                    "Control the cursor with camera hand gestures", pro: true) { HandMouseView() }
            }

            Section("See the Mac") {
                row("Live Screen", "display",
                    "Stream the Mac's screen and touch what you see", pro: true) { LiveScreenView() }
                row("Desktops & Apps", "macwindow.on.rectangle",
                    "Jump to any desktop or open window", pro: true) { MacSwitcherView() }
                row("Watch on a TV", "tv",
                    "Mirror the Mac to a TV and use the phone as the remote",
                    pro: true) { LiveScreenView(startWithMirrorTip: true) }
            }

            Section("Media") {
                row("Media Remote", "playpause.fill",
                    "Playback, volume, and which speaker the Mac uses", pro: true) { MediaControlsView() }
            }

            Section {
                row("Settings", "gearshape", "Pointer speed, scrolling, haptics") { SettingsView() }
                row("Help", "questionmark.circle", "Gestures and troubleshooting") { HelpView() }
            }
        }
        .navigationTitle("Modes")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Pro rows route to the paywall once the trial ends, exactly as the tiles
    /// did — the lock is shown on the row rather than as a badge on a tile.
    @ViewBuilder
    private func row<D: View>(_ title: String, _ icon: String, _ subtitle: String,
                              pro: Bool = false,
                              @ViewBuilder destination: () -> D) -> some View {
        let locked = pro && !proStore.isPro
        NavigationLink(destination: locked ? AnyView(PaywallView()) : AnyView(destination())) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 30)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
