import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome to AirPad")
                    .font(.largeTitle.bold())

                Group {
                    Text("Getting Started").font(.title2.bold())
                    Text("1. Install and run the AirBridge agent on your Mac.\n2. Ensure your iPhone/iPad and Mac are on the same local network.\n3. Open AirPad and select your Mac from the list.")
                }

                Group {
                    Text("Pairing & Trust").font(.title2.bold())
                    Text("On first connect, AirPad performs Trust On First Use (TOFU). It stores the server's certificate fingerprint and a shared secret to authenticate future sessions. This helps prevent tampering and adds message integrity with HMAC.")
                    Text("If you reinstall the Mac agent or move to a new Mac, the fingerprint may change. Use Reset Trust (Forget Server) to clear the saved fingerprint and shared secret, then reconnect to pair again.")
                }

                Group {
                    Text("Controls").font(.title2.bold())
                    Text("• Trackpad: One-finger drag to move the pointer. Two-finger pan to scroll. Double-tap to lock/unlock drag. Two-finger tap for right click.\n• Keyboard: Send keys, modifiers, and special keys.\n• Live Screen: View the Mac screen with adjustable quality and resolution.")
                }

                Group {
                    Text("Privacy & Security").font(.title2.bold())
                    Text("AirPad communicates only on your local network. TLS encrypts traffic, and HMAC integrity protects messages. You can reset trust anytime in Settings or on the connection screen.")
                }

                Group {
                    Text("Troubleshooting").font(.title2.bold())
                    Text("• Can't find your Mac? Ensure Wi‑Fi is on and both devices are on the same network.\n• Connection blocked? Allow local network access when prompted.\n• Pairing or trust errors? Use Reset Trust and reconnect.\n• Performance issues? Lower Live Screen quality or max width in the Options menu.")
                }

                Spacer(minLength: 12)
            }
            .padding()
        }
        .navigationTitle("Help")
    }
}

#Preview {
    NavigationStack { HelpView() }
}
