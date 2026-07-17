//
//  HandGestureRecognizer.swift — HandEngine
//
//  Pose classification + gesture state machine. Consumes hand observations
//  from HandTracker and emits semantic HandEvents; the host app decides what
//  each event does (AirPad maps them to Mac input; a game could map them to
//  anything). No UIKit, no networking.
//
//  Stability techniques:
//  - All distance thresholds are normalized by hand size (wrist -> middle
//    knuckle), so gestures feel identical near and far from the camera.
//  - Cursor anchor = confidence-weighted average of the four knuckles, which
//    barely moves when fingers curl or pinch — clicking can't nudge the cursor.
//  - Pose changes are debounced over consecutive frames and motion output is
//    frozen briefly after a switch, so forming a gesture doesn't twitch the
//    cursor off target.
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
}

final class HandGestureRecognizer {
    var config = HandGestureConfig() {
        didSet { cursor.sensitivity = config.sensitivity }
    }
    /// Emitted on the tracker's camera queue — hosts hop threads as needed.
    var onEvent: ((HandEvent) -> Void)?
    /// Emitted on the camera queue when the debounced pose changes.
    var onPoseChanged: ((HandPose) -> Void)?

    private let cursor = HandCursorMapper()

    // Debounce / state
    private var currentPose: HandPose = .none
    private var candidatePose: HandPose = .none
    private var candidateFrames = 0
    private var poseEnterTime: TimeInterval = 0
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

    // Custom template matching (Gesture Studio)
    private var customMatchID: UUID?
    private var customMatchFrames = 0
    private var lastCustomFire: TimeInterval = 0

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

        // Custom templates (Gesture Studio) take precedence over built-in
        // gestures: while a recorded pose matches strongly, suppress everything
        // else so the two systems can't fight.
        if matchCustomTemplates(hand) { return }

        let observed = classify(hand, wrist: wrist, scale: scale)
        debounce(observed)

        switch currentPose {
        case .pointer:
            trackMovement(hand)
            trackPinch(hand, scale: scale)
        case .fist:
            trackMovement(hand)   // fist moves the cursor too (drag naturally)
            fireAfterHold(0.4, enabled: config.fistDragEnabled) {
                self.dragActive = true
                self.onEvent?(.fistDragBegan)
            }
        case .palm:
            releasePinch()
            trackPalm(hand)
        case .scroll:
            releasePinch()
            trackScroll(hand)
        case .thumbsUp:
            releasePinch()
            fireAfterHold(0.5, enabled: config.thumbsUpEnabled) { self.onEvent?(.thumbsUpHold) }
        case .shaka:
            releasePinch()
            fireAfterHold(0.5, enabled: config.shakaEnabled) { self.onEvent?(.shakaHold) }
        case .none:
            break
        }
    }

    func reset() {
        releasePinch()
        endDragIfNeeded()
        cursor.reset()
        currentPose = .none
        candidatePose = .none
        candidateFrames = 0
        fingerExtendedState.removeAll()
        lastPalmX = nil
        palmTravel = 0
        holdFired = false
        onPoseChanged?(.none)
    }

    // MARK: - Classification

    private func point(_ hand: VNHumanHandPoseObservation,
                       _ j: VNHumanHandPoseObservation.JointName,
                       min: Float = 0.3) -> CGPoint? {
        guard let p = try? hand.recognizedPoint(j), p.confidence > min else { return nil }
        return p.location
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    // Sticky per-finger extension state. A single threshold made a slightly
    // curled hand oscillate extended/curled frame-to-frame, which flickered
    // the pose (pointer -> fist) and glitched the cursor. Hysteresis: a finger
    // becomes extended above 1.18 and only stops being extended below 1.05.
    private var fingerExtendedState: [VNHumanHandPoseObservation.JointName: Bool] = [:]

    /// A finger is extended when its tip is meaningfully farther from the
    /// wrist than its middle joint — a ratio, so hand size cancels out.
    private func extended(_ hand: VNHumanHandPoseObservation, wrist: CGPoint,
                          _ tip: VNHumanHandPoseObservation.JointName,
                          _ pip: VNHumanHandPoseObservation.JointName) -> Bool {
        guard let t = point(hand, tip), let p = point(hand, pip) else {
            return fingerExtendedState[tip] ?? false  // keep last known on a dropout
        }
        let ratio = distance(t, wrist) / max(distance(p, wrist), 0.0001)
        let was = fingerExtendedState[tip] ?? (ratio > 1.15)
        let now = was ? (ratio > 1.05) : (ratio > 1.18)
        fingerExtendedState[tip] = now
        return now
    }

    private func thumbExtended(_ hand: VNHumanHandPoseObservation, wrist: CGPoint, scale: CGFloat) -> Bool {
        // Thumb "out" = tip clearly away from the index knuckle (relative to
        // hand size), which separates thumbs-up/shaka from a closed fist.
        guard let tip = point(hand, .thumbTip), let idxMCP = point(hand, .indexMCP) else { return false }
        return distance(tip, idxMCP) > scale * 1.0
    }

    private func classify(_ hand: VNHumanHandPoseObservation, wrist: CGPoint, scale: CGFloat) -> HandPose {
        let idx = extended(hand, wrist: wrist, .indexTip, .indexPIP)
        let mid = extended(hand, wrist: wrist, .middleTip, .middlePIP)
        let ring = extended(hand, wrist: wrist, .ringTip, .ringPIP)
        let lit = extended(hand, wrist: wrist, .littleTip, .littlePIP)
        let thumb = thumbExtended(hand, wrist: wrist, scale: scale)

        if idx && mid && ring && lit { return .palm }
        if idx && mid && !ring && !lit { return .scroll }
        if !idx && !mid && !ring {
            if lit && thumb { return .shaka }
            if !lit {
                return thumb ? .thumbsUp : .fist
            }
        }
        return .pointer
    }

    private func debounce(_ observed: HandPose) {
        if observed == currentPose {
            candidateFrames = 0
            return
        }
        if observed == candidatePose {
            candidateFrames += 1
        } else {
            candidatePose = observed
            candidateFrames = 1
        }
        // Asymmetric commitment: closed-hand poses need stronger evidence
        // (~0.23s) because they're the common misreads of a pointing hand;
        // returning to pointer/palm/scroll stays fast.
        let required: Int
        switch observed {
        case .fist, .thumbsUp, .shaka: required = 7
        default: required = 4
        }
        guard candidateFrames >= required else { return }

        // Commit the pose change.
        let leaving = currentPose
        currentPose = observed
        candidateFrames = 0
        poseEnterTime = CACurrentMediaTime()
        holdFired = false
        lastPalmX = nil
        palmTravel = 0
        palmStillSince = poseEnterTime
        cursor.reset()
        cursor.freeze(for: 0.3)
        if leaving == .pointer { releasePinch() }
        if leaving == .fist { endDragIfNeeded() }
        onPoseChanged?(observed)
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
        guard let a = anchor(hand) else { return }
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
            onEvent?(.palmHold)
        }
    }

    private func fireAfterHold(_ seconds: TimeInterval, enabled: Bool, _ action: () -> Void) {
        guard enabled, !holdFired else { return }
        if CACurrentMediaTime() - poseEnterTime >= seconds {
            holdFired = true
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
            customMatchFrames = 0
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
            customMatchFrames = 0
            return false
        }
        if id == customMatchID {
            customMatchFrames += 1
        } else {
            customMatchID = id
            customMatchFrames = 1
        }
        let now = CACurrentMediaTime()
        if customMatchFrames >= 4 && now - lastCustomFire > 1.0 {
            lastCustomFire = now
            customMatchFrames = 0
            releasePinch()
            endDragIfNeeded()
            cursor.reset()
            onEvent?(.custom(id))
        }
        return true
    }

    private func handLost() {
        lostFrames += 1
        guard lostFrames == 5 else { return }
        reset()
    }
}
