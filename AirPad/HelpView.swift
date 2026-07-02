import SwiftUI

struct HelpView: View {
    var body: some View {
        List {
            Section("Getting Started") {
                helpRow("1. Run AirBridge on your Mac (menu bar).")
                helpRow("2. Put both devices on the same Wi-Fi network.")
                helpRow("3. Pick your Mac in AirPad and approve the pairing dialog on the Mac — once per device.")
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
                gestureRow("hand.point.up.left", "Point", "Index finger steers the cursor. Pinch thumb+index = click; hold the pinch = drag.")
                gestureRow("hand.raised", "Open palm", "Pauses the cursor. Swipe the palm left/right = switch desktop. Hold still ~1s = Mission Control.")
                gestureRow("hand.point.up.braille", "Two-finger V", "Index+middle up: move your hand up/down to scroll.")
                helpRow("Tips: good lighting, hand 1–2 ft from the phone, palm facing the camera. The border color shows the detected pose. Video is processed on-device and never transmitted.")
            }

            Section("Media & System") {
                helpRow("Volume, play/pause/skip, and display brightness use the Mac's real media keys (you'll see the on-screen HUD).")
                helpRow("Presentation: previous/next slide and blank-screen for Keynote, PowerPoint, and Google Slides.")
                helpRow("Clipboard: send your iPhone clipboard to the Mac (paste with ⌘V), type it directly, or fetch the Mac's clipboard to your phone.")
                helpRow("Lock Mac Screen asks for confirmation first.")
            }

            Section("Dictation") {
                helpRow("Click where you want the text on the Mac, then dictate on the phone, review the transcript, and tap Type on Mac.")
            }

            Section("Keyboard, Apps & Live Screen") {
                helpRow("Keyboard: type text, use modifier keys (⌘⌥⌃⇧) and special keys.")
                helpRow("Apps: launch or focus Mac apps and switch desktops/windows.")
                helpRow("Live Screen: watch the Mac's screen live with adjustable quality; use pointer mode to control what you see.")
            }

            Section("Privacy & Security") {
                helpRow("Traffic stays on your local network, encrypted with TLS. Every device is paired and authenticated per-Mac; the Mac only obeys authenticated devices.")
                helpRow("Reset trust anytime with Forget Server, then re-pair.")
            }

            Section("Troubleshooting") {
                helpRow("Can't find the Mac? Same Wi-Fi network, AirBridge running, and Local Network permission allowed.")
                helpRow("Desktop switching needs more than one desktop (Mission Control > +).")
                helpRow("Input not working? Check the Mac's Accessibility permission for AirBridge (System Settings > Privacy & Security > Accessibility).")
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
