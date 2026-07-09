//
//  GestureStudioView.swift
//  AirPad — Gesture Studio
//
//  Record your own hand poses and map them to actions. Uses HandEngine's
//  HandTracker + HandTemplateRecorder; matching runs inside HandMouseView's
//  recognizer once a gesture is saved and enabled.
//

import SwiftUI

struct GestureStudioView: View {
    @ObservedObject private var store = GestureStore.shared

    var body: some View {
        List {
            Section {
                NavigationLink(destination: GestureRecorderView()) {
                    Label("Record New Gesture", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                }
            }

            Section("My Gestures") {
                if store.gestures.isEmpty {
                    Text("No custom gestures yet. Record a hand pose — a peace sign, an L, whatever you like — and map it to any action.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($store.gestures) { $gesture in
                        HStack(spacing: 12) {
                            Image(systemName: gesture.action.icon)
                                .frame(width: 26)
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(gesture.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(gesture.action.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $gesture.enabled)
                                .labelsHidden()
                        }
                    }
                    .onDelete { store.gestures.remove(atOffsets: $0) }
                }
            }

            Section {
                Text("Hold the pose steady facing the camera while recording. If a gesture misfires during normal pointing, disable it here or re-record it as a more distinctive pose.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Gesture Studio")
    }
}

/// Full recording flow: countdown → hold pose → name it → pick an action.
struct GestureRecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = GestureStore.shared

    private enum Phase: Equatable {
        case ready, countdown(Int), recording(Double), unsteady, captured
    }

    @StateObject private var camera = RecorderCamera()
    @State private var phase: Phase = .ready
    @State private var name = ""
    @State private var action: GestureAction = GestureAction.presets[0]

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                CameraPreview(session: camera.tracker.session)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(borderColor, lineWidth: 3)
                    )

                switch phase {
                case .ready:
                    instruction("Make the pose you want to record,\nthen tap Start.")
                case .countdown(let n):
                    Text("\(n)")
                        .font(.system(size: 90, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 8)
                case .recording(let progress):
                    VStack(spacing: 10) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(width: 180)
                        Text("Hold it steady…")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .shadow(radius: 6)
                    }
                case .unsteady:
                    instruction("Too much movement — hold the pose\nsteadier and try again.")
                case .captured:
                    Label("Captured!", systemImage: "checkmark.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal)

            if phase == .captured {
                VStack(spacing: 12) {
                    TextField("Gesture name (e.g. Peace Sign)", text: $name)
                        .textFieldStyle(.roundedBorder)
                    Picker("Action", selection: $action) {
                        ForEach(GestureAction.presets, id: \.self) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    Button {
                        store.gestures.append(CustomGesture(
                            name: name.isEmpty ? "My Gesture" : name,
                            vector: camera.capturedVector,
                            action: action))
                        dismiss()
                    } label: {
                        Label("Save Gesture", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
            } else {
                Button {
                    startCountdown()
                } label: {
                    Label(phase == .unsteady ? "Try Again" : "Start Recording",
                          systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled({ if case .countdown = phase { return true }
                            if case .recording = phase { return true }
                            return false }())
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .navigationTitle("Record Gesture")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onReceive(camera.$recorderUpdate) { update in
            guard case .recording = phase, let update else { return }
            switch update {
            case .progress(let p): phase = .recording(p)
            case .unsteady:
                phase = .unsteady
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            case .done(let vector):
                camera.capturedVector = vector
                phase = .captured
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private var borderColor: Color {
        switch phase {
        case .recording: return .red
        case .captured: return .green
        case .unsteady: return .orange
        default: return Color.secondary.opacity(0.4)
        }
    }

    private func instruction(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func startCountdown() {
        phase = .countdown(3)
        func tick(_ n: Int) {
            if n == 0 {
                camera.beginRecording()
                phase = .recording(0)
                return
            }
            phase = .countdown(n)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tick(n - 1) }
        }
        tick(3)
    }
}

/// Camera + recorder bridge for the Studio (independent of HandMouse's adapter).
final class RecorderCamera: ObservableObject {
    let tracker = HandTracker()
    private let recorder = HandTemplateRecorder()
    private var recording = false

    @Published var recorderUpdate: HandTemplateRecorder.Update?
    var capturedVector: [Double] = []

    init() {
        tracker.onFrame = { [weak self] hand in
            guard let self, self.recording else { return }
            let update = self.recorder.add(hand)
            if case .done = update { self.recording = false }
            if case .unsteady = update { self.recording = false }
            DispatchQueue.main.async { self.recorderUpdate = update }
        }
    }

    func start() { tracker.start() }
    func stop() { tracker.stop(); recording = false }

    func beginRecording() {
        recorder.reset()
        recording = true
    }
}
