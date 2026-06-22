import SwiftUI
import UIKit

struct TrackpadGestureBridge: UIViewRepresentable {
    var pointerSensitivity: Double
    var naturalScroll: Bool
    var hapticsEnabled: Bool

    func makeUIView(context: Context) -> GestureHostView {
        let v = GestureHostView()
        v.configure(pointerSensitivity: pointerSensitivity, naturalScroll: naturalScroll, hapticsEnabled: hapticsEnabled)
        return v
    }

    func updateUIView(_ uiView: GestureHostView, context: Context) {
        uiView.configure(pointerSensitivity: pointerSensitivity, naturalScroll: naturalScroll, hapticsEnabled: hapticsEnabled)
    }
}

final class GestureHostView: UIView, UIGestureRecognizerDelegate {
    private var pointerSensitivity: CGFloat = 1.0
    private var naturalScroll: Bool = true
    private var hapticsEnabled: Bool = true

    private var dragLocked = false
    private var lastPanTranslation: CGPoint = .zero
    private var lastTwoPanTranslation: CGPoint = .zero

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

    func configure(pointerSensitivity: Double, naturalScroll: Bool, hapticsEnabled: Bool) {
        self.pointerSensitivity = CGFloat(pointerSensitivity)
        self.naturalScroll = naturalScroll
        self.hapticsEnabled = hapticsEnabled
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        if gestureRecognizers == nil || gestureRecognizers?.isEmpty == true {
            addGestureRecognizer(onePan)
            addGestureRecognizer(twoPan)
            addGestureRecognizer(threePan)
            addGestureRecognizer(oneTap)
            addGestureRecognizer(oneDoubleTap)
            addGestureRecognizer(twoTap)
            oneTap.require(toFail: oneDoubleTap)
        }
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
        case .ended, .cancelled, .failed:
            lastTwoPanTranslation = .zero
        default: break
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

