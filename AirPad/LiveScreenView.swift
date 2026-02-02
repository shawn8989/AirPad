import SwiftUI

struct LiveScreenView: View {
    @StateObject private var network = NetworkManager.shared
    @State private var isStreaming = false
    @State private var fitMode: ContentMode = .fit

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.thinMaterial)
                if let img = network.liveImage {
                    GeometryReader { geo in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: fitMode == .fit ? .fit : .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "display")
                            .font(.system(size: 48))
                        Text("No frames yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                fpsOverlay
                    .padding(8)
            }
            .overlay(alignment: .bottomTrailing) {
                fitToggle
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding()

            HStack {
                Button(isStreaming ? "Stop" : "Start") {
                    if isStreaming {
                        network.stopLiveScreen()
                    } else {
                        network.startLiveScreen(maxWidth: 1024, quality: 0.7)
                    }
                    isStreaming.toggle()
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                if isStreaming {
                    Text(String(format: "%.1f FPS", network.liveFPS))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding([.horizontal, .bottom])
        }
        .navigationTitle("Live Screen")
        .onDisappear {
            if isStreaming {
                network.stopLiveScreen()
                isStreaming = false
            }
        }
    }

    private var fpsOverlay: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
            Text(String(format: "%.1f FPS", network.liveFPS))
        }
        .font(.caption.monospacedDigit())
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var fitToggle: some View {
        Menu {
            Picker("Content Mode", selection: $fitMode) {
                Text("Fit").tag(ContentMode.fit)
                Text("Fill").tag(ContentMode.fill)
            }
        } label: {
            Label(fitMode == .fit ? "Fit" : "Fill", systemImage: fitMode == .fit ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                .font(.caption)
                .padding(6)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

#Preview {
    NavigationStack { LiveScreenView() }
}
