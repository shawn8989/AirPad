import SwiftUI
import CoreMotion

/// Gyro-driven pointer control ("Wii remote" style): while the aim pad is
/// held, the phone's rotation rate steers the Mac cursor. Angular velocity
/// maps to pointer velocity through the existing coalesced mouse pipeline,
/// so latency and backpressure behavior match the trackpad.
final class AirMouseController: ObservableObject {
    private let motion = CMMotionManager()
    @Published var isAiming = false
    @Published var motionAvailable = true
    var sensitivity: Double = 1.0

    func start() {
        guard motion.isDeviceMotionAvailable else {
            motionAvailable = false
            return
        }
        guard !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] dm, _ in
            guard let self, let dm, self.isAiming else { return }
            let rate = dm.rotationRate
            // Deadzone swallows sensor noise and hand tremor at rest.
            let dead = 0.02
            let rz = abs(rate.z) > dead ? rate.z : 0   // yaw: twist left/right
            let rx = abs(rate.x) > dead ? rate.x : 0   // pitch: tilt up/down
            if rz == 0 && rx == 0 { return }
            // rad/s -> px per update. ~1000 px per radian at default
            // sensitivity feels close to a Wii pointer.
            let gain = 1000.0 * self.sensitivity / 60.0
            NetworkManager.shared.sendMouseDelta(dx: -rz * gain, dy: -rx * gain)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        isAiming = false
    }
}

struct AirMouseView: View {
    @AppStorage("airMouseSensitivity") private var airMouseSensitivity: Double = 1.0
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true

    @StateObject private var controller = AirMouseController()
    @State private var dragLocked = false

    var body: some View {
        VStack(spacing: 16) {
            Text(controller.isAiming ? "Aiming — move your phone" : "Hold the pad to aim")
                .font(.headline)
                .foregroundStyle(controller.isAiming ? .primary : .secondary)

            // Aim pad: press and hold to steer, release to freeze the cursor
            // (like lifting a mouse off the desk).
            RoundedRectangle(cornerRadius: 24)
                .fill(controller.isAiming ? Color.accentColor.opacity(0.35) : Color(.secondarySystemBackground))
                .overlay(
                    VStack(spacing: 10) {
                        Image(systemName: controller.isAiming ? "dot.circle.and.hand.point.up.left.fill" : "hand.point.up.left")
                            .font(.system(size: 56))
                        Text(controller.isAiming ? "Steering the cursor" : "Hold to aim")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 24))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !controller.isAiming {
                                controller.isAiming = true
                                if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                            }
                        }
                        .onEnded { _ in controller.isAiming = false }
                )
                .padding(.horizontal)

            if !controller.motionAvailable {
                Label("Motion sensors unavailable on this device", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            HStack {
                Text("Sensitivity")
                Slider(value: $airMouseSensitivity, in: 0.25...3.0, step: 0.05)
            }
            .padding(.horizontal)

            HStack {
                Button {
                    NetworkManager.shared.sendClick(button: "left")
                    if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                } label: {
                    Label("Click", systemImage: "cursorarrow.click")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    dragLocked.toggle()
                    if dragLocked {
                        NetworkManager.shared.sendMouseDown(button: "left")
                    } else {
                        NetworkManager.shared.sendMouseUp(button: "left")
                    }
                    if hapticsEnabled { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
                } label: {
                    Label(dragLocked ? "Release" : "Drag", systemImage: dragLocked ? "hand.raised.fill" : "hand.draw")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(dragLocked ? .orange : nil)

                Button {
                    NetworkManager.shared.sendClick(button: "right")
                    if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                } label: {
                    Label("Right", systemImage: "cursorarrow.rays")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .navigationTitle("Air Mouse")
        .onAppear {
            controller.sensitivity = airMouseSensitivity
            controller.start()
        }
        .onDisappear {
            if dragLocked {
                NetworkManager.shared.sendMouseUp(button: "left")
                dragLocked = false
            }
            controller.stop()
        }
        .onChange(of: airMouseSensitivity) { _, newValue in
            controller.sensitivity = newValue
        }
    }
}

#Preview {
    NavigationStack { AirMouseView() }
}
