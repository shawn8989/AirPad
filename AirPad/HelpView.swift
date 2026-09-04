import SwiftUI

struct HelpView: View {
    var body: some View {
        List {
            Section("Getting Started") {
                helpRow("1. Run Wield Host on your Mac (menu bar).")
                helpRow("2. Put both devices on the same Wi-Fi network.")
                helpRow("3. Pick your Mac in Wield and approve the pairing dialog on the Mac — once per device.")
                helpRow("Switch Macs anytime from the picker in the top-left of the control screen.")
            }

            Section("Trackpad") {
                gestureRow("hand.point.up.left", "1 finger", "Move the cursor. Tap = click. Double-tap = lock/unlock drag.")
                gestureRow("hand.draw", "2 fingers", "Scroll. Fast horizontal flick = browser back/forward. 2-finger tap = right click.")
                gestureRow("arrow.up.left.and.arrow.down.right", "Pinch", "Zoom in/out (Cmd +/− on the Mac).")
                gestureRow("hand.raised.fingers.spread", "3–4 finger swipe", "Left/right = switch desktop. Up = Mission Control. Down = current app's windows. Fires when you lift your fingers.")
                gestureRow("circle.dotted", "Touch indicators", "Blue dots show each detected finger (toggle in Settings).")
            }

            Section("Air Mouse (motion)") {
                gestureRow("dot.circle.and.hand.point.up.left.fill", "Aim pad", "Hold and move the phone like a Wii remote to steer the cursor; release to freeze it.")
                gestureRow("arrow.up.and.down.circle", "Scroll pad", "Hold the green pad and tilt the phone to scroll.")
                gestureRow("arrow.left.arrow.right", "Wrist flick", "With no pad held, snap your wrist left/right to switch desktops (toggle on the Air Mouse screen).")
                gestureRow("hand.draw.fill", "Drag button", "Holds the mouse button so you can move windows while aiming.")
            }

            Section("Hand Mouse (camera)") {
                gestureRow("hand.point.up.left", "Move", "A relaxed hand steers the cursor (it tracks your knuckles, so clicking won't nudge it). Pinch thumb+index = click; hold the pinch = drag.")
                gestureRow("hand.raised", "Open palm", "Pauses the cursor. Swipe the palm left/right = switch desktop. Hold still ~1s = Mission Control. Palm-hold, thumbs-up, and shaka are remappable in the gesture settings — map them to any action, like opening an app.")
                gestureRow("hand.point.up.braille", "Two-finger V", "Index+middle up: move your hand up/down to scroll.")
                gestureRow("wand.and.stars", "Gesture Studio", "Record your OWN hand poses (tap the wand on the Hand Mouse screen) and map them to shortcuts, media keys, desktops, or typed text.")
                gestureRow("lock.fill", "Gestures lock in", "Once a pose is recognized it STAYS locked — your hand can drift, relax, or wobble without changing it. To switch, hold the new gesture clearly for a moment: the ring on the pose badge fills as it takes over. Choose Steady, Balanced, or Quick in the gesture settings.")
                gestureRow("hand.raised.fingers.spread", "Calibrate", "Two seconds with your hand open teaches Wield your finger proportions — the single biggest improvement if poses feel touchy. Gesture settings → Calibrate my hand.")
                helpRow("Tips: good lighting, hand 1–2 ft from the phone, palm facing the camera. The badge shows the locked pose. Video is processed on-device and never transmitted.")
            }

            Section("Media & System") {
                helpRow("Volume, play/pause/skip, and display brightness use the Mac's real media keys (you'll see the on-screen HUD).")
                helpRow("Presentation: previous/next slide and blank-screen for Keynote, PowerPoint, and Google Slides.")
                helpRow("Clipboard: send your iPhone clipboard to the Mac (paste with ⌘V), type it directly, or fetch the Mac's clipboard to your phone.")
                helpRow("Lock Mac Screen asks for confirmation first.")
            }

            Section("Show your Mac on a TV") {
                helpRow("Best way: mirror FROM THE MAC. Tap TV Setup (or the TV button in Live Screen) and follow the tip — use the pointer to click the Mac's Control Center → Screen Mirroring → your TV. The TV gets the Mac at full quality with sound, and the phone stays free for any mode.")
                helpRow("The Mac's sound can go somewhere else entirely — the Media page has a speaker picker that bounces audio between the TV, headphones, and the Mac's speakers.")
                helpRow("Alternatives: plug the phone into the TV with an HDMI adapter (the TV shows only the Mac's screen while the phone controls), or mirror the phone from its Control Center — though on some iOS versions the TV then follows you between pages.")
                helpRow("Live Screen controls: Pointer = trackpad on the video, Touch = tap exactly what you see, View = zoom/pan without clicking. The Desktop ◀ ▶ buttons switch desktops and the picture follows.")
            }

            Section("Voice Typing") {
                helpRow("Click where you want the text on the Mac, open the keyboard, and tap the mic key — what you say is typed on the Mac when you finish speaking.")
            }

            Section("Keyboard, Apps & Live Screen") {
                helpRow("Keyboard: type text, use modifier keys (⌘⌥⌃⇧) and special keys.")
                helpRow("Apps: launch or focus Mac apps and switch desktops/windows.")
                helpRow("Live Screen: watch the Mac's screen live with adjustable quality; use pointer mode to control what you see.")
                helpRow("Live Screen Touch mode: tap to click exactly what you see, double-tap to open, two fingers to scroll, hold then move to drag, hold and release in place to right-click.")
                helpRow("The keyboard rises automatically when a text field takes focus on the Mac (toggle in Settings).")
            }

            Section("Privacy & Security") {
                helpRow("Traffic stays on your local network, encrypted with TLS. Every device is paired and authenticated per-Mac; the Mac only obeys authenticated devices.")
                helpRow("Reset trust anytime with Forget Server, then re-pair.")
            }

            Section("Away From Home (Pro)") {
                helpRow("Wield is designed for your own Wi-Fi, but Pro users can control their Mac from anywhere with a personal VPN like Tailscale (free): install it on the Mac and this device, then use Wake / IP → Connect by Address with the Mac's VPN address. Wield Host listens on port 52417.")
                helpRow("Wake a sleeping Mac: the Wake / IP menu sends a wake-up signal to any Mac you've paired with. On the Mac, turn on System Settings → Battery → Options → \"Wake for network access\". Moving the trackpad also wakes a dark display.")
            }

            Section("Troubleshooting") {
                helpRow("Can't find the Mac? Same Wi-Fi network, Wield Host running, and Local Network permission allowed.")
                helpRow("On hotel, café, campus, or airport Wi-Fi? Those networks usually block devices from seeing each other, so discovery fails even though both are online. Fix: turn on Personal Hotspot on this iPhone (Settings → Personal Hotspot) and join the Mac to it. You're then on your own private network and everything works normally — including Live Screen.")
                helpRow("Desktop switching needs more than one desktop (Mission Control > +).")
                helpRow("Connected, but the cursor moves and nothing else works? Wield Host is almost certainly not in the Mac's Applications folder. Until it is, macOS runs it from a temporary copy and quietly discards the Accessibility permission no matter how many times you grant it. Quit Wield Host, drag it to Applications, and open it from there.")
                helpRow("Input not working at all? Check the Mac's Accessibility permission for Wield Host (System Settings > Privacy & Security > Accessibility). If old entries are listed, remove them with the minus button and grant it again.")
                helpRow("Says connected but nothing responds? The two halves of the pairing key no longer match — usually after reinstalling Wield Host or resetting its permissions. It should re-pair itself on the next connection. If it doesn't: click Forget next to this device in Wield Host, then reconnect and approve the prompt.")
                helpRow("Laggy? Lower Live Screen quality, or reconnect.")
                helpRow("Pairing errors? Forget Server on the phone, then reconnect and approve again.")
            }
        }
        .navigationTitle("Help")
    }

    private func helpRow(_ text: String) -> some View {
        Text(text).font(.subheadline)
    }

    private func gestureRow(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack { HelpView() }
}
