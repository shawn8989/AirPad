//
//  KeyboardModeView.swift
//  AirPad
//
//  Keyboard as a full screen of its own rather than a panel that appears
//  over whatever you happened to be looking at.
//
//  Typing on a Mac is almost never just typing: you type, click into the next
//  field, type again. The old design raised the system keyboard over the main
//  screen, which left a trackpad you could barely see and a keyboard with no
//  room, and gave you nothing to click with. Here the whole screen belongs to
//  the task — a trackpad, explicit click buttons under your thumbs, and the
//  keyboard — and `‹ Wield` in the navigation bar takes you back to the modes.
//
//  Two states, because the useful sizes are different:
//    keyboard up   — pad shrinks to the space above it; enough to click into
//                    the next field, which is the actual job
//    keyboard down — pad takes the whole screen, for reading and navigating
//                    between bursts of typing
//
//  Click is a button, not a tap on the pad. A stray tap while repositioning
//  your finger would otherwise fire a click into the document you are typing
//  in. Laptops keep physical buttons for the same reason.
//

import SwiftUI
import UIKit

struct KeyboardModeView: View {
    @ObservedObject private var keyboard = KeyboardPresenter.shared
    @ObservedObject private var network = NetworkManager.shared
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true

    var body: some View {
        VStack(spacing: 10) {
            TrackpadView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .top) {
                    if !keyboard.visible {
                        Text("Trackpad — move, scroll, and swipe as usual")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                }

            HStack(spacing: 10) {
                clickButton("Left Click", "cursorarrow.click", prominent: true) {
                    NetworkManager.shared.sendClick(button: "left")
                }
                clickButton("Right Click", "cursorarrow.rays") {
                    NetworkManager.shared.sendClick(button: "right")
                }
            }

            if !keyboard.visible {
                Button {
                    keyboard.visible = true
                } label: {
                    Label("Show Keyboard", systemImage: "keyboard")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, keyboard.visible ? 6 : 10)
        .navigationTitle("Keyboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    keyboard.visible.toggle()
                } label: {
                    Image(systemName: keyboard.visible
                          ? "keyboard.chevron.compact.down" : "keyboard")
                }
                .accessibilityLabel(keyboard.visible ? "Hide keyboard" : "Show keyboard")
            }
        }
        // Raise it on the way in — this screen exists to type — and lower it on
        // the way out so it can't outlive the screen that asked for it.
        .onAppear { keyboard.visible = true }
        .onDisappear { keyboard.visible = false }
    }

    @ViewBuilder
    private func clickButton(_ title: String, _ icon: String, prominent: Bool = false,
                             action: @escaping () -> Void) -> some View {
        let label = Label(title, systemImage: icon)
            .font(.callout.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 46)
        let tap = {
            if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            action()
        }

        // Branch rather than erase: there is no AnyButtonStyle, and the two
        // styles are different concrete types.
        if prominent {
            Button(action: tap) { label }
                .buttonStyle(.borderedProminent)
                .disabled(!network.isConnected)
        } else {
            Button(action: tap) { label }
                .buttonStyle(.bordered)
                .disabled(!network.isConnected)
        }
    }
}
