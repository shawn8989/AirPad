import SwiftUI
import AVFoundation
import Vision
import QuartzCore

/// Camera hand-tracking pointer ("Hand Mouse"): the front camera watches your
/// hand via Vision's hand-pose detector. All processing is on-device; only the
/// same small input packets as the trackpad go over the network.
///
/// Poses:
///  - Point (index finger, or relaxed hand) — fingertip steers the cursor;
///    pinch thumb+index to click, hold the pinch to drag.
///  - Open palm (all fingers spread) — pointer pauses; swipe the palm left or
///    right to switch desktops; hold the palm still to open Mission Control.
///  - Two-finger "V" (index+middle up) — move the hand up/down to scroll.
final class HandTrackingController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum HandPose: String { case none = "No hand", pointer = "Pointer", palm = "Palm", scroll = "Scroll" }

    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let cameraQueue = DispatchQueue(label: "airpad.handmouse.camera")
    private let request = VNDetectHumanHandPoseRequest()

    @Published var running = false
    @Published var pose: HandPose = .none
    @Published var pinching = false
    @Published var permissionDenied = false

    var sensitivity: Double = 1.0
    var trackingEnabled = true

    // Camera-queue state.
    private var smoothed: CGPoint?
    private var lastSent: CGPoint?
    private var pinchActive = false
    private var lostFrames = 0
    private var currentPose: HandPose = .none
    private var palmStillSince: TimeInterval = 0
    private var lastGestureTime: TimeInterval = 0
    private var lastPalmX: CGFloat?
    private var palmTravel: CGFloat = 0

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraQueue.async { self.configureAndRun() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                DispatchQueue.main.async { self.permissionDenied = !granted }
                if granted { self.cameraQueue.async { self.configureAndRun() } }
            }
        default:
            permissionDenied = true
        }
    }

    private func configureAndRun() {
        if session.inputs.isEmpty {
            session.beginConfiguration()
            session.sessionPreset = .vga640x480
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: cameraQueue)
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            request.maximumHandCount = 1
        }
        guard !session.isRunning else { return }
        session.startRunning()
        DispatchQueue.main.async { self.running = true }
    }

    func stop() {
        cameraQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            if self.pinchActive {
                self.pinchActive = false
                NetworkManager.shared.sendMouseUp(button: "left")
            }
            self.resetTracking()
        }
        running = false
        pose = .none
        pinching = false
    }

    private func resetTracking() {
        smoothed = nil
        lastSent = nil
        lastPalmX = nil
        palmTravel = 0
        palmStillSince = 0
        currentPose = .none
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard trackingEnabled, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])

        guard let hand = request.results?.first,
              let index = try? hand.recognizedPoint(.indexTip), index.confidence > 0.35,
              let wrist = try? hand.recognizedPoint(.wrist), wrist.confidence > 0.2 else {
            handLost()
            return
        }
        lostFrames = 0

        let newPose = classifyPose(hand: hand, wrist: wrist)
        if newPose != currentPose {
            currentPose = newPose
            // Pose changed: restart positional tracking so the cursor doesn't jump.
            smoothed = nil
            lastSent = nil
            lastPalmX = nil
            palmTravel = 0
            palmStillSince = CACurrentMediaTime()
            DispatchQueue.main.async { self.pose = newPose }
        }

        switch currentPose {
        case .pointer:
            trackPointer(hand: hand, index: index)
        case .palm:
            trackPalmGestures(hand: hand)
        case .scroll:
            trackScroll(index: index)
        case .none:
            break
        }
    }

    /// Extended-finger classification: a finger is "up" when its tip is
    /// meaningfully farther from the wrist than its middle (PIP) joint.
    private func classifyPose(hand: VNHumanHandPoseObservation, wrist: VNRecognizedPoint) -> HandPose {
        func extended(_ tip: VNHumanHandPoseObservation.JointName,
                      _ pip: VNHumanHandPoseObservation.JointName) -> Bool {
            guard let t = try? hand.recognizedPoint(tip), t.confidence > 0.3,
                  let p = try? hand.recognizedPoint(pip), p.confidence > 0.3 else { return false }
            let dt = hypot(t.location.x - wrist.location.x, t.location.y - wrist.location.y)
            let dp = hypot(p.location.x - wrist.location.x, p.location.y - wrist.location.y)
            return dt > dp * 1.15
        }
        let indexUp = extended(.indexTip, .indexPIP)
        let middleUp = extended(.middleTip, .middlePIP)
        let ringUp = extended(.ringTip, .ringPIP)
        let littleUp = extended(.littleTip, .littlePIP)

        if indexUp && middleUp && ringUp && littleUp { return .palm }
        if indexUp && middleUp && !ringUp && !littleUp { return .scroll }
        return .pointer
    }

    /// Maps a Vision-normalized fingertip position to screen motion.
    /// Vision reports coordinates in the (landscape, mirrored) camera frame;
    /// for a portrait phone this maps buffer-y -> screen-x and buffer-x ->
    /// screen-y, plus the front-camera mirror.
    private func screenPoint(for location: CGPoint) -> CGPoint {
        CGPoint(x: 1 - location.y, y: location.x)
    }

    private func trackPointer(hand: VNHumanHandPoseObservation, index: VNRecognizedPoint) {
        var p = screenPoint(for: index.location)
        if let s = smoothed {
            let alpha: CGFloat = 0.4
            p = CGPoint(x: s.x + (p.x - s.x) * alpha, y: s.y + (p.y - s.y) * alpha)
        }
        smoothed = p

        if let last = lastSent {
            let dx = Double(p.x - last.x) * 1600.0 * sensitivity
            let dy = Double(p.y - last.y) * 1600.0 * sensitivity
            if abs(dx) >= 0.5 || abs(dy) >= 0.5 {
                NetworkManager.shared.sendMouseDelta(dx: dx, dy: dy)
                lastSent = p
            }
        } else {
            lastSent = p
        }

        // Pinch with hysteresis (close at 0.05, open at 0.09) to avoid flutter.
        if let thumb = try? hand.recognizedPoint(.thumbTip), thumb.confidence > 0.35 {
            let d = hypot(index.location.x - thumb.location.x,
                          index.location.y - thumb.location.y)
            if !pinchActive && d < 0.05 {
                pinchActive = true
                NetworkManager.shared.sendMouseDown(button: "left")
                DispatchQueue.main.async {
                    self.pinching = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } else if pinchActive && d > 0.09 {
                pinchActive = false
                NetworkManager.shared.sendMouseUp(button: "left")
                DispatchQueue.main.async {
                    self.pinching = false
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
    }

    /// Open palm: lateral swipe switches desktops; holding still opens
    /// Mission Control. The pointer stays paused the whole time.
    private func trackPalmGestures(hand: VNHumanHandPoseObservation) {
        releasePinchIfNeeded()
        guard let middle = try? hand.recognizedPoint(.middleTip) else { return }
        let x = screenPoint(for: middle.location).x
        let now = CACurrentMediaTime()

        if let last = lastPalmX {
            let delta = x - last
            // Accumulate consistent lateral travel; reset on direction change.
            if palmTravel.sign != delta.sign { palmTravel = 0 }
            palmTravel += delta
            if abs(delta) > 0.004 { palmStillSince = now }

            if abs(palmTravel) > 0.22 && now - lastGestureTime > 1.0 {
                lastGestureTime = now
                let dir = palmTravel > 0 ? "right" : "left"
                palmTravel = 0
                NetworkManager.shared.sendSwipe(fingers: 3, direction: dir)
                DispatchQueue.main.async { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
            } else if now - palmStillSince > 1.0 && now - lastGestureTime > 1.5 {
                lastGestureTime = now
                NetworkManager.shared.sendSwipe(fingers: 3, direction: "up")   // Mission Control
                DispatchQueue.main.async { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
            }
        } else {
            palmStillSince = now
        }
        lastPalmX = x
    }

    /// Two-finger V: vertical hand motion scrolls.
    private func trackScroll(index: VNRecognizedPoint) {
        releasePinchIfNeeded()
        var p = screenPoint(for: index.location)
        if let s = smoothed {
            let alpha: CGFloat = 0.4
            p = CGPoint(x: s.x + (p.x - s.x) * alpha, y: s.y + (p.y - s.y) * alpha)
        }
        smoothed = p
        if let last = lastSent {
            let dy = Double(p.y - last.y) * 1400.0 * sensitivity
            if abs(dy) >= 0.5 {
                NetworkManager.shared.sendScroll(dx: 0, dy: -dy)
                lastSent = p
            }
        } else {
            lastSent = p
        }
    }

    private func releasePinchIfNeeded() {
        if pinchActive {
            pinchActive = false
            NetworkManager.shared.sendMouseUp(button: "left")
            DispatchQueue.main.async { self.pinching = false }
        }
    }

    private func handLost() {
        lostFrames += 1
        // Small grace period so one bad frame doesn't drop the hand.
        guard lostFrames == 5 else { return }
        releasePinchIfNeeded()
        resetTracking()
        DispatchQueue.main.async { self.pose = .none }
    }
}

/// Live camera preview so you can see your hand's position in frame.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

struct HandMouseView: View {
    @AppStorage("handMouseSensitivity") private var handMouseSensitivity: Double = 1.0
    @StateObject private var controller = HandTrackingController()

    private var borderColor: Color {
        if controller.pinching { return .orange }
        switch controller.pose {
        case .none: return Color.secondary.opacity(0.4)
        case .pointer: return .green
        case .palm: return .blue
        case .scroll: return .purple
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                CameraPreview(session: controller.session)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(borderColor, lineWidth: 3)
                    )
                    .overlay(alignment: .topLeading) {
                        Label(controller.pinching ? "Pinch — button down" : controller.pose.rawValue,
                              systemImage: controller.pose == .none ? "hand.raised.slash" : "hand.raised.fill")
                            .font(.footnote.weight(.semibold))
                            .padding(8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                    }

                if controller.permissionDenied {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash.fill").font(.largeTitle)
                        Text("Camera access is off.\nEnable it in Settings > AirPad.")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                } else if !controller.running {
                    ProgressView("Starting camera…")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal)

            HStack {
                Text("Sensitivity")
                Slider(value: $handMouseSensitivity, in: 0.25...3.0, step: 0.05)
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 4) {
                Label("Point: move finger to steer • pinch = click, hold pinch = drag", systemImage: "hand.point.up.left")
                Label("Open palm: swipe left/right = switch desktop • hold still = Mission Control", systemImage: "hand.raised")
                Label("Two-finger V: move up/down to scroll", systemImage: "hand.point.up.braille")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .navigationTitle("Hand Mouse")
        .onAppear {
            controller.sensitivity = handMouseSensitivity
            controller.start()
        }
        .onDisappear { controller.stop() }
        .onChange(of: handMouseSensitivity) { _, newValue in
            controller.sensitivity = newValue
        }
    }
}

#Preview {
    NavigationStack { HandMouseView() }
}
