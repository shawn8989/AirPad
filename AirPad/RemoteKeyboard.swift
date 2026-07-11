//
//  RemoteKeyboard.swift
//  AirPad
//
//  The inline remote keyboard: the SYSTEM iOS keyboard (autocorrect,
//  dictation, swipe typing, every language) driven by a hidden text input,
//  plus an accessory strip docked above it with the keys iOS lacks —
//  Esc, Tab, modifier toggles (⌘⌥⌃⇧), and arrows. Characters are typed on
//  the Mac as you type; modifiers apply to the NEXT key then clear
//  (sticky-once), so ⌘ then C sends ⌘C.
//

import SwiftUI
import UIKit
import Combine

/// Mapping of common characters to macOS virtual key codes so modifier
/// combos (⌘C etc.) can be sent as real key events.
enum MacKeyMap {
    static let codes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
        "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, " ": 49, "`": 50
    ]

    static func code(for character: Character) -> UInt16? {
        codes[Character(character.lowercased())]
    }
}

/// Shared state between the hidden input and the accessory bar.
final class RemoteKeyboardState: ObservableObject {
    @Published var command = false
    @Published var option = false
    @Published var control = false
    @Published var shift = false

    var anyModifier: Bool { command || option || control || shift }

    func clearModifiers() {
        command = false; option = false; control = false; shift = false
    }

    /// Sends a key with the currently toggled modifiers, then clears them.
    func sendKey(_ keyCode: UInt16) {
        NetworkManager.shared.sendKeyCombo(keyCode,
                                           command: command, option: option,
                                           control: control, shift: shift)
        if anyModifier { clearModifiers() }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// Hidden UIKit text input that raises the system keyboard and forwards
/// everything typed to the Mac.
struct RemoteKeyboardInput: UIViewRepresentable {
    @Binding var isVisible: Bool
    @ObservedObject var state: RemoteKeyboardState

    func makeUIView(context: Context) -> ForwardingTextField {
        let field = ForwardingTextField()
        field.remoteState = state
        field.onDismissed = { isVisible = false }
        field.autocorrectionType = .no          // corrections would type ghost edits on the Mac
        field.autocapitalizationType = .none
        field.smartQuotesType = .no
        field.smartDashesType = .no

        // Accessory strip docked above the system keyboard.
        let bar = UIHostingController(rootView: RemoteKeyboardBar(state: state) {
            isVisible = false
        })
        bar.view.frame = CGRect(x: 0, y: 0, width: 0, height: 46)
        bar.view.backgroundColor = .clear
        field.inputAccessoryView = bar.view
        return field
    }

    func updateUIView(_ field: ForwardingTextField, context: Context) {
        if isVisible && !field.isFirstResponder {
            field.becomeFirstResponder()
        } else if !isVisible && field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    final class ForwardingTextField: UITextField, UITextFieldDelegate {
        weak var remoteState: RemoteKeyboardState?
        var onDismissed: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            delegate = self
            alpha = 0.02  // must be "visible" to become first responder reliably
        }
        required init?(coder: NSCoder) { fatalError() }

        // UIKeyInput forwarding: every character the system keyboard produces.
        override func insertText(_ text: String) {
            guard let state = remoteState else { return }
            if text == "\n" {
                state.sendKey(36)  // Return
                return
            }
            if state.anyModifier, text.count == 1,
               let code = MacKeyMap.code(for: text.first!) {
                state.sendKey(code)  // e.g. ⌘C as a real key combo
                return
            }
            NetworkManager.shared.sendTypeText(text)
        }

        override func deleteBackward() {
            remoteState?.sendKey(51)  // Delete/Backspace (honors held modifiers)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            onDismissed?()
        }
    }
}

/// The strip above the keyboard: Esc, Tab, modifiers, arrows, hide.
struct RemoteKeyboardBar: View {
    @ObservedObject var state: RemoteKeyboardState
    var onHide: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    key("esc") { state.sendKey(53) }
                    key("tab") { state.sendKey(48) }
                    modifier("⌘", $state.command)
                    modifier("⌥", $state.option)
                    modifier("⌃", $state.control)
                    modifier("⇧", $state.shift)
                    key("←") { state.sendKey(123) }
                    key("↓") { state.sendKey(125) }
                    key("↑") { state.sendKey(126) }
                    key("→") { state.sendKey(124) }
                }
                .padding(.horizontal, 8)
            }
            Button(action: onHide) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .frame(width: 40, height: 34)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.trailing, 8)
        }
        .frame(height: 46)
        .background(.ultraThinMaterial)
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .frame(minWidth: 40, minHeight: 34)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func modifier(_ label: String, _ isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .frame(minWidth: 40, minHeight: 34)
                .background(isOn.wrappedValue ? Color.accentColor : Color(.tertiarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(isOn.wrappedValue ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
