//
//  QRScannerView.swift
//  AirPad
//
//  Camera QR scanner for instant pairing: scan the code AirBridge displays
//  on the Mac and you're paired — no approval dialog.
//

import SwiftUI
import AVFoundation

struct QRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var handled = false

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerView { code in
                    guard !handled else { return }
                    handled = true
                    if let error = NetworkManager.shared.handleScannedQR(code) {
                        errorMessage = error
                        handled = false  // allow retry
                    } else {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        dismiss()
                    }
                }
                .ignoresSafeArea()

                VStack {
                    Spacer()
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding()
                    } else {
                        Text("Point at the QR code on your Mac\n(AirBridge → Show Pairing QR)")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding()
                    }
                }
            }
            .navigationTitle("Scan to Pair")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Thin AVFoundation QR scanner. Reuses the camera permission the Hand Mouse
/// already requests.
struct QRScannerView: UIViewRepresentable {
    var onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        context.coordinator.start(on: view)
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewHostView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class PreviewHostView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "airpad.qrscanner")
        private let onCode: (String) -> Void

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func start(on view: PreviewHostView) {
            view.previewLayer.session = session
            view.previewLayer.videoGravity = .resizeAspectFill
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted, let self else { return }
                self.queue.async { self.configureAndRun() }
            }
        }

        private func configureAndRun() {
            guard session.inputs.isEmpty else {
                if !session.isRunning { session.startRunning() }
                return
            }
            session.beginConfiguration()
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
            }
            session.commitConfiguration()
            session.startRunning()
        }

        func stop() {
            queue.async { [session] in
                if session.isRunning { session.stopRunning() }
            }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let string = object.stringValue else { return }
            onCode(string)
        }
    }
}
