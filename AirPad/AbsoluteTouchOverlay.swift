//
//  AbsoluteTouchOverlay.swift
//  AirPad
//
//  "Tap what you see" for Live Screen: touches on the streamed image are
//  mapped to display-normalized coordinates and sent as absolute cursor
//  moves. Tap to click, double-tap to double-click (opens files), one-finger
//  pan to move the pointer, two-finger pan to scroll, and hold to either
//  right-click (release in place) or drag (move while holding).
//

import SwiftUI
import UIKit

struct AbsoluteTouchOverlay: UIViewRepresentable {
    var isActive: Bool
    var imageSize: CGSize?
    var fill: Bool  // true when the stream is aspect-FILL, false for aspect-fit

    func makeUIView(context: Context) -> AbsoluteTouchView {
        let v = AbsoluteTouchView()
        v.configure(imageSize: imageSize, fill: fill)
        return v
    }

    func updateUIView(_ uiView: AbsoluteTouchView, context: Context) {
        uiView.configure(imageSize: imageSize, fill: fill)
        uiView.isUserInteractionEnabled = isActive
        uiView.alpha = isActive ? 1 : 0
    }
}

final class AbsoluteTouchView: UIView {
    private var imageSize: CGSize?
    private var fill = false
    private var lastMoveSent: TimeInterval = 0

    // Hold state: nil = not holding, false = holding in place (right click on
    // release), true = dragging with the left button down.
    private var holdIsDragging: Bool?
    private var holdStartPoint: CGPoint = .zero
    private var lastScrollPoint: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        // Wait out the double-tap window so a double-tap doesn't also fire two
        // singles — macOS only opens things on a genuine clickState=2 pair.
        tap.require(toFail: doubleTap)
        addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        addGestureRecognizer(longPress)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)

        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        addGestureRecognizer(scroll)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(imageSize: CGSize?, fill: Bool) {
        self.imageSize = imageSize
        self.fill = fill
    }

    // MARK: - Coordinate mapping

    /// Maps a view point to display-normalized (0...1) coordinates, accounting
    /// for the letterboxing/cropping of aspect-fit / aspect-fill rendering.
    private func normalized(_ point: CGPoint) -> CGPoint? {
        guard bounds.width > 0, bounds.height > 0,
              let image = imageSize, image.width > 0, image.height > 0 else { return nil }
        let scale = fill
            ? max(bounds.width / image.width, bounds.height / image.height)
            : min(bounds.width / image.width, bounds.height / image.height)
        let drawnSize = CGSize(width: image.width * scale, height: image.height * scale)
        let origin = CGPoint(x: (bounds.width - drawnSize.width) / 2,
                             y: (bounds.height - drawnSize.height) / 2)
        let x = (point.x - origin.x) / drawnSize.width
        let y = (point.y - origin.y) / drawnSize.height
        guard x >= -0.01, x <= 1.01, y >= -0.01, y <= 1.01 else { return nil }  // outside the image
        return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    private func moveCursor(to point: CGPoint, force: Bool = false) -> Bool {
        guard let n = normalized(point) else { return false }
        // Throttle continuous drags to ~50 Hz; taps force through.
        let now = CACurrentMediaTime()
        if !force && now - lastMoveSent < 0.02 { return true }
        lastMoveSent = now
        NetworkManager.shared.sendMouseMoveAbs(x: Double(n.x), y: Double(n.y))
        return true
    }

    // MARK: - Gestures

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended else { return }
        if moveCursor(to: g.location(in: self), force: true) {
            NetworkManager.shared.sendClick(button: "left")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended else { return }
        if moveCursor(to: g.location(in: self), force: true) {
            NetworkManager.shared.sendClick(button: "left", count: 2)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    /// Hold in place → right click on release. Hold then move → drag with the
    /// left button (move windows, select text, drag files).
    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        let point = g.location(in: self)
        switch g.state {
        case .began:
            guard moveCursor(to: point, force: true) else { return }
            holdIsDragging = false
            holdStartPoint = point
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .changed:
            guard let dragging = holdIsDragging else { return }
            if !dragging {
                let dx = point.x - holdStartPoint.x, dy = point.y - holdStartPoint.y
                guard dx * dx + dy * dy > 144 else { return }  // 12 pt of slack before committing to a drag
                holdIsDragging = true
                _ = moveCursor(to: holdStartPoint, force: true)
                NetworkManager.shared.sendMouseDown(button: "left")
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            }
            _ = moveCursor(to: point)
        case .ended, .cancelled, .failed:
            guard let dragging = holdIsDragging else { return }
            holdIsDragging = nil
            if dragging {
                _ = moveCursor(to: point, force: true)
                NetworkManager.shared.sendMouseUp(button: "left")
            } else if g.state == .ended {
                NetworkManager.shared.sendClick(button: "right")
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        default:
            break
        }
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began, .changed:
            _ = moveCursor(to: g.location(in: self))
        default:
            break
        }
    }

    @objc private func handleScroll(_ g: UIPanGestureRecognizer) {
        let point = g.location(in: self)
        switch g.state {
        case .began:
            lastScrollPoint = point
        case .changed:
            var dx = Double(point.x - lastScrollPoint.x)
            var dy = Double(point.y - lastScrollPoint.y)
            lastScrollPoint = point
            // Same setting the trackpad uses; unset means the AppStorage default (true).
            let natural = UserDefaults.standard.object(forKey: "naturalScroll") as? Bool ?? true
            if !natural { dx = -dx; dy = -dy }
            NetworkManager.shared.sendScroll(dx: dx * 2, dy: dy * 2)
        default:
            break
        }
    }
}
