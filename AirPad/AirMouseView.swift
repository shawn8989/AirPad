import SwiftUI
import CoreMotion

/// Gyro-driven pointer control ("Wii remote" style): while the aim pad is
/// held, the phone's rotation rate steers the Mac cursor. Angular velocity
/// maps to pointer velocity through the existing coalesced mouse pipeline,
/// so latency and backpressure behavior match the trackpad.
final class AirMouseController: ObservableObject {
    enum Mode { case idle, pointer, scroll }

    private let motion = CMMotionManager()
    @Published var mode: Mode = .idle
    @Published var motionAvailable = true
    var sensitivity: Double = 1.0
    var flickEnabled = true
    var hapticsEnabled = true

    private var lastFlickTime: TimeInterval = 0

    func start() {
        guard motion.isDeviceMotionAvailable else {
            motionAvailable = false
            return
        }
        guard !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] dm, _ in
            guard let self, let dm else { return }
            let rate = dm.rotationRate

            // Flick: a sharp twist while NOT holding a pad switches desktops,
            // so it can never fight with pointer aiming.
            if self.mode == .idle {
                guard self.flickEnabled else { return }
                let now = dm.timestamp
                if abs(rate.z) > 4.5 && now - self.lastFlickTime > 0.8 {
                    self.lastFlickTime = now
                    // Clockwise snap (negative z) = flick right = next Space.
                    NetworkManager.shared.sendSwipe(fingers: 3, direction: rate.z < 0 ? "right" : "left")
                    if self.hapticsEnabled { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
                }
                return
            }

            // Deadzone swallows sensor noise and hand tremor at rest.
            let dead = 0.02
            let rz = abs(rate.z) > dead ? rate.z : 0   // yaw: twist left/right
            let rx = abs(rate.x) > dead ? rate.x : 0   // pitch: tilt up/down
            if rz == 0 && rx == 0 { return }
            // rad/s -> px per update. ~1000 px per radian at default
            // sensitivity feels close to a Wii pointer.
            let gain = 1000.0 * self.sensitivity / 60.0
            switch self.mode {
            case .pointer:
                NetworkManager.shared.sendMouseDelta(dx: -rz * gain, dy: -rx * gain)
            case .scroll:
                // Tilt to scroll; horizontal twist scrolls sideways.
                NetworkManager.shared.sendScroll(dx: -rz * gain * 0.6, dy: rx * gain * 0.6)
            case .idle:
                break
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        mode = .idle
    }
}

struct AirMouseView: View {
    @AppStorage("airMouseSensitivity") private var airMouseSensitivity: Double = 1.0
    @AppStorage("airFlickEnabled") private var airFlickEnabled: Bool = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true

    @StateObject private var controller = AirMouseController()
    @State private var dragLocked = false

    private var statusText: String {
        switch controller.mode {
        case .pointer: return "Aiming — move your phone"
        case .scroll: return "Scrolling — tilt your phone"
        case .idle: return airFlickEnabled ? "Hold a pad to aim • snap wrist to switch desktops" : "Hold a pad to aim"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(statusText)
                .font(.headline)
                .foregroundStyle(controller.mode == .idle ? .secondary : .primary)

            // Aim pad: press and hold to steer, release to freeze the cursor
            // (like lifting a mouse off the desk).
            RoundedRectangle(cornerRadius: 24)
                .fill(controller.mode == .pointer ? Color.accentColor.opacity(0.35) : Color(.secondarySystemBackground))
                .overlay(
                    VStack(spacing: 10) {
                        Image(systemName: controller.mode == .pointer ? "dot.circle.and.hand.point.up.left.fill" : "hand.point.up.left")
                            .font(.system(size: 56))
                        Text(controller.mode == .pointer ? "Steering the cursor" : "Hold to aim")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 24))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if controller.mode != .pointer {
                                controller.mode = .pointer
                                if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                            }
                        }
                        .onEnded { _ in controller.mode = .idle }
                )
                .padding(.horizontal)

            // Scroll pad: hold and tilt to scroll instead of pointing.
            RoundedRectangle(cornerRadius: 18)
                .fill(controller.mode == .scroll ? Color.green.opacity(0.35) : Color(.secondarySystemBackground))
                .overlay(
                    Label(controller.mode == .scroll ? "Scrolling" : "Hold to scroll",
                          systemImage: "arrow.up.and.down.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                )
                .frame(height: 64)
                .contentShape(RoundedRectangle(cornerRadius: 18))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if controller.mode != .scroll {
                                controller.mode = .scroll
                                if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                            }
                        }
                        .onEnded { _ in controller.mode = .idle }
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

            Toggle(isOn: $airFlickEnabled) {
                Label("Wrist flick switches desktops", systemImage: "arrow.left.arrow.right")
                    .font(.subheadline)
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
            controller.flickEnabled = airFlickEnabled
            controller.hapticsEnabled = hapticsEnabled
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
        .onChange(of: airFlickEnabled) { _, newValue in
            controller.flickEnabled = newValue
        }
    }
}

#Preview {
    NavigationStack { AirMouseView() }
}
