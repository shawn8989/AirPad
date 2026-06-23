import SwiftUI
import UIKit
import QuartzCore

struct TrackpadGestureBridge: UIViewRepresentable {
    var pointerSensitivity: Double
    var naturalScroll: Bool
    var hapticsEnabled: Bool
    var showTouches: Bool

    func makeUIView(context: Context) -> GestureHostView {
        let v = GestureHostView()
        v.configure(pointerSensitivity: pointerSensitivity, naturalScroll: naturalScroll, hapticsEnabled: hapticsEnabled, showTouches: showTouches)
        return v
    }

    func updateUIView(_ uiView: GestureHostView, context: Context) {
        uiView.configure(pointerSensitivity: pointerSensitivity, naturalScroll: naturalScroll, hapticsEnabled: hapticsEnabled, showTouches: showTouches)
    }
}

final class GestureHostView: UIView, UIGestureRecognizerDelegate {
    private var pointerSensitivity: CGFloat = 1.0
    private var naturalScroll: Bool = true
    private var hapticsEnabled: Bool = true

    private var dragLocked = false
    private var pinchAccum: CGFloat = 1.0

    // Live finger-tracking for the on-screen touch indicator AND for all pan
    // handling (mouse move, scroll, multi-finger swipes). touchPoints is rebuilt
    // from the authoritative event.allTouches on every callback, so a missed
    // touchesEnded can never leave a phantom finger behind.
    private var showTouches: Bool = true
    private var touchPoints: [ObjectIdentifier: CGPoint] = [:]

    // Pan/swipe state. We do ALL pan handling manually rather than with
    // UIPanGestureRecognizers: recognizer actions fire before the view's touch
    // callbacks, so a recognizer-based gate against the live finger count is
    // always one event stale and leaks cursor movement into multi-finger swipes.
    // Tracking every touch here in one place keeps a single, correctly-ordered
    // source of truth.
    private var touchStarts: [ObjectIdentifier: CGPoint] = [:]
    private var touchPrev: [ObjectIdentifier: CGPoint] = [:]
    private var gesturePeak: Int = 0
    private var gestureStartTime: TimeInterval = 0
    private var endedDisplacement: CGPoint = .zero
    private var endedCount: Int = 0
    private var tracking: Bool = false

    private lazy var pinch: UIPinchGestureRecognizer = {
        let g = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        g.delegate = self
        return g
    }()

    private lazy var oneTap: UITapGestureRecognizer = {
        let g = UITapGestureRecognizer(target: self, action: #selector(handleOneTap(_:)))
        g.numberOfTouchesRequired = 1
        g.numberOfTapsRequired = 1
        g.delegate = self
        return g
    }()

    private lazy var oneDoubleTap: UITapGestureRecognizer = {
        let g = UITapGestureRecognizer(target: self, action: #selector(handleOneDoubleTap(_:)))
        g.numberOfTouchesRequired = 1
        g.numberOfTapsRequired = 2
        g.delegate = self
        return g
    }()

    private lazy var twoTap: UITapGestureRecognizer = {
        let g = UITapGestureRecognizer(target: self, action: #selector(handleTwoTap(_:)))
        g.numberOfTouchesRequired = 2
        g.numberOfTapsRequired = 1
        g.delegate = self
        return g
    }()

    func configure(pointerSensitivity: Double, naturalScroll: Bool, hapticsEnabled: Bool, showTouches: Bool) {
        self.pointerSensitivity = CGFloat(pointerSensitivity)
        self.naturalScroll = naturalScroll
        self.hapticsEnabled = hapticsEnabled
        self.showTouches = showTouches
        isMultipleTouchEnabled = true
        isOpaque = false
        backgroundColor = .clear
        if gestureRecognizers == nil || gestureRecognizers?.isEmpty == true {
            // Only discrete gestures use recognizers now; all panning/swiping is
            // handled in touchesBegan/Moved/Ended below.
            addGestureRecognizer(pinch)
            addGestureRecognizer(oneTap)
            addGestureRecognizer(oneDoubleTap)
            addGestureRecognizer(twoTap)
            oneTap.require(toFail: oneDoubleTap)
            // Keep touches flowing to this view's touchesBegan/Moved so manual
            // pan handling keeps seeing every touch even after a recognizer engages.
            for g in [pinch, oneTap, oneDoubleTap, twoTap] as [UIGestureRecognizer] {
                g.cancelsTouchesInView = false
            }
        }
        if !showTouches && !touchPoints.isEmpty {
            touchPoints.removeAll()
            setNeedsDisplay()
        }
    }

    // MARK: - Raw touch tracking (indicator + manual multi-finger swipes)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        syncTouches(event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        syncTouches(event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        syncTouches(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        syncTouches(event)
    }

    /// Single source of truth for all panning. Rebuilds the active-touch set
    /// from the authoritative event.allTouches, drives 1-finger cursor movement
    /// and 2-finger scrolling from the live touches, accumulates per-touch
    /// displacement for 3-/4-finger swipe classification, and fires the swipe
    /// once all fingers lift. Because this runs in the view's own touch
    /// callbacks, the live finger count is never stale, so movement never leaks
    /// into a multi-finger gesture.
    private func syncTouches(_ event: UIEvent?) {
        let all = event?.allTouches ?? []
        var live: [ObjectIdentifier: CGPoint] = [:]
        for t in all {
            let id = ObjectIdentifier(t)
            let loc = t.location(in: self)
            switch t.phase {
            case .began, .moved, .stationary:
                live[id] = loc
                if touchStarts[id] == nil { touchStarts[id] = loc }
            case .ended, .cancelled:
                if let start = touchStarts[id] {
                    endedDisplacement.x += loc.x - start.x
                    endedDisplacement.y += loc.y - start.y
                    endedCount += 1
                    touchStarts[id] = nil
                }
            default:
                break
            }
        }
        // Account for any finger that vanished without an end callback so it
        // can't wedge the gesture open (the cause of the stuck-finger drift).
        for id in Array(touchStarts.keys) where live[id] == nil {
            endedCount += 1
            touchStarts[id] = nil
        }

        if !live.isEmpty && !tracking {
            tracking = true
            gestureStartTime = CACurrentMediaTime()
        }
        gesturePeak = max(gesturePeak, live.count)

        // Continuous movement: 1 finger -> cursor, 2 fingers -> scroll. Gated on
        // the peak count so once a 3rd finger has appeared nothing moves, and a
        // 2-finger gesture that drops to 1 finger doesn't suddenly jump the cursor.
        if gesturePeak == 1 && live.count == 1, let (id, loc) = live.first,
           let prev = touchPrev[id] {
            let dx = Double(loc.x - prev.x) * Double(pointerSensitivity)
            let dy = Double(loc.y - prev.y) * Double(pointerSensitivity)
            if dx != 0 || dy != 0 { NetworkManager.shared.sendMouseDelta(dx: dx, dy: dy) }
        } else if gesturePeak == 2 && live.count == 2 {
            var sumX: CGFloat = 0, sumY: CGFloat = 0, n = 0
            for (id, loc) in live {
                if let prev = touchPrev[id] { sumX += loc.x - prev.x; sumY += loc.y - prev.y; n += 1 }
            }
            if n > 0 {
                var dx = sumX / CGFloat(n), dy = sumY / CGFloat(n)
                if !naturalScroll { dx = -dx; dy = -dy }
                if dx != 0 || dy != 0 { NetworkManager.shared.sendScroll(dx: Double(dx), dy: Double(dy)) }
            }
        }

        touchPrev = live
        touchPoints = live
        if showTouches { setNeedsDisplay() }

        if live.isEmpty && tracking {
            finalizeGesture()
        }
    }

    /// Classifies the completed gesture: a 3-/4-finger swipe by direction, or a
    /// fast 2-finger horizontal flick into browser back/forward.
    private func finalizeGesture() {
        let peak = gesturePeak
        let n = max(endedCount, 1)
        let avg = CGPoint(x: endedDisplacement.x / CGFloat(n),
                          y: endedDisplacement.y / CGFloat(n))
        let duration = max(CACurrentMediaTime() - gestureStartTime, 0.001)
        if peak == 3 || peak == 4 {
            let threshold: CGFloat = 40
            if abs(avg.x) > abs(avg.y) {
                if abs(avg.x) >= threshold {
                    NetworkManager.shared.sendSwipe(fingers: peak, direction: avg.x > 0 ? "right" : "left")
                    if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                }
            } else if abs(avg.y) >= threshold {
                NetworkManager.shared.sendSwipe(fingers: peak, direction: avg.y > 0 ? "down" : "up")
                if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            }
        } else if peak == 2 {
            // Fast horizontal 2-finger flick -> browser back/forward.
            let velX = avg.x / CGFloat(duration)
            if abs(velX) > 900 && abs(avg.x) > abs(avg.y) * 2.5 {
                NetworkManager.shared.sendNav(direction: velX > 0 ? "back" : "forward")
                if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            }
        }
        gesturePeak = 0
        endedDisplacement = .zero
        endedCount = 0
        tracking = false
        touchStarts.removeAll()
        touchPrev.removeAll()
    }

    // MARK: - Drawing the finger indicator
    override func draw(_ rect: CGRect) {
        guard showTouches, !touchPoints.isEmpty,
              let ctx = UIGraphicsGetCurrentContext() else { return }
        let tint = UIColor.systemBlue
        let radius: CGFloat = 34
        for point in touchPoints.values {
            let dot = CGRect(x: point.x - radius, y: point.y - radius,
                             width: radius * 2, height: radius * 2)
            ctx.setFillColor(tint.withAlphaComponent(0.25).cgColor)
            ctx.fillEllipse(in: dot)
            ctx.setStrokeColor(tint.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(3)
            ctx.strokeEllipse(in: dot)
        }
        // Finger count badge, centered.
        let count = touchPoints.count
        let label = count == 1 ? "1 finger" : "\(count) fingers"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: UIColor.systemBlue
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        let origin = CGPoint(x: (bounds.width - size.width) / 2,
                             y: max(12, bounds.height - size.height - 16))
        (label as NSString).draw(at: origin, withAttributes: attrs)
    }

    // MARK: - Handlers
    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            pinchAccum = 1.0
        case .changed:
            pinchAccum *= g.scale
            g.scale = 1.0
            // Emit a discrete zoom step each time the cumulative scale crosses a threshold.
            if pinchAccum >= 1.25 {
                NetworkManager.shared.sendPinch(zoomIn: true)
                pinchAccum = 1.0
                if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            } else if pinchAccum <= 0.8 {
                NetworkManager.shared.sendPinch(zoomIn: false)
                pinchAccum = 1.0
                if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            }
        default:
            break
        }
    }

    @objc private func handleOneTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended else { return }
        if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        NetworkManager.shared.sendClick(button: "left")
    }

    @objc private func handleOneDoubleTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended else { return }
        dragLocked.toggle()
        if hapticsEnabled { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
        if dragLocked {
            NetworkManager.shared.sendMouseDown(button: "left")
        } else {
            NetworkManager.shared.sendMouseUp(button: "left")
        }
    }

    @objc private func handleTwoTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended else { return }
        if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        NetworkManager.shared.sendClick(button: "right")
    }

    // MARK: - Delegate
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

