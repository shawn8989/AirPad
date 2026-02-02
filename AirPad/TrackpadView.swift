//
//  TrackpadView.swift
//  AirPad
//
//  A SwiftUI trackpad surface mapping gestures to network packets.
//

import SwiftUI

struct TrackpadView: View {
    @State private var lastDragLocation: CGPoint?
    @State private var twoFinger = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                Text(twoFinger ? "Scroll" : "Trackpad")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(in: geo))
            .simultaneousGesture(twoFingerDragGesture())
            .gesture(tapGesture())
        }
    }

    private func dragGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if twoFinger {
                    let dx = value.translation.width - (lastDragLocation?.x ?? 0)
                    let dy = value.translation.height - (lastDragLocation?.y ?? 0)
                    NetworkManager.shared.sendScroll(dx: dx, dy: dy)
                    lastDragLocation = CGPoint(x: value.translation.width, y: value.translation.height)
                } else {
                    let dx = value.translation.width - (lastDragLocation?.x ?? 0)
                    let dy = value.translation.height - (lastDragLocation?.y ?? 0)
                    NetworkManager.shared.sendMouseDelta(dx: dx, dy: dy)
                    lastDragLocation = CGPoint(x: value.translation.width, y: value.translation.height)
                }
            }
            .onEnded { _ in
                lastDragLocation = nil
            }
    }

    private func twoFingerDragGesture() -> some Gesture {
        // Represent two-finger mode by long press on second finger using MagnificationGesture as proxy
        MagnificationGesture(minimumScaleDelta: 0)
            .onChanged { _ in
                if twoFinger == false {
                    twoFinger = true
                    lastDragLocation = nil
                }
            }
            .onEnded { _ in
                twoFinger = false
                lastDragLocation = nil
            }
    }

    private func tapGesture() -> some Gesture {
        TapGesture(count: 1)
            .onEnded {
                NetworkManager.shared.sendClick()
            }
    }
}

#Preview {
    TrackpadView()
        .frame(height: 300)
        .padding()
}
