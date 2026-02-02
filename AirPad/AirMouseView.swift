import SwiftUI

struct AirMouseView: View {
    @AppStorage("pointerSensitivity") private var pointerSensitivity: Double = 1.0
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true

    var body: some View {
        VStack(spacing: 16) {
            Text("Air Mouse")
                .font(.largeTitle.bold())
            Text("Move your device to control the pointer. This is a placeholder view.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "dot.circle.and.hand.point.up.left.fill")
                            .font(.system(size: 48))
                        Text("Air Mouse Controller Placeholder")
                            .font(.headline)
                        Text("Sensitivity: \(String(format: "%.2f", pointerSensitivity))  •  Haptics: \(hapticsEnabled ? "On" : "Off")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                )
                .frame(maxWidth: .infinity, maxHeight: 320)
                .padding()

            HStack {
                Button {
                    NetworkManager.shared.sendClick(button: "left")
                } label: {
                    Label("Click", systemImage: "cursorarrow.click")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    NetworkManager.shared.sendClick(button: "right")
                } label: {
                    Label("Right Click", systemImage: "cursorarrow.rays")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            Spacer()
        }
        .navigationTitle("Air Mouse")
    }
}

#Preview {
    NavigationStack { AirMouseView() }
}
