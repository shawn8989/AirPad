import SwiftUI
import UIKit

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
    private var lastPanTranslation: CGPoint = .zero
    private var lastTwoPanTranslation: CGPoint = .zero

    // Live finger-tracking for the on-screen touch indicator. Keyed by the
    // UITouch instance so each finger gets a stable dot for its lifetime.
    private var showTouches: Bool = true
    private var touchPoints: [ObjectIdentifier: CGPoint] = [:]

    private lazy var onePan: UIPanGestureRecognizer = {
        let g = UIPanGestureRecognizer(target: self, action: #selector(handleOnePan(_:)))
        g.minimumNumberOfTouches = 1
        g.maximumNumberOfTouches = 1
        g.delegate = self
        return g
    }()

    private lazy var twoPan: UIPanGestureRecognizer = {
        let g = UIPanGestureRecognizer(target: self, action: #selector(handleTwoPan(_:)))
        g.minimumNumberOfTouches = 2
        g.maximumNumberOfTouches = 2
        g.delegate = self
        return g
    }()

    private lazy var threePan: UIPanGestureRecognizer = {
        let g = UIPanGestureRecognizer(target: self, action: #selector(handleThreePan(_:)))
        g.minimumNumberOfTouches = 3
        g.maximumNumberOfTouches = 3
        g.delegate = self
        return g
    }()

    private lazy var fourPan: UIPanGestureRecognizer = {
        let g = UIPanGestureRecognizer(target: self, action: #selector(handleFourPan(_:)))
        g.minimumNumberOfTouches = 4
        g.maximumNumberOfTouches = 4
        g.delegate = self
        return g
    }()

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
            addGestureRecognizer(onePan)
            addGestureRecognizer(twoPan)
            addGestureRecognizer(threePan)
            addGestureRecognizer(fourPan)
            addGestureRecognizer(pinch)
            addGestureRecognizer(oneTap)
            addGestureRecognizer(oneDoubleTap)
            addGestureRecognizer(twoTap)
            oneTap.require(toFail: oneDoubleTap)
            // Keep touches flowing to this view's touchesBegan/Moved so the
            // finger indicator stays live even after a recognizer engages.
            for g in [onePan, twoPan, threePan, fourPan, oneTap, oneDoubleTap, twoTap] as [UIGestureRecognizer] {
                g.cancelsTouchesInView = false
            }
            pinch.cancelsTouchesInView = false
        }
        if !showTouches && !touchPoints.isEmpty {
            touchPoints.removeAll()
            setNeedsDisplay()
        }
    }

    // MARK: - Raw touch tracking (drives the on-screen finger indicator)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        updateTouchPoints(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        updateTouchPoints(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        for t in touches { touchPoints.removeValue(forKey: ObjectIdentifier(t)) }
        if showTouches { setNeedsDisplay() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        for t in touches { touchPoints.removeValue(forKey: ObjectIdentifier(t)) }
        if showTouches { setNeedsDisplay() }
    }

    private func updateTouchPoints(_ touches: Set<UITouch>) {
        guard showTouches else { return }
        for t in touches { touchPoints[ObjectIdentifier(t)] = t.location(in: self) }
        setNeedsDisplay()
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
    @objc private func handleOnePan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            lastPanTranslation = .zero
        case .changed:
            let t = g.translation(in: self)
            let dx = (t.x - lastPanTranslation.x) * pointerSensitivity
            let dy = (t.y - lastPanTranslation.y) * pointerSensitivity
            NetworkManager.shared.sendMouseDelta(dx: Double(dx), dy: Double(dy))
            lastPanTranslation = t
        case .ended, .cancelled, .failed:
            lastPanTranslation = .zero
        default: break
        }
    }

    @objc private func handleTwoPan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            lastTwoPanTranslation = .zero
        case .changed:
            let t = g.translation(in: self)
            var dx = (t.x - lastTwoPanTranslation.x)
            var dy = (t.y - lastTwoPanTranslation.y)
            if !naturalScroll {
                dx = -dx; dy = -dy
            }
            // Edge horizontal mapping: if start near left/right 10%, map vertical to horizontal
            let start = g.location(ofTouch: 0, in: self)
            let nearLeft = start.x < bounds.width * 0.1
            let nearRight = start.x > bounds.width * 0.9
            if nearLeft || nearRight {
                NetworkManager.shared.sendScroll(dx: Double(dy), dy: 0)
            } else {
                NetworkManager.shared.sendScroll(dx: Double(dx), dy: Double(dy))
            }
            lastTwoPanTranslation = t
        case .ended:
            // A fast horizontal two-finger flick navigates back/forward.
            let v = g.velocity(in: self)
            if abs(v.x) > 900 && abs(v.x) > abs(v.y) * 2.5 {
                NetworkManager.shared.sendNav(direction: v.x > 0 ? "back" : "forward")
                if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            }
            lastTwoPanTranslation = .zero
        case .cancelled, .failed:
            lastTwoPanTranslation = .zero
        default: break
        }
    }

    @objc private func handleFourPan(_ g: UIPanGestureRecognizer) {
        guard g.state == .ended else { return }
        let t = g.translation(in: self)
        let threshold: CGFloat = 40
        if abs(t.x) > abs(t.y) {
            if abs(t.x) >= threshold {
                NetworkManager.shared.sendSwipe(fingers: 4, direction: t.x > 0 ? "right" : "left")
                if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            }
        } else {
            if abs(t.y) >= threshold {
                NetworkManager.shared.sendSwipe(fingers: 4, direction: t.y > 0 ? "down" : "up")
                if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            }
        }
    }

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

    @objc private func handleThreePan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            break
        case .ended:
            let t = g.translation(in: self)
            let threshold: CGFloat = 40
            if abs(t.x) > abs(t.y) {
                if abs(t.x) >= threshold {
                    NetworkManager.shared.sendSwipe(fingers: 3, direction: t.x > 0 ? "right" : "left")
                    if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                }
            } else {
                if abs(t.y) >= threshold {
                    NetworkManager.shared.sendSwipe(fingers: 3, direction: t.y > 0 ? "down" : "up")
                    if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                }
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

