import SwiftUI
import AVFoundation
import Vision

/// Camera hand-tracking pointer ("Hand Mouse"): the front camera watches your
/// hand via Vision's hand-pose detector. Moving your index fingertip steers
/// the Mac cursor; pinching thumb and index together presses the mouse button
/// (quick pinch = click, hold = drag). All processing is on-device; only the
/// same small mouse packets as the trackpad go over the network.
final class HandTrackingController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let cameraQueue = DispatchQueue(label: "airpad.handmouse.camera")
    private let request = VNDetectHumanHandPoseRequest()

    @Published var running = false
    @Published var handVisible = false
    @Published var pinching = false
    @Published var permissionDenied = false

    var sensitivity: Double = 1.0
    var trackingEnabled = true

    // Smoothed fingertip position (normalized 0...1) and pinch state, owned by
    // the camera queue.
    private var smoothed: CGPoint?
    private var lastSent: CGPoint?
    private var pinchActive = false
    private var lostFrames = 0

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
            self.smoothed = nil
            self.lastSent = nil
        }
        running = false
        handVisible = false
        pinching = false
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard trackingEnabled, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])

        guard let hand = request.results?.first,
              let index = try? hand.recognizedPoint(.indexTip), index.confidence > 0.35 else {
            handLost()
            return
        }

        lostFrames = 0
        if !handVisible { DispatchQueue.main.async { self.handVisible = true } }

        // Vision coordinates are normalized with origin at bottom-left of the
        // (landscape, mirrored) front-camera frame. Map so that moving the hand
        // right/up on screen moves the cursor right/up regardless.
        var p = CGPoint(x: 1 - index.location.y, y: 1 - index.location.x)
        p.x = 1 - p.x  // front camera is mirrored horizontally

        // Exponential smoothing tames per-frame Vision jitter.
        if let s = smoothed {
            let alpha: CGFloat = 0.4
            p = CGPoint(x: s.x + (p.x - s.x) * alpha, y: s.y + (p.y - s.y) * alpha)
        }
        smoothed = p

        if let last = lastSent {
            // Normalized delta -> pixels. ~1600 px across the full camera view
            // at default sensitivity.
            let dx = Double(p.x - last.x) * 1600.0 * sensitivity
            let dy = Double(p.y - last.y) * 1600.0 * sensitivity
            if abs(dx) >= 0.5 || abs(dy) >= 0.5 {
                NetworkManager.shared.sendMouseDelta(dx: dx, dy: dy)
                lastSent = p
            }
        } else {
            lastSent = p
        }

        // Pinch: thumb tip close to index tip presses the button; hysteresis
        // (0.05 to close, 0.09 to open) prevents flutter at the boundary.
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

    private func handLost() {
        lostFrames += 1
        // Small grace period so one bad frame doesn't drop the hand.
        guard lostFrames == 5 else { return }
        smoothed = nil
        lastSent = nil
        if pinchActive {
            pinchActive = false
            NetworkManager.shared.sendMouseUp(button: "left")
            DispatchQueue.main.async { self.pinching = false }
        }
        DispatchQueue.main.async { self.handVisible = false }
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

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                CameraPreview(session: controller.session)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(controller.pinching ? Color.orange :
                                          (controller.handVisible ? Color.green : Color.secondary.opacity(0.4)),
                                          lineWidth: 3)
                    )

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

            HStack(spacing: 16) {
                Label(controller.handVisible ? "Hand tracked" : "Show your hand",
                      systemImage: controller.handVisible ? "hand.raised.fill" : "hand.raised.slash")
                    .foregroundStyle(controller.handVisible ? .green : .secondary)
                Label(controller.pinching ? "Pinching (button down)" : "Pinch to click",
                      systemImage: controller.pinching ? "hand.pinch.fill" : "hand.pinch")
                    .foregroundStyle(controller.pinching ? .orange : .secondary)
            }
            .font(.footnote)

            HStack {
                Text("Sensitivity")
                Slider(value: $handMouseSensitivity, in: 0.25...3.0, step: 0.05)
            }
            .padding(.horizontal)

            Text("Point with your index finger to move the cursor. Pinch thumb and index together for a click; hold the pinch to drag.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
