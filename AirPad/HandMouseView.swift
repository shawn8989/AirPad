import SwiftUI
import Combine
import AVFoundation

//
//  HandMouseView — thin UI + adapter over the HandEngine module.
//  HandEngine (HandTracker / HandGestureRecognizer / HandCursorMapper) knows
//  nothing about networking; this view maps its semantic events onto
//  NetworkManager calls. Another app (a game, etc.) could reuse HandEngine
//  with a different adapter.
//

final class HandMouseAdapter: ObservableObject {
    let tracker = HandTracker()
    let recognizer = HandGestureRecognizer()

    @Published var running = false
    @Published var permissionDenied = false
    @Published var pose: HandPose = .none
    @Published var pinching = false

    init() {
        tracker.onPermission = { [weak self] granted in self?.permissionDenied = !granted }
        tracker.onRunning = { [weak self] running in self?.running = running }
        tracker.onFrame = { [weak self] hand in self?.recognizer.process(hand) }
        recognizer.onPoseChanged = { [weak self] pose in
            DispatchQueue.main.async { self?.pose = pose }
        }
        recognizer.onEvent = { [weak self] event in self?.handle(event) }
    }

    var config: HandGestureConfig {
        get { recognizer.config }
        set { recognizer.config = newValue }
    }

    func start() { tracker.start() }

    func stop() {
        recognizer.reset()   // releases any held pinch/drag
        tracker.stop()
    }

    /// Maps engine events to Mac input. Runs on the camera queue — the
    /// NetworkManager senders are queue-safe; only UI state hops to main.
    private func handle(_ event: HandEvent) {
        switch event {
        case .move(let dx, let dy):
            NetworkManager.shared.sendMouseDelta(dx: dx, dy: dy)
        case .scroll(let dy):
            NetworkManager.shared.sendScroll(dx: 0, dy: dy)
        case .pinchBegan:
            NetworkManager.shared.sendMouseDown(button: "left")
            DispatchQueue.main.async {
                self.pinching = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        case .pinchEnded:
            NetworkManager.shared.sendMouseUp(button: "left")
            DispatchQueue.main.async {
                self.pinching = false
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        case .palmSwipe(let right):
            NetworkManager.shared.sendSwipe(fingers: 3, direction: right ? "right" : "left")
            heavyHaptic()
        case .palmHold:
            NetworkManager.shared.sendSwipe(fingers: 3, direction: "up")  // Mission Control
            heavyHaptic()
        case .fistDragBegan:
            NetworkManager.shared.sendMouseDown(button: "left")
            DispatchQueue.main.async {
                self.pinching = true
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            }
        case .fistDragEnded:
            NetworkManager.shared.sendMouseUp(button: "left")
            DispatchQueue.main.async {
                self.pinching = false
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        case .thumbsUpHold:
            NetworkManager.shared.sendMedia(action: "play_pause")
            heavyHaptic()
        case .shakaHold:
            NetworkManager.shared.sendSwipe(fingers: 3, direction: "right")  // next desktop
            heavyHaptic()
        case .custom(let id):
            // User-recorded gesture (Gesture Studio): execute its mapped action.
            if let gesture = GestureStore.shared.gesture(id: id) {
                gesture.action.execute()
                heavyHaptic()
            }
        }
    }

    private func heavyHaptic() {
        DispatchQueue.main.async { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
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
    @AppStorage("handGesturePalmSwipe") private var palmSwipeEnabled = true
    @AppStorage("handGesturePalmHold") private var palmHoldEnabled = true
    @AppStorage("handGestureScroll") private var scrollEnabled = true
    @AppStorage("handGestureFistDrag") private var fistDragEnabled = true
    @AppStorage("handGestureThumbsUp") private var thumbsUpEnabled = true
    @AppStorage("handGestureShaka") private var shakaEnabled = true

    @StateObject private var adapter = HandMouseAdapter()
    @State private var showGestureSheet = false

    private var borderColor: Color {
        if adapter.pinching { return .orange }
        switch adapter.pose {
        case .none: return Color.secondary.opacity(0.4)
        case .pointer: return .green
        case .palm: return .blue
        case .scroll: return .purple
        case .fist: return .orange
        case .thumbsUp, .shaka: return .teal
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                CameraPreview(session: adapter.tracker.session)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(borderColor, lineWidth: 3)
                    )
                    .overlay(alignment: .topLeading) {
                        Label(adapter.pinching ? "Pinch — button down" : adapter.pose.rawValue,
                              systemImage: adapter.pose == .none ? "hand.raised.slash" : "hand.raised.fill")
                            .font(.footnote.weight(.semibold))
                            .padding(8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                    }
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 8) {
                            NavigationLink(destination: GestureStudioView()) {
                                Image(systemName: "wand.and.stars")
                                    .padding(8)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            Button {
                                showGestureSheet = true
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .padding(8)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                        }
                        .padding(10)
                    }

                if adapter.permissionDenied {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash.fill").font(.largeTitle)
                        Text("Camera access is off.\nEnable it in Settings > AirPad.")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                } else if !adapter.running {
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
                Label("Move: relaxed hand steers • pinch = click, hold pinch = drag", systemImage: "hand.point.up.left")
                Label("Fist (hold): grab & drag • Palm: swipe = desktop, hold = Mission Control", systemImage: "hand.raised")
                Label("Two-finger V: scroll • Thumbs-up: play/pause • Shaka 🤙: next desktop", systemImage: "hand.thumbsup")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .navigationTitle("Hand Mouse")
        .sheet(isPresented: $showGestureSheet) { gestureSheet }
        .onAppear {
            pushConfig()
            adapter.start()
        }
        .onDisappear { adapter.stop() }
        .onChange(of: handMouseSensitivity) { _, _ in pushConfig() }
        .onChange(of: palmSwipeEnabled) { _, _ in pushConfig() }
        .onChange(of: palmHoldEnabled) { _, _ in pushConfig() }
        .onChange(of: scrollEnabled) { _, _ in pushConfig() }
        .onChange(of: fistDragEnabled) { _, _ in pushConfig() }
        .onChange(of: thumbsUpEnabled) { _, _ in pushConfig() }
        .onChange(of: shakaEnabled) { _, _ in pushConfig() }
    }

    private var gestureSheet: some View {
        NavigationStack {
            List {
                Section("Gestures") {
                    Toggle("Palm swipe → switch desktop", isOn: $palmSwipeEnabled)
                    Toggle("Palm hold → Mission Control", isOn: $palmHoldEnabled)
                    Toggle("Two-finger V → scroll", isOn: $scrollEnabled)
                    Toggle("Fist hold → grab & drag", isOn: $fistDragEnabled)
                    Toggle("Thumbs-up → play/pause", isOn: $thumbsUpEnabled)
                    Toggle("Shaka 🤙 → next desktop", isOn: $shakaEnabled)
                }
                Section {
                    Text("Pointing and pinch-to-click are always on. Turn off any gesture that misfires for you.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Hand Gestures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showGestureSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func pushConfig() {
        var c = HandGestureConfig()
        c.sensitivity = handMouseSensitivity
        c.palmSwipeEnabled = palmSwipeEnabled
        c.palmHoldEnabled = palmHoldEnabled
        c.scrollEnabled = scrollEnabled
        c.fistDragEnabled = fistDragEnabled
        c.thumbsUpEnabled = thumbsUpEnabled
        c.shakaEnabled = shakaEnabled
        c.customTemplates = GestureStore.shared.enabledTemplates
        adapter.config = c
    }
}

#Preview {
    NavigationStack { HandMouseView() }
}
