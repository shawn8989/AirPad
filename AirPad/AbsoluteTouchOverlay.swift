//
//  AbsoluteTouchOverlay.swift
//  AirPad
//
//  "Tap what you see" for Live Screen: touches on the streamed image are
//  mapped to display-normalized coordinates and sent as absolute cursor
//  moves — tap to click exactly there, drag to move the pointer, long-press
//  for a right click.
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        addGestureRecognizer(longPress)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
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

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        if moveCursor(to: g.location(in: self), force: true) {
            NetworkManager.shared.sendClick(button: "right")
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
}
