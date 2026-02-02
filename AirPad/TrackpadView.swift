//
//  TrackpadView.swift
//  AirPad
//
//  A SwiftUI trackpad surface mapping gestures to network packets.
//

import SwiftUI

struct TrackpadView: View {
    @AppStorage("pointerSensitivity") private var pointerSensitivity: Double = 1.0
    @AppStorage("naturalScroll") private var naturalScroll: Bool = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                Text("Trackpad")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .overlay(
                TrackpadGestureBridge(pointerSensitivity: pointerSensitivity,
                                       naturalScroll: naturalScroll,
                                       hapticsEnabled: hapticsEnabled)
                    .allowsHitTesting(true)
            )
        }
    }
}

#Preview {
    TrackpadView()
        .frame(height: 300)
        .padding()
}
