//
//  HandCursorMapper.swift — HandEngine
//
//  Turns a stream of (noisy) hand anchor positions into smooth cursor deltas
//  using a One-Euro filter: heavy smoothing when the hand is nearly still
//  (kills jitter while hovering a target), light smoothing when it moves fast
//  (stays responsive). Pure math — no UI, no networking.
//

import CoreGraphics
import QuartzCore

/// One-Euro low-pass filter (Casiez et al.) for a single axis.
private struct OneEuroFilter {
    var minCutoff: Double
    var beta: Double
    var dCutoff: Double = 1.0

    private var prev: Double?
    private var prevDeriv: Double = 0

    // Explicit init: the synthesized memberwise one is private because the
    // filter-state properties are private.
    init(minCutoff: Double, beta: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    private func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    mutating func filter(_ value: Double, dt: Double) -> Double {
        guard dt > 0, let last = prev else {
            prev = value
            return value
        }
        let rawDeriv = (value - last) / dt
        let aD = alpha(cutoff: dCutoff, dt: dt)
        let deriv = prevDeriv + aD * (rawDeriv - prevDeriv)
        prevDeriv = deriv
        let cutoff = minCutoff + beta * abs(deriv)
        let a = alpha(cutoff: cutoff, dt: dt)
        let filtered = last + a * (value - last)
        prev = filtered
        return filtered
    }

    mutating func reset() {
        prev = nil
        prevDeriv = 0
    }
}

final class HandCursorMapper {
    /// Pointer speed multiplier (1.0 = default).
    var sensitivity: Double = 1.0
    /// Pixels of cursor travel per full normalized-camera-frame of hand travel.
    var pixelsPerFrame: Double = 1600

    // One-Euro tuning: positions are in normalized 0...1 units, hand velocities
    // are roughly 0...2 units/s. A low minCutoff keeps a hovering hand rock
    // steady; beta lifts the cutoff quickly once the hand actually moves.
    private var fx = OneEuroFilter(minCutoff: 0.7, beta: 15.0)
    private var fy = OneEuroFilter(minCutoff: 0.7, beta: 15.0)

    private var lastSent: CGPoint?
    private var lastTime: TimeInterval = 0
    private var freezeUntil: TimeInterval = 0

    /// Retunes the smoothing (Steady = heavier, Quick = lighter). Keeps the
    /// filter's running state so changing it mid-session can't jolt the cursor.
    func configureSmoothing(minCutoff: Double, beta: Double) {
        fx.minCutoff = minCutoff
        fx.beta = beta
        fy.minCutoff = minCutoff
        fy.beta = beta
    }

    /// Feed the next anchor position; returns a cursor delta in pixels, or nil
    /// when nothing should move (first sample, frozen, or sub-pixel).
    func update(_ anchor: CGPoint, at time: TimeInterval = CACurrentMediaTime()) -> (dx: Double, dy: Double)? {
        let dt = lastTime > 0 ? min(max(time - lastTime, 0.001), 0.25) : 1.0 / 30.0
        lastTime = time
        let p = CGPoint(x: fx.filter(Double(anchor.x), dt: dt),
                        y: fy.filter(Double(anchor.y), dt: dt))
        guard time >= freezeUntil else { lastSent = p; return nil }
        guard let last = lastSent else { lastSent = p; return nil }
        let rawDx = Double(p.x - last.x)
        let rawDy = Double(p.y - last.y)

        // Speed-adaptive gain (pointer acceleration): a slow, deliberate hand
        // gets sub-unity gain for pixel-precise targeting; a fast sweep gets
        // extra reach so the whole screen is coverable without straining.
        let speed = hypot(rawDx, rawDy) / dt          // normalized units/s
        let t = min(max((speed - 0.04) / 0.86, 0), 1)
        let gain = 0.45 + 1.05 * t * t * (3 - 2 * t)  // smoothstep 0.45...1.5

        let dx = rawDx * pixelsPerFrame * sensitivity * gain
        let dy = rawDy * pixelsPerFrame * sensitivity * gain
        guard abs(dx) >= 0.5 || abs(dy) >= 0.5 else {
            return nil  // leave lastSent so sub-pixel motion accumulates
        }
        lastSent = p
        return (dx, dy)
    }

    /// Forget position history (pose change, hand lost) so the next sample
    /// can't produce a jump.
    func reset() {
        fx.reset()
        fy.reset()
        lastSent = nil
        lastTime = 0
    }

    /// Keep tracking but suppress output briefly (hand settling into a pose).
    func freeze(for seconds: TimeInterval) {
        freezeUntil = CACurrentMediaTime() + seconds
    }
}
