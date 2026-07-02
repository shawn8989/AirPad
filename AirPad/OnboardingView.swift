import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some View {
        TabView {
            OnboardingPage(
                title: "Control your Mac",
                systemImage: "bonjour",
                text: "AirPad finds your Macs on the local network and connects over an encrypted, paired channel. Approve the pairing once on the Mac and you're in — switch between Macs anytime from the picker at the top."
            )
            OnboardingPage(
                title: "Trackpad",
                systemImage: "hand.draw",
                text: "1 finger moves the cursor, tap to click, double-tap to lock a drag. 2 fingers scroll (fast flick = browser back/forward, 2-finger tap = right click). Pinch to zoom.",
                detail: "Blue dots show every finger the pad detects."
            )
            OnboardingPage(
                title: "Multi-finger gestures",
                systemImage: "hand.raised.fingers.spread",
                text: "Swipe 3 or 4 fingers: left/right switches desktops, up opens Mission Control, down shows the current app's windows.",
                detail: "Swipes fire when you lift your fingers."
            )
            OnboardingPage(
                title: "Air Mouse",
                systemImage: "dot.circle.and.hand.point.up.left.fill",
                text: "Hold the aim pad and move your phone like a Wii remote to steer the cursor. Release to freeze. Hold the green pad and tilt to scroll.",
                detail: "Snap your wrist (pads released) to switch desktops."
            )
            OnboardingPage(
                title: "Hand Mouse",
                systemImage: "hand.point.up.left",
                text: "The front camera tracks your hand. Point with your index finger to move the cursor, pinch thumb+index to click, hold the pinch to drag.",
                detail: "Open palm: swipe = switch desktop, hold still = Mission Control. Two-finger V: scroll. Video never leaves your phone."
            )
            OnboardingPage(
                title: "Media, Clipboard & More",
                systemImage: "playpause.fill",
                text: "The Media screen has volume, playback, brightness, presentation slides, clipboard sync, and screen lock. Dictation types what you say directly on the Mac.",
                detail: "Find everything on the main screen after you connect."
            )
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    hasCompletedOnboarding = true
                    dismiss()
                }
            }
        }
        .navigationTitle("Welcome")
    }
}

private struct OnboardingPage: View {
    var title: String
    var systemImage: String
    var text: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.title.bold())
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()
            Spacer()
        }
        .padding()
    }
}

#Preview {
    NavigationStack { OnboardingView() }
}
