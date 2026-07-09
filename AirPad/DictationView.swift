import SwiftUI
import Speech
import AVFoundation

/// Dictate on the iPhone, type on the Mac. Speech recognition runs through
/// SFSpeechRecognizer; recognized text is reviewed on-screen and sent to the
/// Mac as a type_text message (typed wherever the Mac's cursor is).
final class DictationController: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer? = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        errorMessage = nil
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                guard status == .authorized else {
                    self.errorMessage = "Speech recognition permission is off. Enable it in Settings > AirPad."
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            self.errorMessage = "Microphone permission is off. Enable it in Settings > AirPad."
                            return
                        }
                        self.beginRecording()
                    }
                }
            }
        }
    }

    private func beginRecording() {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is unavailable right now."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || (result?.isFinal ?? false) {
                        self.stop()
                    }
                }
            }
        } catch {
            errorMessage = "Could not start recording: \(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct DictationView: View {
    @StateObject private var controller = DictationController()
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @State private var sentConfirmation = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Click where you want the text on your Mac, dictate here, review, then send.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextEditor(text: $controller.transcript)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(controller.isRecording ? Color.red : Color.clear, lineWidth: 2)
                )
                .frame(maxHeight: .infinity)
                .padding(.horizontal)

            if let error = controller.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
            }

            Button {
                controller.toggle()
                if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            } label: {
                Label(controller.isRecording ? "Stop" : "Dictate",
                      systemImage: controller.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.isRecording ? .red : .accentColor)
            .padding(.horizontal)

            HStack {
                Button {
                    NetworkManager.shared.sendTypeText(controller.transcript)
                    sentConfirmation = true
                    if hapticsEnabled { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { sentConfirmation = false }
                } label: {
                    Label(sentConfirmation ? "Sent!" : "Type on Mac", systemImage: "keyboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(controller.transcript.isEmpty)

                Button(role: .destructive) {
                    controller.transcript = ""
                } label: {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(controller.transcript.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .navigationTitle("Dictation")
        .onDisappear { controller.stop() }
    }
}

#Preview {
    NavigationStack { DictationView() }
}
