//
//  HandGestureRecognizer.swift — HandEngine
//
//  Pose classification + gesture state machine. Consumes hand observations
//  from HandTracker and emits semantic HandEvents; the host app decides what
//  each event does (AirPad maps them to Mac input; a game could map them to
//  anything). No UIKit, no networking.
//
//  THE POSE LATCH (the thing that makes this usable):
//  A pose, once committed, is held until a DIFFERENT pose proves itself. Three
//  gates must all pass before the latch opens —
//    1. dwell    — no change is even considered right after one commits,
//    2. evidence — the challenger must lead continuously for a span of TIME
//                  (not frames: Vision's frame rate sags under load, and
//                  frame-count thresholds silently changed meaning with it),
//    3. margin   — and lead by a clear score gap, not merely tie.
//  A wobbling or half-relaxed hand fails the margin gate, so it stays put.
//  Poses are scored continuously (0...1) rather than decided by a tree of
//  yes/no finger flags — a boolean tree has no notion of "how sure", so a
//  finger hovering on its threshold used to flip the whole pose every frame.
//
//  Other stability techniques:
//  - All distance thresholds are normalized by hand size (wrist -> middle
//    knuckle) AND by the user's own calibration, so gestures feel identical
//    near and far from the camera and across different hands.
//  - Cursor anchor = confidence-weighted average of the four knuckles, which
//    barely moves when fingers curl or pinch — clicking can't nudge the cursor.
//  - A pose change no longer resets the cursor filter. The anchor is the same
//    knuckle average in every pose, so its history stays valid; throwing it
//    away was what made the cursor lurch after each (often spurious) switch.
//

import Vision
import CoreGraphics
import QuartzCore

enum HandPose: String {
    case none = "No hand"
    case pointer = "Pointer"
    case palm = "Palm"
    case scroll = "Scroll"
    case fist = "Fist"
    case thumbsUp = "Thumbs Up"
    case shaka = "Shaka"
}

enum HandEvent {
    case move(dx: Double, dy: Double)
    case scroll(dy: Double)
    case pinchBegan          // press mouse button
    case pinchEnded          // release mouse button
    case palmSwipe(right: Bool)
    case palmHold            // Mission Control
    case fistDragBegan
    case fistDragEnded
    case thumbsUpHold        // play/pause
    case shakaHold           // next desktop
    case custom(UUID)        // user-recorded template matched (Gesture Studio)
}

struct HandGestureConfig {
    var sensitivity: Double = 1.0
    var palmSwipeEnabled = true
    var palmHoldEnabled = true
    var scrollEnabled = true
    var fistDragEnabled = true
    var thumbsUpEnabled = true
    var shakaEnabled = true
    /// Enabled user-recorded pose templates (Gesture Studio), by id.
    var customTemplates: [UUID: [Double]] = [:]
    /// How readily the latch opens.
    var tuning: HandTuning = .balanced
    /// User-facing multiplier on every lock requirement (1.0 = the preset).
    var lockStrength: Double = 1.0
    /// This user's measured finger geometry.
    var calibration: HandCalibration = .default
}

final class HandGestureRecognizer {
    var config = HandGestureConfig() {
        didSet {
            cursor.sensitivity = config.sensitivity
            cursor.configureSmoothing(minCutoff: config.tuning.minCutoff,
                                      beta: config.tuning.beta)
        }
    }
    /// Emitted on the tracker's camera queue — hosts hop threads as needed.
    var onEvent: ((HandEvent) -> Void)?
    /// Emitted on the camera queue when the LATCHED pose changes.
    var onPoseChanged: ((HandPose) -> Void)?
    /// Emitted on the camera queue as a challenger pose gains evidence:
    /// (challenger, 0...1 progress). Progress 0 means "nothing pending" — the
    /// UI draws this as a filling ring so the lock is visible, not mysterious.
    var onPoseCandidate: ((HandPose, Double) -> Void)?
    /// Fired once when a calibration capture completes.
    var onCalibrated: ((HandCalibration) -> Void)?

    private let cursor = HandCursorMapper()

    // Latch state
    private var currentPose: HandPose = .none
    private var currentScore: Double = 0
    private var candidatePose: HandPose = .none
    private var candidateSince: TimeInterval = 0
    private var poseEnterTime: TimeInterval = 0
    private var lastCandidateProgress: Double = -1
    private var lostFrames = 0

    // Pinch
    private var pinchActive = false

    // Palm gestures
    private var lastPalmX: CGFloat?
    private var palmTravel: CGFloat = 0
    private var palmStillSince: TimeInterval = 0
    private var lastGestureTime: TimeInterval = 0

    // Hold-gesture latches (fire once per pose entry)
    private var holdFired = false
    private var dragActive = false
    /// True once a one-shot gesture (thumbs-up, shaka, palm-hold) has fired in
    /// the current pose: the latch then releases almost freely so you aren't
    /// stranded in a gesture whose job is already done.
    private var oneShotFired = false

    // Custom template matching (Gesture Studio)
    private var customMatchID: UUID?
    private var customMatchSince: TimeInterval = 0
    private var lastCustomFire: TimeInterval = 0

    // Calibration capture
    private var calibrating = false
    private var calibrationSamples: [[Double]] = []
    private var calibrationEnds: TimeInterval = 0

    // MARK: - Input

    func process(_ hand: VNHumanHandPoseObservation?) {
        guard let hand else {
            handLost()
            return
        }
        guard let wrist = point(hand, .wrist, min: 0.2),
              let midMCP = point(hand, .middleMCP) else {
            handLost()
            return
        }
        lostFrames = 0
        let scale = distance(wrist, midMCP)
        guard scale > 0.02 else { return }

        if calibrating {
            collectCalibrationSample(hand, wrist: wrist, scale: scale)
            return
        }

        // Custom templates (Gesture Studio) take precedence over built-in
        // gestures: while a recorded pose matches strongly, suppress everything
        // else so the two systems can't fight.
        if matchCustomTemplates(hand) { return }

        let amounts = fingerAmounts(hand, wrist: wrist, scale: scale)
        updateLatch(with: amounts)

        // Pinch is tracked independently of the latched pose. Tying it to
        // `pointer` meant a mis-latched pose made clicking impossible; it stays
        // off only in poses where the thumb and index are curled together
        // anyway (fist) or deliberately apart (thumbs-up, shaka), where a
        // "pinch" reading would be an artifact rather than an intention.
        switch currentPose {
        case .pointer, .palm, .scroll:
            trackPinch(hand, scale: scale)
        default:
            releasePinch()
        }

        switch currentPose {
        case .pointer:
            trackMovement(hand)
        case .fist:
            trackMovement(hand)   // fist moves the cursor too (drag naturally)
            fireAfterHold(0.4, enabled: config.fistDragEnabled, oneShot: false) {
                self.dragActive = true
                self.onEvent?(.fistDragBegan)
            }
        case .palm:
            trackPalm(hand)
        case .scroll:
            trackScroll(hand)
        case .thumbsUp:
            fireAfterHold(0.5, enabled: config.thumbsUpEnabled) { self.onEvent?(.thumbsUpHold) }
        case .shaka:
            fireAfterHold(0.5, enabled: config.shakaEnabled) { self.onEvent?(.shakaHold) }
        case .none:
            // No latched pose yet (hand just appeared): still steer, so the
            // cursor never feels dead while the first pose settles.
            trackMovement(hand)
        }
    }

    func reset() {
        releasePinch()
        endDragIfNeeded()
        cursor.reset()
        currentPose = .none
        currentScore = 0
        candidatePose = .none
        candidateSince = 0
        fingerExtendedRaw.removeAll()
        lastPalmX = nil
        palmTravel = 0
        holdFired = false
        oneShotFired = false
        emitCandidate(.none, 0)
        onPoseChanged?(.none)
    }

    // MARK: - Calibration

    /// Captures the user's open hand for `seconds` and derives per-finger
    /// extension ratios from the median sample (median, not mean: one bad
    /// frame with a joint off-screen can't drag the result).
    func startCalibration(seconds: TimeInterval = 2.0) {
        calibrationSamples.removeAll()
        calibrating = true
        calibrationEnds = CACurrentMediaTime() + seconds
        releasePinch()
        endDragIfNeeded()
    }

    func cancelCalibration() {
        calibrating = false
        calibrationSamples.removeAll()
    }

    private func collectCalibrationSample(_ hand: VNHumanHandPoseObservation,
                                          wrist: CGPoint, scale: CGFloat) {
        let fingers: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
            (.indexTip, .indexPIP), (.middleTip, .middlePIP),
            (.ringTip, .ringPIP), (.littleTip, .littlePIP)
        ]
        var sample: [Double] = []
        for (tip, pip) in fingers {
            guard let t = point(hand, tip), let p = point(hand, pip) else { return }
            sample.append(Double(distance(t, wrist) / max(distance(p, wrist), 0.0001)))
        }
        guard let thumbTip = point(hand, .thumbTip), let idxMCP = point(hand, .indexMCP) else { return }
        sample.append(Double(distance(thumbTip, idxMCP) / scale))
        calibrationSamples.append(sample)

        guard CACurrentMediaTime() >= calibrationEnds else { return }
        calibrating = false
        // Need a decent number of clean frames or the capture isn't trustworthy.
        guard calibrationSamples.count >= 12 else {
            onCalibrated?(config.calibration)   // keep what we had
            return
        }
        func median(_ index: Int) -> Double {
            let values = calibrationSamples.map { $0[index] }.sorted()
            return values[values.count / 2]
        }
        let measured = HandCalibration(index: median(0), middle: median(1),
                                       ring: median(2), little: median(3),
                                       thumbOut: median(4)).sanitized()
        config.calibration = measured
        onCalibrated?(measured)
    }

    // MARK: - Classification (continuous scores)

    private func point(_ hand: VNHumanHandPoseObservation,
                       _ j: VNHumanHandPoseObservation.JointName,
                       min: Float = 0.3) -> CGPoint? {
        guard let p = try? hand.recognizedPoint(j), p.confidence > min else { return nil }
        return p.location
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Last good raw ratio per finger, so a one-frame joint dropout holds its
    /// value instead of reading as "curled".
    private var fingerExtendedRaw: [VNHumanHandPoseObservation.JointName: Double] = [:]

    /// How extended a finger is, 0 (curled) ... 1 (straight), measured against
    /// this user's calibrated extension for that finger. The soft band between
    /// the two ends is what lets poses be *scored* instead of guessed.
    private func extensionAmount(_ hand: VNHumanHandPoseObservation, wrist: CGPoint,
                                 _ tip: VNHumanHandPoseObservation.JointName,
                                 _ pip: VNHumanHandPoseObservation.JointName,
                                 reference: Double) -> Double {
        let ratio: Double
        if let t = point(hand, tip), let p = point(hand, pip) {
            ratio = Double(distance(t, wrist) / max(distance(p, wrist), 0.0001))
            fingerExtendedRaw[tip] = ratio
        } else if let last = fingerExtendedRaw[tip] {
            ratio = last
        } else {
            return 0.5   // unknown: sits between, contributing to no pose strongly
        }
        // Curled ≈ 1.0 (tip no farther than the middle joint); extended ≈ the
        // calibrated reference. Map that span onto 0...1 with a margin at each
        // end so normal wobble doesn't reach the extremes.
        let lo = 1.0 + (reference - 1.0) * 0.40
        let hi = 1.0 + (reference - 1.0) * 0.80
        return min(max((ratio - lo) / max(hi - lo, 0.01), 0), 1)
    }

    private func thumbAmount(_ hand: VNHumanHandPoseObservation, scale: CGFloat) -> Double {
        guard let tip = point(hand, .thumbTip), let idxMCP = point(hand, .indexMCP) else { return 0.5 }
        let d = Double(distance(tip, idxMCP) / scale)
        let reference = config.calibration.thumbOut
        let lo = reference * 0.55
        let hi = reference * 0.90
        return min(max((d - lo) / max(hi - lo, 0.01), 0), 1)
    }

    /// [index, middle, ring, little, thumb] extension amounts.
    private func fingerAmounts(_ hand: VNHumanHandPoseObservation,
                               wrist: CGPoint, scale: CGFloat) -> [Double] {
        let cal = config.calibration
        return [
            extensionAmount(hand, wrist: wrist, .indexTip, .indexPIP, reference: cal.index),
            extensionAmount(hand, wrist: wrist, .middleTip, .middlePIP, reference: cal.middle),
            extensionAmount(hand, wrist: wrist, .ringTip, .ringPIP, reference: cal.ring),
            extensionAmount(hand, wrist: wrist, .littleTip, .littlePIP, reference: cal.little),
            thumbAmount(hand, scale: scale)
        ]
    }

    /// Target finger amounts per pose, with per-finger weights (0 = ignore).
    /// Weighted agreement with these templates is the pose score.
    private struct PoseTemplate {
        let pose: HandPose
        let target: [Double]
        let weight: [Double]
    }

    private static let templates: [PoseTemplate] = [
        // Index out, the rest folded. Thumb ignored: it rides along differently
        // for everyone while pointing, and pinching moves it constantly.
        PoseTemplate(pose: .pointer, target: [1, 0, 0, 0, 0],
                     weight: [1.3, 1.0, 0.7, 0.7, 0]),
        PoseTemplate(pose: .palm, target: [1, 1, 1, 1, 0],
                     weight: [1.0, 1.0, 1.0, 1.0, 0]),
        PoseTemplate(pose: .scroll, target: [1, 1, 0, 0, 0],
                     weight: [1.0, 1.0, 1.2, 1.2, 0]),
        PoseTemplate(pose: .fist, target: [0, 0, 0, 0, 0],
                     weight: [1.0, 1.0, 1.0, 1.0, 0.8]),
        PoseTemplate(pose: .thumbsUp, target: [0, 0, 0, 0, 1],
                     weight: [1.0, 1.0, 1.0, 1.0, 1.6]),
        PoseTemplate(pose: .shaka, target: [0, 0, 0, 1, 1],
                     weight: [1.0, 1.0, 1.0, 1.4, 1.4])
    ]

    private func score(_ template: PoseTemplate, _ amounts: [Double]) -> Double {
        var total = 0.0, weightSum = 0.0
        for i in 0..<5 where template.weight[i] > 0 {
            total += template.weight[i] * (1 - abs(amounts[i] - template.target[i]))
            weightSum += template.weight[i]
        }
        guard weightSum > 0 else { return 0 }
        return total / weightSum
    }

    private func scores(_ amounts: [Double]) -> [(pose: HandPose, score: Double)] {
        Self.templates.map { template in
            var s = score(template, amounts)
            // Pointer is the safe default: steering the cursor is harmless,
            // firing a gesture is not. A small bias keeps ambiguous hands
            // pointing rather than guessing at a command.
            if template.pose == .pointer { s += 0.04 }
            return (template.pose, s)
        }
    }

    // MARK: - The latch

    private func updateLatch(with amounts: [Double]) {
        let now = CACurrentMediaTime()
        let ranked = scores(amounts).sorted { $0.score > $1.score }
        guard let best = ranked.first else { return }
        currentScore = ranked.first(where: { $0.pose == currentPose })?.score ?? 0

        // First pose after the hand appears: take it immediately (nothing to
        // protect yet) once it's reasonably confident.
        if currentPose == .none {
            guard best.score > 0.55 else { return }
            commit(best.pose, at: now)
            return
        }

        if best.pose == currentPose {
            if candidatePose != .none { emitCandidate(.none, 0) }
            candidatePose = .none
            return
        }

        // How hard THIS pose holds on. Steering and dragging resist drift;
        // a one-shot that has already fired lets go almost immediately, so
        // you can fire it and get straight back to pointing.
        let sticky: Double
        if oneShotFired {
            sticky = 0.35
        } else {
            sticky = HandTuning.stickiness(for: currentPose, dragging: dragActive)
                * config.lockStrength
        }
        let dwell = config.tuning.dwell * sticky
        let evidence = config.tuning.evidence * sticky
        // Cap the margin: an arbitrarily high bar could make a pose impossible
        // to leave, which is worse than a stray switch.
        let margin = min(config.tuning.margin * sticky, 0.32)

        // Gate 1: dwell — ignore everything right after a commit.
        guard now - poseEnterTime >= dwell else {
            if candidatePose != .none { emitCandidate(.none, 0) }
            candidatePose = .none
            return
        }

        // Gate 3 (checked continuously): a clear lead, not a tie.
        guard best.score - currentScore >= margin else {
            if candidatePose != .none { emitCandidate(.none, 0) }
            candidatePose = .none
            return
        }

        // Gate 2: sustained evidence, measured in seconds.
        if best.pose != candidatePose {
            candidatePose = best.pose
            candidateSince = now
        }
        let progress = min((now - candidateSince) / max(evidence, 0.05), 1)
        emitCandidate(best.pose, progress)
        if progress >= 1 {
            commit(best.pose, at: now)
        }
    }

    private func commit(_ pose: HandPose, at now: TimeInterval) {
        let leaving = currentPose
        currentPose = pose
        candidatePose = .none
        poseEnterTime = now
        holdFired = false
        oneShotFired = false
        lastPalmX = nil
        palmTravel = 0
        palmStillSince = now
        // Deliberately NOT cursor.reset(): the knuckle anchor is the same in
        // every pose, so the filter history is still valid. Dropping it here is
        // what used to make the cursor jump after each switch. A short freeze
        // is enough to swallow the hand reshaping itself.
        cursor.freeze(for: config.tuning.settleFreeze)
        if leaving == .pointer || leaving == .palm || leaving == .scroll { releasePinch() }
        if leaving == .fist { endDragIfNeeded() }
        emitCandidate(.none, 0)
        onPoseChanged?(pose)
    }

    private func emitCandidate(_ pose: HandPose, _ progress: Double) {
        // Only report meaningful movement, so the UI isn't redrawn every frame
        // (and an idle "nothing pending" state isn't re-sent forever).
        if progress == 0 && lastCandidateProgress == 0 { return }
        guard progress == 0 || abs(progress - lastCandidateProgress) > 0.02 else { return }
        lastCandidateProgress = progress
        onPoseCandidate?(pose, progress)
    }

    // MARK: - Behaviors

    /// Camera-frame -> screen-space mapping for a portrait phone with the
    /// mirrored front camera (buffer-y -> screen-x, buffer-x -> screen-y).
    private func screenPoint(_ location: CGPoint) -> CGPoint {
        CGPoint(x: 1 - location.y, y: location.x)
    }

    /// Stable anchor: confidence-weighted knuckle average. Joints below 0.5
    /// confidence are excluded so a flickering joint can't jerk the anchor.
    private func anchor(_ hand: VNHumanHandPoseObservation) -> CGPoint? {
        let joints: [VNHumanHandPoseObservation.JointName] = [.indexMCP, .middleMCP, .ringMCP, .littleMCP]
        var sum = CGPoint.zero
        var weight: CGFloat = 0
        for j in joints {
            guard let p = try? hand.recognizedPoint(j), p.confidence > 0.5 else { continue }
            let w = CGFloat(p.confidence)
            sum.x += p.location.x * w
            sum.y += p.location.y * w
            weight += w
        }
        guard weight > 0 else { return nil }
        return CGPoint(x: sum.x / weight, y: sum.y / weight)
    }

    private func trackMovement(_ hand: VNHumanHandPoseObservation) {
        guard let a = anchor(hand) else { return }
        if let (dx, dy) = cursor.update(screenPoint(a)) {
            onEvent?(.move(dx: dx, dy: dy))
        }
    }

    private func trackScroll(_ hand: VNHumanHandPoseObservation) {
        guard config.scrollEnabled, let a = anchor(hand) else { return }
        if let (_, dy) = cursor.update(screenPoint(a)) {
            onEvent?(.scroll(dy: -dy * 0.9))
        }
    }

    private func trackPinch(_ hand: VNHumanHandPoseObservation, scale: CGFloat) {
        guard let index = point(hand, .indexTip, min: 0.3),
              let thumb = point(hand, .thumbTip, min: 0.3) else { return }
        // Normalized by hand size so pinch feels the same at any distance.
        let d = distance(index, thumb) / scale
        if !pinchActive && d < 0.40 {
            pinchActive = true
            // Closing the pinch shifts the knuckles slightly — hold the cursor
            // still through the click so it can't slide off the target.
            cursor.freeze(for: 0.15)
            onEvent?(.pinchBegan)
        } else if pinchActive && d > 0.55 {
            pinchActive = false
            cursor.freeze(for: 0.12)
            onEvent?(.pinchEnded)
        }
    }

    private func trackPalm(_ hand: VNHumanHandPoseObservation) {
        // A pinch held in an open hand is a click, not a swipe — don't let the
        // travel it causes fire a desktop switch too.
        guard !pinchActive, let a = anchor(hand) else { return }
        let x = screenPoint(a).x
        let now = CACurrentMediaTime()
        defer { lastPalmX = x }
        guard let last = lastPalmX else {
            palmStillSince = now
            return
        }
        let delta = x - last
        if palmTravel.sign != delta.sign { palmTravel = 0 }
        palmTravel += delta
        if abs(delta) > 0.004 { palmStillSince = now }

        if config.palmSwipeEnabled, abs(palmTravel) > 0.22, now - lastGestureTime > 1.0 {
            lastGestureTime = now
            let right = palmTravel > 0
            palmTravel = 0
            onEvent?(.palmSwipe(right: right))
        } else if config.palmHoldEnabled, now - palmStillSince > 1.0, now - lastGestureTime > 1.5 {
            lastGestureTime = now
            oneShotFired = true
            onEvent?(.palmHold)
        }
    }

    /// Fires once per pose entry after the pose has been held `seconds`.
    /// `oneShot` gestures also unlock the latch afterwards (see oneShotFired);
    /// fist-drag is NOT one-shot — it begins a continuous action that must keep
    /// holding the pose until the user opens their hand.
    private func fireAfterHold(_ seconds: TimeInterval, enabled: Bool,
                               oneShot: Bool = true, _ action: () -> Void) {
        guard enabled, !holdFired else { return }
        if CACurrentMediaTime() - poseEnterTime >= seconds {
            holdFired = true
            if oneShot { oneShotFired = true }
            action()
        }
    }

    private func releasePinch() {
        if pinchActive {
            pinchActive = false
            onEvent?(.pinchEnded)
        }
    }

    private func endDragIfNeeded() {
        if dragActive {
            dragActive = false
            onEvent?(.fistDragEnded)
        }
    }

    /// Returns true when a user template matches (built-ins are suppressed).
    private func matchCustomTemplates(_ hand: VNHumanHandPoseObservation) -> Bool {
        guard !config.customTemplates.isEmpty,
              let features = HandPoseFeatures.vector(from: hand) else {
            customMatchID = nil
            return false
        }
        var bestID: UUID?
        var bestScore = 0.0
        for (id, template) in config.customTemplates {
            let score = HandPoseFeatures.cosineSimilarity(template, features)
            if score > bestScore {
                bestScore = score
                bestID = id
            }
        }
        guard bestScore >= 0.93, let id = bestID else {
            customMatchID = nil
            return false
        }
        let now = CACurrentMediaTime()
        if id != customMatchID {
            customMatchID = id
            customMatchSince = now
        }
        // Same time-based evidence rule as the built-in latch.
        if now - customMatchSince >= config.tuning.evidence, now - lastCustomFire > 1.0 {
            lastCustomFire = now
            customMatchSince = now
            releasePinch()
            endDragIfNeeded()
            onEvent?(.custom(id))
        }
        return true
    }

    private func handLost() {
        lostFrames += 1
        guard lostFrames == 5 else { return }
        if calibrating { cancelCalibration() }
        reset()
    }
}
