//
//  AirPopGameView.swift
//  AirPad
//
//  AirPop: a hand-tracking reflex game and HandEngine showcase. Bubbles
//  appear over the camera view — steer the ring with your hand and PINCH
//  while inside a bubble to pop it before it shrinks away. Golden bubbles
//  are worth extra, bombs cost you, and fast chains build a combo
//  multiplier. Entirely on-device; nothing is sent to the Mac.
//

import SwiftUI
import Combine
import Vision
import QuartzCore

final class AirPopEngine: ObservableObject {
    enum BubbleKind { case normal, golden, bomb }

    struct Bubble: Identifiable {
        let id = UUID()
        var kind: BubbleKind
        var position: CGPoint    // normalized 0...1
        var bornAt: TimeInterval
        var lifetime: TimeInterval
        var radius: CGFloat      // normalized (fraction of min dimension)
    }

    struct Burst: Identifiable {
        let id = UUID()
        var position: CGPoint
        var color: Color
    }

    struct Floater: Identifiable {
        let id = UUID()
        var text: String
        var position: CGPoint
        var color: Color
        var bornAt: TimeInterval
    }

    enum Phase { case menu, playing, gameOver }

    /// Gesture powers: every ability is triggered by one of the SAME poses
    /// Hand Mouse uses, so a round of AirPop doubles as gesture practice.
    enum Power: CaseIterable {
        case shockwave   // palm hold: pop all normal bubbles
        case freeze      // fist hold: bubbles stop aging for 3s
        case extraTime   // thumbs-up hold: +3s on the clock
        case goldenRush  // shaka hold: 5s of fast, mostly golden spawns
        case starShower  // YOUR recorded gesture (Gesture Studio): 3 golden bubbles

        var cooldown: TimeInterval {
            switch self {
            case .shockwave: return 10
            case .freeze: return 12
            case .extraTime: return 15
            case .goldenRush: return 20
            case .starShower: return 12
            }
        }

        var icon: String {
            switch self {
            case .shockwave: return "hand.raised.fill"
            case .freeze: return "snowflake"
            case .extraTime: return "hand.thumbsup.fill"
            case .goldenRush: return "sparkles"
            case .starShower: return "wand.and.stars"
            }
        }
    }

    let tracker = HandTracker()
    private let recognizer = HandGestureRecognizer()

    @Published var phase: Phase = .menu
    @Published var cursor: CGPoint?          // normalized, smoothed
    @Published var pinching = false
    @Published var bubbles: [Bubble] = []
    @Published var bursts: [Burst] = []
    @Published var floaters: [Floater] = []
    @Published var score = 0
    @Published var combo = 1
    @Published var timeLeft: Int = 45
    @Published var handVisible = false
    @Published var permissionDenied = false
    @Published var bombFlash = false
    @Published var isNewBest = false
    @Published var now: TimeInterval = CACurrentMediaTime()  // drives shrink animation
    @Published var pose: HandPose = .none
    @Published var readyAt: [Power: TimeInterval] = [:]      // cooldown ends
    @Published var frozenUntil: TimeInterval = 0
    @Published var rushUntil: TimeInterval = 0

    /// Whether the player has any Gesture Studio recordings (enables Star Shower).
    let hasCustomGestures = !GestureStore.shared.enabledTemplates.isEmpty

    @AppStorage("airpop.best") var best = 0

    private var pinchActive = false
    private var smoothed: CGPoint?
    private var lastSpawn: TimeInterval = 0
    private var endsAt: TimeInterval = 0
    private var lastPopAt: TimeInterval = 0
    private var lastTickSecond = -1
    private var poseSince: TimeInterval = 0
    private var ticker: AnyCancellable?

    init() {
        tracker.onPermission = { [weak self] granted in self?.permissionDenied = !granted }
        tracker.onFrame = { [weak self] hand in self?.process(hand) }

        // The recognizer only feeds us pose changes and Gesture Studio matches;
        // its built-in gesture EVENTS (palm swipe, scroll...) are disabled so
        // the game owns what each pose means.
        var cfg = HandGestureConfig()
        cfg.palmSwipeEnabled = false
        cfg.palmHoldEnabled = false
        cfg.scrollEnabled = false
        cfg.fistDragEnabled = false
        cfg.thumbsUpEnabled = false
        cfg.shakaEnabled = false
        cfg.customTemplates = GestureStore.shared.enabledTemplates
        recognizer.config = cfg
        recognizer.onPoseChanged = { [weak self] pose in
            DispatchQueue.main.async {
                self?.pose = pose
                self?.poseSince = CACurrentMediaTime()
            }
        }
        recognizer.onEvent = { [weak self] event in
            if case .custom = event {
                DispatchQueue.main.async { self?.firePower(.starShower) }
            }
        }
    }

    func startCamera() {
        tracker.start()
        AirPopSounds.shared.prepare()
    }

    func stopCamera() {
        tracker.stop()
        ticker?.cancel()
        AirPopSounds.shared.stop()
        phase = .menu
    }

    func startGame() {
        score = 0
        combo = 1
        bubbles = []
        bursts = []
        floaters = []
        isNewBest = false
        timeLeft = 45
        endsAt = CACurrentMediaTime() + 45
        lastSpawn = 0
        lastPopAt = 0
        lastTickSecond = -1
        readyAt = [:]
        frozenUntil = 0
        rushUntil = 0
        phase = .playing
        AirPopSounds.shared.play(.pop)
        ticker?.cancel()
        ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func tick() {
        guard phase == .playing else { return }
        let t = CACurrentMediaTime()
        now = t
        timeLeft = max(0, Int(ceil(endsAt - t)))

        // Countdown blips for the final seconds.
        if timeLeft <= 3 && timeLeft > 0 && timeLeft != lastTickSecond {
            lastTickSecond = timeLeft
            AirPopSounds.shared.play(.tick)
        }

        if t >= endsAt {
            phase = .gameOver
            if score > best {
                best = score
                isNewBest = true
                AirPopSounds.shared.play(.newBest)
            } else {
                AirPopSounds.shared.play(.gameOver)
            }
            ticker?.cancel()
            return
        }

        floaters.removeAll { t - $0.bornAt > 0.8 }

        // Held gesture powers: a pose held ~0.6s fires its ability (and will
        // fire the moment its cooldown ends if the player keeps holding).
        if pose != .none && t - poseSince > 0.6 {
            switch pose {
            case .palm: firePower(.shockwave)
            case .fist: firePower(.freeze)
            case .thumbsUp: firePower(.extraTime)
            case .shaka: firePower(.goldenRush)
            default: break
            }
        }

        // FREEZE: shift every bubble's birth time forward so lifetimes (and
        // the shrink animation) pause; spawning pauses with them.
        let frozen = t < frozenUntil
        if frozen {
            let dt = 1.0 / 30.0
            for i in bubbles.indices { bubbles[i].bornAt += dt }
            lastSpawn += dt
        }

        // MAGNET: while holding the V-sign, bubbles drift toward the cursor —
        // except bombs, which know better.
        if pose == .scroll, let target = cursor {
            for i in bubbles.indices where bubbles[i].kind != .bomb {
                bubbles[i].position.x += (target.x - bubbles[i].position.x) * 0.05
                bubbles[i].position.y += (target.y - bubbles[i].position.y) * 0.05
            }
        }

        bubbles.removeAll { t - $0.bornAt > $0.lifetime }

        // Spawn faster as the round progresses; Golden Rush doubles the pace
        // and flips the odds toward golden.
        let elapsed = 45.0 - (endsAt - t)
        let rushing = t < rushUntil
        var interval = max(0.4, 0.95 - elapsed / 60.0)
        if rushing { interval *= 0.5 }
        if !frozen && t - lastSpawn > interval && bubbles.count < (rushing ? 9 : 7) {
            lastSpawn = t
            let roll = Double.random(in: 0...1)
            let kind: BubbleKind
            if rushing {
                kind = roll < 0.55 ? .golden : .normal  // no bombs during a rush
            } else if roll < 0.10 { kind = .golden }
            else if roll < 0.26 && elapsed > 8 { kind = .bomb }  // bombs join after a warm-up
            else { kind = .normal }
            bubbles.append(Bubble(
                kind: kind,
                position: CGPoint(x: .random(in: 0.12...0.88), y: .random(in: 0.15...0.8)),
                bornAt: t,
                lifetime: kind == .golden ? .random(in: 1.4...2.0) : .random(in: 1.8...3.0),
                radius: kind == .golden ? .random(in: 0.045...0.06) : .random(in: 0.055...0.085)))
        }
    }

    // MARK: - Gesture powers

    private func firePower(_ power: Power) {
        guard phase == .playing else { return }
        if power == .starShower && !hasCustomGestures { return }
        let t = CACurrentMediaTime()
        guard t >= (readyAt[power] ?? 0) else { return }
        readyAt[power] = t + power.cooldown

        switch power {
        case .shockwave:
            let victims = bubbles.filter { $0.kind == .normal }
            guard !victims.isEmpty else { readyAt[power] = t + 1; return }  // don't waste it on nothing
            bubbles.removeAll { $0.kind == .normal }
            for v in victims { spawnBurst(at: v.position, color: .cyan) }
            score += victims.count
            addFloater("✋ POP! +\(victims.count)", at: CGPoint(x: 0.5, y: 0.42), color: .cyan)
            AirPopSounds.shared.play(.pop)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        case .freeze:
            frozenUntil = t + 3
            addFloater("✊ FREEZE", at: CGPoint(x: 0.5, y: 0.42), color: .cyan)
            AirPopSounds.shared.play(.golden)
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        case .extraTime:
            endsAt += 3
            addFloater("👍 +3s", at: CGPoint(x: 0.5, y: 0.42), color: .green)
            AirPopSounds.shared.play(.golden)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        case .goldenRush:
            rushUntil = t + 5
            addFloater("🤙 GOLDEN RUSH", at: CGPoint(x: 0.5, y: 0.42), color: .yellow)
            AirPopSounds.shared.play(.newBest)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        case .starShower:
            for _ in 0..<3 {
                bubbles.append(Bubble(
                    kind: .golden,
                    position: CGPoint(x: .random(in: 0.15...0.85), y: .random(in: 0.18...0.75)),
                    bornAt: t,
                    lifetime: 2.2,
                    radius: .random(in: 0.05...0.065)))
            }
            addFloater("⭐ STAR SHOWER", at: CGPoint(x: 0.5, y: 0.42), color: .yellow)
            AirPopSounds.shared.play(.newBest)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }

    // MARK: - Hand processing (camera queue -> main)

    private func process(_ hand: VNHumanHandPoseObservation?) {
        recognizer.process(hand)  // pose classification + Gesture Studio matching
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
        guard let index = bubbles.indices.min(by: { distanceTo(bubbles[$0], point) < distanceTo(bubbles[$1], point) }),
              distanceTo(bubbles[index], point) < bubbles[index].radius * 1.6 else { return }
        let bubble = bubbles.remove(at: index)
        let t = CACurrentMediaTime()

        switch bubble.kind {
        case .bomb:
            combo = 1
            score = max(0, score - 5)
            lastPopAt = 0
            spawnBurst(at: bubble.position, color: .red)
            addFloater("-5", at: bubble.position, color: .red)
            AirPopSounds.shared.play(.bomb)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            bombFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.bombFlash = false }

        case .normal, .golden:
            // Chain pops within 1.4s to grow the multiplier (max 5x).
            combo = (t - lastPopAt < 1.4 && lastPopAt > 0) ? min(combo + 1, 5) : 1
            lastPopAt = t
            let base = bubble.kind == .golden ? 3 : 1
            let points = base * combo
            score += points
            let color: Color = bubble.kind == .golden ? .yellow : .cyan
            spawnBurst(at: bubble.position, color: color)
            addFloater(combo > 1 ? "+\(points)  x\(combo)" : "+\(points)",
                       at: bubble.position, color: color)
            AirPopSounds.shared.play(bubble.kind == .golden ? .golden : .pop)
            UIImpactFeedbackGenerator(style: bubble.kind == .golden ? .heavy : .medium).impactOccurred()
        }
    }

    private func spawnBurst(at position: CGPoint, color: Color) {
        let burst = Burst(position: position, color: color)
        bursts.append(burst)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.bursts.removeAll { $0.id == burst.id }
        }
    }

    private func addFloater(_ text: String, at position: CGPoint, color: Color) {
        floaters.append(Floater(text: text, position: position, color: color,
                                bornAt: CACurrentMediaTime()))
    }

    private func distanceTo(_ bubble: Bubble, _ point: CGPoint) -> CGFloat {
        hypot(bubble.position.x - point.x, bubble.position.y - point.y)
    }
}

struct AirPopGameView: View {
    @StateObject private var engine = AirPopEngine()
    @AppStorage("airpop.muted") private var muted = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(session: engine.tracker.session)
                    .ignoresSafeArea()
                LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.15), .black.opacity(0.45)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                // Bomb hit: red flash over everything.
                Color.red.opacity(engine.bombFlash ? 0.35 : 0)
                    .ignoresSafeArea()
                    .animation(.easeOut(duration: 0.25), value: engine.bombFlash)
                    .allowsHitTesting(false)

                // Freeze: icy tint while time is stopped.
                Color.cyan.opacity(engine.now < engine.frozenUntil ? 0.16 : 0)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.3), value: engine.now < engine.frozenUntil)
                    .allowsHitTesting(false)

                // Bubbles
                ForEach(engine.bubbles) { bubble in
                    let d = bubble.radius * 2 * min(geo.size.width, geo.size.height)
                    BubbleView(bubble: bubble, now: engine.now)
                        .frame(width: d, height: d)
                        .position(x: bubble.position.x * geo.size.width,
                                  y: bubble.position.y * geo.size.height)
                        .transition(.scale)
                }

                // Pop particle bursts
                ForEach(engine.bursts) { burst in
                    BurstView(color: burst.color)
                        .position(x: burst.position.x * geo.size.width,
                                  y: burst.position.y * geo.size.height)
                        .allowsHitTesting(false)
                }

                // Floating score text
                ForEach(engine.floaters) { floater in
                    FloaterView(floater: floater)
                        .position(x: floater.position.x * geo.size.width,
                                  y: floater.position.y * geo.size.height - 30)
                        .allowsHitTesting(false)
                }

                // Hand cursor ring
                if let cursor = engine.cursor {
                    ZStack {
                        Circle()
                            .strokeBorder(engine.pinching ? Color.orange : Color.white, lineWidth: 4)
                        Circle()
                            .fill((engine.pinching ? Color.orange : Color.white).opacity(0.25))
                            .padding(6)
                    }
                    .frame(width: engine.pinching ? 34 : 44, height: engine.pinching ? 34 : 44)
                    .animation(.snappy(duration: 0.12), value: engine.pinching)
                    .position(x: cursor.x * geo.size.width, y: cursor.y * geo.size.height)
                    .shadow(radius: 4)
                }

                // HUD
                VStack {
                    HStack(spacing: 10) {
                        Label("\(engine.score)", systemImage: "star.fill")
                            .foregroundStyle(.yellow)
                        if engine.combo > 1 {
                            Text("x\(engine.combo)")
                                .font(.headline.bold())
                                .foregroundStyle(.orange)
                                .transition(.scale)
                        }
                        Spacer()
                        Label("\(engine.timeLeft)s", systemImage: "timer")
                            .monospacedDigit()
                            .foregroundStyle(engine.timeLeft <= 5 && engine.phase == .playing ? .red : .primary)
                        Button {
                            muted.toggle()
                            AirPopSounds.shared.muted = muted
                        } label: {
                            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        }
                    }
                    .font(.headline)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
                    .animation(.snappy(duration: 0.15), value: engine.combo)

                    // Live pose readout — the "trainer" feedback loop.
                    if engine.phase == .playing && engine.pose != .none && engine.pose != .pointer {
                        Text(engine.pose.rawValue)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .transition(.opacity)
                    }

                    Spacer()
                    if !engine.handVisible && engine.phase == .playing {
                        Text("Show your hand to the camera")
                            .font(.subheadline.weight(.semibold))
                            .padding(10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 8)
                    }
                    if engine.phase == .playing {
                        AbilityBar(engine: engine)
                            .padding(.bottom, 24)
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
                            if engine.isNewBest {
                                Text("🎉 New Best!")
                                    .font(.headline)
                                    .foregroundStyle(.yellow)
                            }
                        }
                        Text("Best: \(engine.best)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        VStack(spacing: 6) {
                            Text("Steer the ring with your hand.\nPinch inside a bubble to pop it!")
                            HStack(spacing: 14) {
                                Label("+1", systemImage: "circle.fill").foregroundStyle(.cyan)
                                Label("+3", systemImage: "star.circle.fill").foregroundStyle(.yellow)
                                Label("−5", systemImage: "flame.circle.fill").foregroundStyle(.red)
                            }
                            .font(.footnote.weight(.semibold))
                            Text("Chain pops fast for up to 5x!")
                        }
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                        // Gesture powers legend — the same poses Hand Mouse uses.
                        VStack(alignment: .leading, spacing: 5) {
                            legendRow("✋ Palm (hold)", "Shockwave — pop every blue bubble")
                            legendRow("✊ Fist (hold)", "Freeze — bubbles stop for 3s")
                            legendRow("✌️ V-sign (hold it)", "Magnet — bubbles drift to you")
                            legendRow("👍 Thumbs up", "+3 seconds")
                            legendRow("🤙 Shaka", "Golden Rush — 5s of gold")
                            if engine.hasCustomGestures {
                                legendRow("⭐ Your gesture", "Star Shower — 3 golden bubbles")
                            } else {
                                Text("Record a gesture in Gesture Studio to unlock ⭐ Star Shower!")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.caption)
                        .padding(.top, 2)
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
        .onAppear {
            AirPopSounds.shared.muted = muted
            engine.startCamera()
        }
        .onDisappear { engine.stopCamera() }
    }

    private func legendRow(_ gesture: String, _ effect: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(gesture).frame(width: 128, alignment: .leading)
            Text(effect).foregroundStyle(.secondary)
        }
    }
}

/// Bottom HUD row: one chip per gesture power — lit when ready, dimmed with a
/// countdown while cooling down, pulsing while its effect is active.
private struct AbilityBar: View {
    @ObservedObject var engine: AirPopEngine

    var body: some View {
        HStack(spacing: 14) {
            chip(.shockwave, active: false)
            chip(.freeze, active: engine.now < engine.frozenUntil)
            chip(.extraTime, active: false)
            chip(.goldenRush, active: engine.now < engine.rushUntil)
            if engine.hasCustomGestures {
                chip(.starShower, active: false)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func chip(_ power: AirPopEngine.Power, active: Bool) -> some View {
        let remaining = max(0, (engine.readyAt[power] ?? 0) - engine.now)
        return ZStack {
            Image(systemName: power.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(active ? .yellow : (remaining > 0 ? .gray : .white))
                .opacity(remaining > 0 ? 0.45 : 1)
            if remaining > 0 {
                Text("\(Int(ceil(remaining)))")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .offset(y: 1)
            }
        }
        .frame(width: 30, height: 30)
        .scaleEffect(active ? 1.2 : 1)
        .animation(.snappy(duration: 0.2), value: active)
    }
}

// MARK: - Pieces

/// A bubble with a gradient body, glass shine, and a shrink as its life runs
/// out so urgency is visible at a glance.
private struct BubbleView: View {
    let bubble: AirPopEngine.Bubble
    let now: TimeInterval

    var body: some View {
        let lifeLeft = max(0, 1 - (now - bubble.bornAt) / bubble.lifetime)
        // Full size for the first 40% of life, then shrink toward 55%.
        let shrink = lifeLeft > 0.6 ? 1.0 : 0.55 + 0.45 * (lifeLeft / 0.6)

        ZStack {
            Circle().fill(gradient)
            Circle().strokeBorder(border, lineWidth: 3)
            // Glass highlight
            Circle()
                .fill(.white.opacity(0.55))
                .frame(width: 12, height: 12)
                .offset(x: -8, y: -10)
                .blur(radius: 2)
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .scaleEffect(shrink)
        .opacity(0.6 + 0.4 * lifeLeft)
    }

    private var gradient: RadialGradient {
        let colors: [Color]
        switch bubble.kind {
        case .normal: colors = [.cyan.opacity(0.65), .blue.opacity(0.35)]
        case .golden: colors = [.yellow.opacity(0.85), .orange.opacity(0.45)]
        case .bomb:   colors = [.red.opacity(0.75), .black.opacity(0.5)]
        }
        return RadialGradient(colors: colors, center: .init(x: 0.35, y: 0.3),
                              startRadius: 2, endRadius: 46)
    }

    private var border: Color {
        switch bubble.kind {
        case .normal: return .cyan
        case .golden: return .yellow
        case .bomb:   return .red
        }
    }

    private var icon: String? {
        switch bubble.kind {
        case .normal: return nil
        case .golden: return "star.fill"
        case .bomb:   return "flame.fill"
        }
    }
}

/// Eight particles flying outward and fading — the pop's confetti.
private struct BurstView: View {
    let color: Color
    @State private var fired = false

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) / 8 * 2 * .pi
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .offset(x: fired ? cos(angle) * 46 : 0,
                            y: fired ? sin(angle) * 46 : 0)
                    .opacity(fired ? 0 : 1)
                    .scaleEffect(fired ? 0.4 : 1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { fired = true }
        }
    }
}

/// "+3 x2" text that rises and fades.
private struct FloaterView: View {
    let floater: AirPopEngine.Floater
    @State private var risen = false

    var body: some View {
        Text(floater.text)
            .font(.headline.bold())
            .foregroundStyle(floater.color)
            .shadow(color: .black.opacity(0.6), radius: 2)
            .offset(y: risen ? -34 : 0)
            .opacity(risen ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.75)) { risen = true }
            }
    }
}

#Preview {
    NavigationStack { AirPopGameView() }
}
