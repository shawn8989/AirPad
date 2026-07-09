//
//  HandPoseTemplate.swift — HandEngine
//
//  Custom-gesture templates: a hand pose reduced to a normalized feature
//  vector (all 21 joints, wrist-origin, hand-size-scaled) compared with
//  cosine similarity. Recording averages ~1.5s of held-pose frames and
//  rejects unsteady captures. Pure math — reusable outside AirPad.
//

import Vision
import CoreGraphics

enum HandPoseFeatures {
    static let jointOrder: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip
    ]

    /// Wrist-origin, hand-size-normalized joint coordinates (42 values), or
    /// nil when any joint is too low-confidence for a trustworthy vector.
    static func vector(from hand: VNHumanHandPoseObservation) -> [Double]? {
        guard let wrist = try? hand.recognizedPoint(.wrist), wrist.confidence > 0.2,
              let mid = try? hand.recognizedPoint(.middleMCP), mid.confidence > 0.3 else { return nil }
        let scale = hypot(mid.location.x - wrist.location.x, mid.location.y - wrist.location.y)
        guard scale > 0.02 else { return nil }
        var v: [Double] = []
        v.reserveCapacity(jointOrder.count * 2)
        for joint in jointOrder {
            guard let p = try? hand.recognizedPoint(joint), p.confidence > 0.25 else { return nil }
            v.append(Double((p.location.x - wrist.location.x) / scale))
            v.append(Double((p.location.y - wrist.location.y) / scale))
        }
        return v
    }

    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom > 0 ? dot / denom : 0
    }

    static func mean(_ vectors: [[Double]]) -> [Double] {
        guard let first = vectors.first else { return [] }
        var m = [Double](repeating: 0, count: first.count)
        for v in vectors {
            for i in 0..<m.count { m[i] += v[i] }
        }
        for i in 0..<m.count { m[i] /= Double(vectors.count) }
        return m
    }
}

/// Averages held-pose frames into a template; rejects unsteady captures.
final class HandTemplateRecorder {
    enum Update {
        case progress(Double)      // 0...1 while capturing
        case done([Double])        // final template vector
        case unsteady              // too much movement — ask user to retry
    }

    private var frames: [[Double]] = []
    private let targetFrames = 45  // ~1.5s at 30fps

    func reset() { frames.removeAll() }

    func add(_ hand: VNHumanHandPoseObservation?) -> Update {
        guard let hand, let v = HandPoseFeatures.vector(from: hand) else {
            return .progress(Double(frames.count) / Double(targetFrames))
        }
        frames.append(v)
        guard frames.count >= targetFrames else {
            return .progress(Double(frames.count) / Double(targetFrames))
        }
        let mean = HandPoseFeatures.mean(frames)
        // Average per-frame deviation from the mean, in hand-scale units.
        let avgDeviation = frames.map { frame -> Double in
            var sum = 0.0
            for i in 0..<frame.count {
                let d = frame[i] - mean[i]
                sum += d * d
            }
            return sum.squareRoot()
        }.reduce(0, +) / Double(frames.count)
        frames.removeAll()
        return avgDeviation > 0.9 ? .unsteady : .done(mean)
    }
}
