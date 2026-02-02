import SwiftUI
import UIKit

struct TouchCountOverlay: UIViewRepresentable {
    typealias UIViewType = TouchCountingView

    var onChanged: (Int) -> Void
    var onEnded: () -> Void

    func makeUIView(context: Context) -> TouchCountingView {
        let v = TouchCountingView()
        v.onChanged = onChanged
        v.onEnded = onEnded
        v.isUserInteractionEnabled = true
        v.backgroundColor = .clear
        v.isExclusiveTouch = false
        return v
    }

    func updateUIView(_ uiView: TouchCountingView, context: Context) {
        uiView.onChanged = onChanged
        uiView.onEnded = onEnded
    }
}

final class TouchCountingView: UIView {
    var onChanged: ((Int) -> Void)?
    var onEnded: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isUserInteractionEnabled = true
        isExclusiveTouch = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
        isUserInteractionEnabled = true
        isExclusiveTouch = false
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Return false so that touches pass through for gestures, but we still receive them here.
        return true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        onChanged?(currentTouchCount(from: event))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        onChanged?(currentTouchCount(from: event))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        let count = currentTouchCount(from: event)
        if count == 0 { onEnded?() } else { onChanged?(count) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        onEnded?()
    }

    private func currentTouchCount(from event: UIEvent?) -> Int {
        guard let allTouches = event?.allTouches else { return 0 }
        let count = allTouches.filter { $0.view === self && ($0.phase == .began || $0.phase == .moved || $0.phase == .stationary) }.count
        return count
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Do not interfere with gestures
        return false
    }
}
