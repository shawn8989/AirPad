//
//  HandTuning.swift — HandEngine
//
//  Two knobs the rest of the engine reads: how eagerly a pose is allowed to
//  change (HandTuning), and what THIS user's fingers actually look like when
//  extended (HandCalibration).
//
//  Hand shape, camera distance, and lighting vary enormously between people,
//  and the old hardcoded thresholds only suited a hand shaped like the average
//  of the test set — everyone else had to hold unnaturally still to stay in one
//  pose. Calibration measures your own open hand once and scales every finger
//  threshold to it.
//

import Foundation

/// How much evidence a new pose needs before it can take over. Higher =
/// steadier (harder to knock out of the pose you're in), lower = quicker.
struct HandTuning: Equatable {
    /// No pose change is even considered for this long after one commits.
    var dwell: TimeInterval
    /// A challenger must out-score the current pose continuously for this long.
    var evidence: TimeInterval
    /// ...and by at least this much (0...1 score units).
    var margin: Double
    /// Cursor output pause after a pose commits (settling the hand).
    var settleFreeze: TimeInterval
    /// One-Euro smoothing.
    var minCutoff: Double
    var beta: Double

    static let steady = HandTuning(dwell: 0.50, evidence: 0.55, margin: 0.16,
                                   settleFreeze: 0.16, minCutoff: 0.5, beta: 12.0)
    static let balanced = HandTuning(dwell: 0.35, evidence: 0.40, margin: 0.12,
                                     settleFreeze: 0.12, minCutoff: 0.7, beta: 15.0)
    static let quick = HandTuning(dwell: 0.22, evidence: 0.26, margin: 0.09,
                                  settleFreeze: 0.08, minCutoff: 0.9, beta: 18.0)

    static func named(_ name: String) -> HandTuning {
        switch name {
        case "steady": return .steady
        case "quick": return .quick
        default: return .balanced
        }
    }
}

/// Per-user finger geometry, measured from a held open hand. Values are the
/// tip-to-wrist / middle-joint-to-wrist ratio for each finger when fully
/// extended, plus the thumb's distance from the index knuckle in hand-size
/// units. Defaults match a typical adult hand so an uncalibrated app still
/// works out of the box.
struct HandCalibration: Codable, Equatable {
    var index: Double = 1.28
    var middle: Double = 1.28
    var ring: Double = 1.26
    var little: Double = 1.22
    var thumbOut: Double = 1.15

    static let `default` = HandCalibration()
    private static let key = "handCalibration.v1"

    static func load() -> HandCalibration {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(HandCalibration.self, from: data) else {
            return .default
        }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static var isCalibrated: Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    /// Sanity bounds: a bad capture (hand half out of frame) must not make the
    /// engine unusable, so every measurement is clamped to a plausible range.
    func sanitized() -> HandCalibration {
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
        return HandCalibration(index: clamp(index, 1.12, 1.60),
                               middle: clamp(middle, 1.12, 1.60),
                               ring: clamp(ring, 1.10, 1.55),
                               little: clamp(little, 1.08, 1.50),
                               thumbOut: clamp(thumbOut, 0.80, 1.80))
    }
}
