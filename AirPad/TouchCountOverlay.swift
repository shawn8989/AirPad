import SwiftUI
import UIKit

struct TouchCountOverlay: UIViewRepresentable {
    typealias UIViewType = PassthroughContainerView

    var onChanged: (Int) -> Void
    var onEnded: () -> Void

    func makeUIView(context: Context) -> PassthroughContainerView {
        let v = PassthroughContainerView()
        v.installRecognizerIfNeeded(onChanged: onChanged, onEnded: onEnded)
        return v
    }

    func updateUIView(_ uiView: PassthroughContainerView, context: Context) {
        uiView.installRecognizerIfNeeded(onChanged: onChanged, onEnded: onEnded)
        uiView.touchCounter?.onChanged = onChanged
        uiView.touchCounter?.onEnded = onEnded
    }
}

final class PassthroughContainerView: UIView {
    fileprivate var touchCounter: TouchCounterGestureRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false // don't intercept touches
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        // Try installing when added to a superview
        installRecognizerIfNeeded(onChanged: touchCounter?.onChanged, onEnded: touchCounter?.onEnded)
    }

    func installRecognizerIfNeeded(onChanged: ((Int) -> Void)?, onEnded: (() -> Void)?) {
        guard let host = self.superview else { return }
        if touchCounter == nil {
            let recognizer = TouchCounterGestureRecognizer()
            recognizer.onChanged = onChanged
            recognizer.onEnded = onEnded
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.requiresExclusiveTouchType = false
            recognizer.delegate = recognizer
            host.addGestureRecognizer(recognizer)
            touchCounter = recognizer
        } else {
            touchCounter?.onChanged = onChanged
            touchCounter?.onEnded = onEnded
        }
    }
}

final class TouchCounterGestureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onChanged: ((Int) -> Void)?
    var onEnded: (() -> Void)?

    private var activeTouches: Set<UITouch> = []

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for t in touches { activeTouches.insert(t) }
        if state == .possible { state = .began } else { state = .changed }
        onChanged?(activeTouches.count)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible { state = .began } else { state = .changed }
        onChanged?(activeTouches.count)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for t in touches { activeTouches.remove(t) }
        if activeTouches.isEmpty {
            state = .ended
            onEnded?()
        } else {
            state = .changed
            onChanged?(activeTouches.count)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        activeTouches.removeAll()
        state = .cancelled
        onEnded?()
    }

    // MARK: UIGestureRecognizerDelegate
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
