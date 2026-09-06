//
//  HandTracker.swift — HandEngine
//
//  Camera + Vision hand-pose pipeline. Emits one observation (or nil) per
//  processed frame on its own serial queue. Depends only on AVFoundation and
//  Vision — no UIKit views, no networking — so the whole HandEngine folder can
//  be lifted into another app (a game, a kiosk, etc.) unchanged.
//

import AVFoundation
import Vision

final class HandTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Exposed so a host UI can attach an AVCaptureVideoPreviewLayer.
    let session = AVCaptureSession()

    private let output = AVCaptureVideoDataOutput()
    private let cameraQueue = DispatchQueue(label: "handengine.camera")
    private let request = VNDetectHumanHandPoseRequest()

    /// Called on the camera queue with the best hand observation for the
    /// frame, or nil when no hand was found.
    var onFrame: ((VNHumanHandPoseObservation?) -> Void)?
    /// Called on the main thread when camera permission resolves.
    var onPermission: ((Bool) -> Void)?
    /// Called on the main thread when the session starts/stops running.
    var onRunning: ((Bool) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraQueue.async { self.configureAndRun() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                DispatchQueue.main.async { self.onPermission?(granted) }
                if granted { self.cameraQueue.async { self.configureAndRun() } }
            }
        default:
            DispatchQueue.main.async { self.onPermission?(false) }
        }
    }

    func stop() {
        cameraQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            // AVCaptureVideoDataOutput retains its delegate STRONGLY, and we own
            // the output — so tracker -> output -> tracker was a cycle and the
            // tracker, its capture session, its camera input and its onFrame
            // closure were never deallocated. Every visit to Hand Mouse, Gesture
            // Studio, or AirPop leaked a whole capture session, and the leaked
            // ones went on contending for the front camera.
            self.output.setSampleBufferDelegate(nil, queue: nil)
            DispatchQueue.main.async { self.onRunning?(false) }
        }
    }

    deinit {
        output.setSampleBufferDelegate(nil, queue: nil)
        if session.isRunning { session.stopRunning() }
    }

    private func configureAndRun() {
        if session.inputs.isEmpty {
            session.beginConfiguration()
            // VGA is plenty for hand pose and keeps Vision fast enough to run
            // per-frame without falling behind.
            session.sessionPreset = .vga640x480
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)
            // Drop late frames instead of queueing them — a backlog of stale
            // frames is what makes tracking feel laggy in bursts.
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: cameraQueue)
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            request.maximumHandCount = 1
        }
        // Re-arm every time: stop() clears the delegate to break the retain
        // cycle, and the configuration block above runs only on first setup, so
        // a stop/start round trip would otherwise deliver no frames at all.
        output.setSampleBufferDelegate(self, queue: cameraQueue)
        guard !session.isRunning else { return }
        session.startRunning()
        DispatchQueue.main.async { self.onRunning?(true) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // `request` is reused across frames, so emitting its results after a
            // failed perform re-delivered the PREVIOUS frame's observation as if
            // it were fresh — a phantom hand that kept the pose latched.
            onFrame?(nil)
            return
        }
        onFrame?(request.results?.first)
    }
}
