import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some View {
        TabView {
            OnboardingPage(title: "Discover your Mac", systemImage: "bonjour", text: "AirPad finds your Mac on the local network using Bonjour.")
            OnboardingPage(title: "Pair & Trust", systemImage: "checkmark.shield", text: "On first connect, we pair and remember the server fingerprint to protect future sessions.")
            OnboardingPage(title: "Permissions", systemImage: "wifi", text: "Allow Local Network access when prompted so AirPad can find your Mac.")
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
            Spacer()
        }
        .padding()
    }
}

#Preview {
    NavigationStack { OnboardingView() }
}

