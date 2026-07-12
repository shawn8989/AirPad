//
//  GestureStudioView.swift
//  AirPad — Gesture Studio
//
//  Record your own hand poses and map them to actions. Uses HandEngine's
//  HandTracker + HandTemplateRecorder; matching runs inside HandMouseView's
//  recognizer once a gesture is saved and enabled.
//

import SwiftUI
import Combine

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
                        NavigationLink(destination: GestureEditView(gesture: $gesture)) {
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
                    NavigationLink {
                        ActionPickerView(selection: $action)
                    } label: {
                        HStack {
                            Label(action.displayName, systemImage: action.icon)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
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

/// Edit an existing gesture: rename it or point it at a different action.
struct GestureEditView: View {
    @Binding var gesture: CustomGesture

    var body: some View {
        Form {
            Section("Name") {
                TextField("Gesture name", text: $gesture.name)
            }
            Section("Action") {
                NavigationLink {
                    ActionPickerView(selection: $gesture.action)
                } label: {
                    Label(gesture.action.displayName, systemImage: gesture.action.icon)
                }
            }
            Section {
                Toggle("Enabled", isOn: $gesture.enabled)
            } footer: {
                Text("The pose itself can't be edited — record a new gesture to change it.")
            }
        }
        .navigationTitle("Edit Gesture")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Everything a gesture can do: open apps and websites, type text, and the
/// full preset catalog (navigation, media, editing, windows, screenshots).
struct ActionPickerView: View {
    @Binding var selection: GestureAction
    @Environment(\.dismiss) private var dismiss
    @State private var showAppPicker = false
    @State private var showURLEditor = false
    @State private var showTextEditor = false

    var body: some View {
        List {
            Section("Open on the Mac") {
                Button { showAppPicker = true } label: {
                    pickRow(Label("Open an App…", systemImage: "app.badge"),
                            selected: isLaunchApp)
                }
                Button { showURLEditor = true } label: {
                    pickRow(Label("Open a Website…", systemImage: "safari"),
                            selected: isOpenURL)
                }
                Button { showTextEditor = true } label: {
                    pickRow(Label("Type Text…", systemImage: "keyboard"),
                            selected: isTypeText)
                }
            }

            ForEach(GestureAction.presetGroups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.actions, id: \.self) { preset in
                        Button {
                            selection = preset
                            dismiss()
                        } label: {
                            pickRow(Label(preset.displayName, systemImage: preset.icon),
                                    selected: selection == preset)
                        }
                    }
                }
            }
        }
        .navigationTitle("Choose Action")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAppPicker) {
            NavigationStack {
                MacAppActionPicker { app in
                    selection = .launchApp(name: app.name, bundleID: app.bundleIdentifier)
                    showAppPicker = false
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showURLEditor) {
            NavigationStack {
                URLActionEditor(initial: currentURL) { name, url in
                    selection = .openURL(name: name, url: url)
                    showURLEditor = false
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showTextEditor) {
            NavigationStack {
                TypeTextActionEditor(initial: currentText) { text in
                    selection = .typeText(text)
                    showTextEditor = false
                    dismiss()
                }
            }
        }
    }

    private func pickRow(_ label: some View, selected: Bool) -> some View {
        HStack {
            label.foregroundStyle(.primary)
            Spacer()
            if selected {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
            }
        }
    }

    private var isLaunchApp: Bool { if case .launchApp = selection { return true }; return false }
    private var isOpenURL: Bool { if case .openURL = selection { return true }; return false }
    private var isTypeText: Bool { if case .typeText = selection { return true }; return false }
    private var currentURL: (String, String) {
        if case .openURL(let name, let url) = selection { return (name, url) }
        return ("", "")
    }
    private var currentText: String {
        if case .typeText(let t) = selection { return t }
        return ""
    }
}

/// Picks one of the Mac's installed apps (same list the Launcher uses).
struct MacAppActionPicker: View {
    var onPick: (MacAppInfo) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var apps: [MacAppInfo] = []
    @State private var query = ""
    @State private var failed = false

    private var filtered: [MacAppInfo] {
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if apps.isEmpty && !failed {
                ProgressView("Loading apps from your Mac…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if failed {
                ContentUnavailableView("Couldn't load apps",
                                       systemImage: "wifi.exclamationmark",
                                       description: Text("Make sure you're connected to your Mac, then try again."))
            } else {
                List(filtered) { app in
                    Button { onPick(app) } label: {
                        HStack {
                            Image(systemName: "app.dashed")
                                .foregroundStyle(Color.accentColor)
                            Text(app.name)
                            Spacer()
                            if app.isRunning {
                                Circle().fill(.green).frame(width: 8, height: 8)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .searchable(text: $query, prompt: "Search apps")
            }
        }
        .navigationTitle("Choose App")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .task {
            do {
                apps = try await NetworkManager.shared.requestInstalledApps()
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            } catch {
                failed = true
            }
        }
    }
}

/// Name + URL for an "open website" action.
struct URLActionEditor: View {
    var initial: (name: String, url: String)
    var onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""

    var body: some View {
        Form {
            Section("Website") {
                TextField("Name (e.g. YouTube)", text: $name)
                TextField("https://…", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                Button("Save") {
                    var u = url.trimmingCharacters(in: .whitespaces)
                    if !u.isEmpty && !u.contains("://") { u = "https://" + u }
                    onSave(name.isEmpty ? u : name, u)
                }
                .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Open a Website")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear {
            name = initial.name
            url = initial.url
        }
    }
}

/// Text snippet for a "type text" action.
struct TypeTextActionEditor: View {
    var initial: String
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        Form {
            Section("Text to type on the Mac") {
                TextField("e.g. your email address", text: $text, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section {
                Button("Save") { onSave(text) }
                    .disabled(text.isEmpty)
            }
        }
        .navigationTitle("Type Text")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear { text = initial }
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
