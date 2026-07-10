//
//  AirPopGameView.swift
//  AirPad
//
//  AirPop: a hand-tracking reflex game and HandEngine showcase. Bubbles
//  appear over the camera view — steer the ring with your hand and PINCH
//  while inside a bubble to pop it before it fades. Entirely on-device;
//  nothing is sent to the Mac.
//

import SwiftUI
import Combine
import Vision
import QuartzCore

final class AirPopEngine: ObservableObject {
    struct Bubble: Identifiable {
        let id = UUID()
        var position: CGPoint    // normalized 0...1
        var bornAt: TimeInterval
        var lifetime: TimeInterval
        var radius: CGFloat      // normalized (fraction of min dimension)
    }

    enum Phase { case menu, playing, gameOver }

    let tracker = HandTracker()

    @Published var phase: Phase = .menu
    @Published var cursor: CGPoint?          // normalized, smoothed
    @Published var pinching = false
    @Published var bubbles: [Bubble] = []
    @Published var score = 0
    @Published var timeLeft: Int = 45
    @Published var handVisible = false
    @Published var permissionDenied = false

    @AppStorage("airpop.best") var best = 0

    private var pinchActive = false
    private var smoothed: CGPoint?
    private var lastSpawn: TimeInterval = 0
    private var endsAt: TimeInterval = 0
    private var ticker: AnyCancellable?

    init() {
        tracker.onPermission = { [weak self] granted in self?.permissionDenied = !granted }
        tracker.onFrame = { [weak self] hand in self?.process(hand) }
    }

    func startCamera() { tracker.start() }
    func stopCamera() {
        tracker.stop()
        ticker?.cancel()
        phase = .menu
    }

    func startGame() {
        score = 0
        bubbles = []
        timeLeft = 45
        endsAt = CACurrentMediaTime() + 45
        lastSpawn = 0
        phase = .playing
        ticker?.cancel()
        ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func tick() {
        guard phase == .playing else { return }
        let now = CACurrentMediaTime()
        timeLeft = max(0, Int(ceil(endsAt - now)))
        if now >= endsAt {
            phase = .gameOver
            best = max(best, score)
            ticker?.cancel()
            return
        }
        // Expire old bubbles.
        bubbles.removeAll { now - $0.bornAt > $0.lifetime }
        // Spawn faster as the round progresses.
        let elapsed = 45.0 - (endsAt - now)
        let interval = max(0.45, 1.0 - elapsed / 60.0)
        if now - lastSpawn > interval && bubbles.count < 6 {
            lastSpawn = now
            bubbles.append(Bubble(
                position: CGPoint(x: .random(in: 0.12...0.88), y: .random(in: 0.15...0.8)),
                bornAt: now,
                lifetime: .random(in: 1.8...3.0),
                radius: .random(in: 0.055...0.085)))
        }
    }

    // MARK: - Hand processing (camera queue -> main)

    private func process(_ hand: VNHumanHandPoseObservation?) {
        guard let hand,
              let wrist = try? hand.recognizedPoint(.wrist), wrist.confidence > 0.2,
              let midMCP = try? hand.recognizedPoint(.middleMCP), midMCP.confidence > 0.3 else {
            DispatchQueue.main.async {
                self.handVisible = false
                self.cursor = nil
                self.smoothed = nil
            }
            return
        }
        let scale = hypot(midMCP.location.x - wrist.location.x, midMCP.location.y - wrist.location.y)
        guard scale > 0.02 else { return }

        // Knuckle-average anchor mapped to screen space (portrait, mirrored).
        var sum = CGPoint.zero
        var weight: CGFloat = 0
        for joint in [VNHumanHandPoseObservation.JointName.indexMCP, .middleMCP, .ringMCP, .littleMCP] {
            guard let p = try? hand.recognizedPoint(joint), p.confidence > 0.5 else { continue }
            sum.x += p.location.x * CGFloat(p.confidence)
            sum.y += p.location.y * CGFloat(p.confidence)
            weight += CGFloat(p.confidence)
        }
        guard weight > 0 else { return }
        let anchor = CGPoint(x: sum.x / weight, y: sum.y / weight)
        let mapped = CGPoint(x: 1 - anchor.y, y: anchor.x)

        // Hand-size-normalized pinch with hysteresis.
        var pinchNow = pinchActive
        if let index = try? hand.recognizedPoint(.indexTip), index.confidence > 0.35,
           let thumb = try? hand.recognizedPoint(.thumbTip), thumb.confidence > 0.35 {
            let d = hypot(index.location.x - thumb.location.x, index.location.y - thumb.location.y) / scale
            if !pinchActive && d < 0.35 { pinchNow = true }
            if pinchActive && d > 0.55 { pinchNow = false }
        }
        let began = pinchNow && !pinchActive
        pinchActive = pinchNow

        DispatchQueue.main.async {
            self.handVisible = true
            let alpha: CGFloat = 0.4
            let s = self.smoothed.map {
                CGPoint(x: $0.x + (mapped.x - $0.x) * alpha, y: $0.y + (mapped.y - $0.y) * alpha)
            } ?? mapped
            self.smoothed = s
            self.cursor = s
            self.pinching = pinchNow
            if began { self.tryPop(at: s) }
        }
    }

    private func tryPop(at point: CGPoint) {
        guard phase == .playing else { return }
        // Generous hit test: pop the nearest bubble within 1.6x its radius.
        if let index = bubbles.indices.min(by: { distanceTo(bubbles[$0], point) < distanceTo(bubbles[$1], point) }),
           distanceTo(bubbles[index], point) < bubbles[index].radius * 1.6 {
            bubbles.remove(at: index)
            score += 1
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func distanceTo(_ bubble: Bubble, _ point: CGPoint) -> CGFloat {
        hypot(bubble.position.x - point.x, bubble.position.y - point.y)
    }
}

struct AirPopGameView: View {
    @StateObject private var engine = AirPopEngine()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(session: engine.tracker.session)
                    .ignoresSafeArea()
                Color.black.opacity(0.25).ignoresSafeArea()

                // Bubbles
                ForEach(engine.bubbles) { bubble in
                    let r = bubble.radius * min(geo.size.width, geo.size.height)
                    Circle()
                        .fill(Color.accentColor.opacity(0.35))
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 3))
                        .frame(width: r * 2, height: r * 2)
                        .position(x: bubble.position.x * geo.size.width,
                                  y: bubble.position.y * geo.size.height)
                        .transition(.scale)
                }

                // Hand cursor ring
                if let cursor = engine.cursor {
                    Circle()
                        .strokeBorder(engine.pinching ? Color.orange : Color.white, lineWidth: 4)
                        .frame(width: 44, height: 44)
                        .position(x: cursor.x * geo.size.width, y: cursor.y * geo.size.height)
                        .shadow(radius: 4)
                }

                // HUD
                VStack {
                    HStack {
                        Label("\(engine.score)", systemImage: "star.fill")
                        Spacer()
                        Label("\(engine.timeLeft)s", systemImage: "timer")
                            .monospacedDigit()
                    }
                    .font(.headline)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
                    Spacer()
                    if !engine.handVisible && engine.phase == .playing {
                        Text("Show your hand to the camera")
                            .font(.subheadline.weight(.semibold))
                            .padding(10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 30)
                    }
                }

                // Menu / game-over overlays
                if engine.phase != .playing {
                    VStack(spacing: 14) {
                        Text(engine.phase == .menu ? "AirPop" : "Time's up!")
                            .font(.largeTitle.bold())
                        if engine.phase == .gameOver {
                            Text("Score: \(engine.score)")
                                .font(.title2.weight(.semibold))
                        }
                        Text("Best: \(engine.best)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Steer the ring with your hand.\nPinch inside a bubble to pop it!")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button {
                            engine.startGame()
                        } label: {
                            Label(engine.phase == .menu ? "Start" : "Play Again", systemImage: "play.fill")
                                .font(.headline)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)

                        if engine.permissionDenied {
                            Text("Camera access is off — enable it in Settings › AirPad.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(28)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: engine.bubbles.count)
        .navigationTitle("AirPop")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { engine.startCamera() }
        .onDisappear { engine.stopCamera() }
    }
}

#Preview {
    NavigationStack { AirPopGameView() }
}
