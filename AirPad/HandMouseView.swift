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
    /// The pose currently trying to take over, and how close it is (0...1).
    /// Drawn as a filling ring so the lock is visible rather than mysterious.
    @Published var candidatePose: HandPose = .none
    @Published var candidateProgress: Double = 0
    @Published var calibrating = false
    @Published var calibrationDone = false

    init() {
        tracker.onPermission = { [weak self] granted in self?.permissionDenied = !granted }
        tracker.onRunning = { [weak self] running in self?.running = running }
        tracker.onFrame = { [weak self] hand in self?.recognizer.process(hand) }
        recognizer.onPoseChanged = { [weak self] pose in
            DispatchQueue.main.async {
                self?.pose = pose
                self?.candidatePose = .none
                self?.candidateProgress = 0
            }
        }
        recognizer.onPoseCandidate = { [weak self] pose, progress in
            DispatchQueue.main.async {
                self?.candidatePose = progress > 0 ? pose : .none
                self?.candidateProgress = progress
            }
        }
        recognizer.onCalibrated = { [weak self] calibration in
            calibration.save()
            DispatchQueue.main.async {
                self?.calibrating = false
                self?.calibrationDone = true
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
        recognizer.onEvent = { [weak self] event in self?.handle(event) }
    }

    func calibrate() {
        calibrationDone = false
        calibrating = true
        recognizer.startCalibration(seconds: 2.0)
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
            BuiltinGestureMap.action(for: .palmHold).execute()  // default: Mission Control
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
            BuiltinGestureMap.action(for: .thumbsUp).execute()  // default: play/pause
            heavyHaptic()
        case .shakaHold:
            BuiltinGestureMap.action(for: .shaka).execute()  // default: next desktop
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
    @AppStorage("handTuningPreset") private var tuningPreset = "balanced"

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
                        poseBadge
                            .padding(10)
                    }
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 8) {
                            // Typing while hand-tracking: raise the remote
                            // keyboard (dictation is the hands-free option).
                            Button {
                                KeyboardPresenter.shared.visible = true
                            } label: {
                                Image(systemName: "keyboard")
                                    .padding(8)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            NavigationLink(destination: AirPopGameView()) {
                                Image(systemName: "gamecontroller")
                                    .padding(8)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
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

                if adapter.calibrating {
                    VStack(spacing: 10) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.accentColor)
                        Text("Hold your hand open")
                            .font(.headline)
                        Text("Fingers spread, palm to the camera — measuring…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        ProgressView()
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
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
        .onChange(of: tuningPreset) { _, _ in pushConfig() }
        .onChange(of: adapter.calibrationDone) { _, done in
            // Re-push so the freshly measured calibration takes effect at once.
            if done { pushConfig() }
        }
    }

    /// Locked pose + a ring that fills while another pose builds evidence.
    /// Seeing *why* the pose isn't switching is what makes the lock learnable.
    private var poseBadge: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: adapter.candidateProgress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: adapter.pose == .none ? "hand.raised.slash" : "hand.raised.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(width: 30, height: 30)
            .animation(.linear(duration: 0.1), value: adapter.candidateProgress)

            VStack(alignment: .leading, spacing: 1) {
                Text(adapter.pinching ? "Pinch — button down" : adapter.pose.rawValue)
                    .font(.footnote.weight(.semibold))
                if adapter.candidateProgress > 0, adapter.candidatePose != .none {
                    Text("→ \(adapter.candidatePose.rawValue)")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                } else if adapter.pose != .none {
                    Text("locked")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var gestureSheet: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Gesture lock", selection: $tuningPreset) {
                        Text("Steady").tag("steady")
                        Text("Balanced").tag("balanced")
                        Text("Quick").tag("quick")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Feel")
                } footer: {
                    Text("A gesture stays locked in until a different one is clearly and steadily held — your hand can drift without changing pose. Steady holds hardest; Quick switches soonest.")
                }

                Section {
                    Button {
                        showGestureSheet = false
                        adapter.calibrate()
                    } label: {
                        Label(HandCalibration.isCalibrated ? "Re-calibrate my hand" : "Calibrate my hand",
                              systemImage: "hand.raised.fingers.spread")
                    }
                    if HandCalibration.isCalibrated {
                        Button(role: .destructive) {
                            HandCalibration.clear()
                            pushConfig()
                        } label: {
                            Label("Use default hand sizing", systemImage: "arrow.uturn.backward")
                        }
                    }
                } header: {
                    Text("Calibration")
                } footer: {
                    Text(HandCalibration.isCalibrated
                         ? "Poses are tuned to your hand. Re-run this if recognition drifts in different lighting or at a different distance."
                         : "Two seconds with your hand open teaches AirPad your finger proportions — the single biggest fix if poses feel touchy.")
                }

                Section("Gestures") {
                    Toggle("Palm swipe → switch desktop", isOn: $palmSwipeEnabled)
                    Toggle("Two-finger V → scroll", isOn: $scrollEnabled)
                    Toggle("Fist hold → grab & drag", isOn: $fistDragEnabled)
                }
                Section("Customizable Gestures") {
                    builtinGestureRow(.palmHold, enabled: $palmHoldEnabled)
                    builtinGestureRow(.thumbsUp, enabled: $thumbsUpEnabled)
                    builtinGestureRow(.shaka, enabled: $shakaEnabled)
                }
                Section {
                    Text("Pointing and pinch-to-click are always on. Turn off any gesture that misfires, or tap a customizable one to change what it does — open an app, a shortcut, Mission Control, anything.")
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

    /// A toggle + a NavigationLink into the Gesture Studio action picker, so
    /// each built-in hold gesture's ACTION is user-remappable (e.g. shaka →
    /// Mission Control).
    private func builtinGestureRow(_ slot: BuiltinGestureSlot, enabled: Binding<Bool>) -> some View {
        HStack {
            NavigationLink {
                ActionPickerView(selection: Binding(
                    get: { BuiltinGestureMap.action(for: slot) },
                    set: { BuiltinGestureMap.set($0, for: slot) }))
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.displayName)
                    Text(BuiltinGestureMap.action(for: slot).displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("", isOn: enabled)
                .labelsHidden()
        }
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
        c.tuning = HandTuning.named(tuningPreset)
        c.calibration = HandCalibration.load()
        adapter.config = c
    }
}

#Preview {
    NavigationStack { HandMouseView() }
}
