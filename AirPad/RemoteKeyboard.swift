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

    /// Characters produced by Shift + a base key (US layout).
    static let shifted: [Character: UInt16] = [
        "!": 18, "@": 19, "#": 20, "$": 21, "%": 23, "^": 22, "&": 26,
        "*": 28, "(": 25, ")": 29, "_": 27, "+": 24, "{": 33, "}": 30,
        "|": 42, ":": 41, "\"": 39, "<": 43, ">": 47, "?": 44, "~": 50
    ]
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

/// App-wide keyboard presenter. Exactly ONE RemoteKeyboardInput may live in
/// the view hierarchy (hosted at the root in ContentView) — two instances
/// fight over first-responder status and dismiss each other. Every screen
/// raises the keyboard through this shared state instead of hosting its own.
final class KeyboardPresenter: ObservableObject {
    static let shared = KeyboardPresenter()
    @Published var visible = false
    let state = RemoteKeyboardState()
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
            field.resetSentinel()
            if !field.becomeFirstResponder() {
                // The window may not be ready on the exact frame the flag
                // flips (e.g. auto-popup during a screen transition) — retry.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if isVisible && !field.isFirstResponder {
                        field.resetSentinel()
                        field.becomeFirstResponder()
                    }
                }
            }
        } else if !isVisible && field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    final class ForwardingTextField: UITextField, UITextFieldDelegate {
        weak var remoteState: RemoteKeyboardState?
        var onDismissed: (() -> Void)?

        // The field always holds this sentinel. Typing grows the text past it,
        // backspace shrinks it below it — the editingChanged diff below turns
        // both into remote key events. This is the ONLY reliable capture: on
        // real devices the system keyboard inserts text through UITextField's
        // internal editing path, and a subclass insertText override is simply
        // never called (delete worked, letters didn't — that was why).
        private let sentinel = "\u{200B}"

        override init(frame: CGRect) {
            super.init(frame: frame)
            delegate = self
            alpha = 0.02  // must be "visible" to become first responder reliably
            text = sentinel
            addTarget(self, action: #selector(editingChanged), for: .editingChanged)
        }
        required init?(coder: NSCoder) { fatalError() }

        func resetSentinel() {
            text = sentinel
        }

        // iOS dictation continuously EDITS the text it inserted (rewriting
        // words as recognition refines). Resetting the sentinel mid-dictation
        // yanks that text away and kills the session after a few words — so
        // while dictating we let text accumulate untouched and flush it as one
        // type_text when dictation ends.
        private var wasDictating = false
        private var isDictating: Bool {
            textInputMode?.primaryLanguage == "dictation"
        }

        @objc private func editingChanged() {
            if isDictating {
                wasDictating = true
                scheduleDictationFlush()
                return  // hands off: dictation owns the text until it ends
            }
            if wasDictating {
                wasDictating = false
                flushDictationText()
                return
            }
            let current = text ?? ""
            defer {
                if current != sentinel { text = sentinel }
            }
            if current.isEmpty {
                remoteState?.sendKey(51)  // backspace consumed the sentinel
            } else if current.hasPrefix(sentinel), current.count > sentinel.count {
                forward(String(current.dropFirst(sentinel.count)))
            } else if current != sentinel {
                // Unexpected shape (cursor moved, autofill...): strip and forward.
                let typed = current.replacingOccurrences(of: sentinel, with: "")
                if !typed.isEmpty { forward(typed) }
            }
        }

        private func flushDictationText() {
            let dictated = (text ?? "").replacingOccurrences(of: sentinel, with: "")
            if !dictated.isEmpty {
                NetworkManager.shared.sendTypeText(dictated)
            }
            resetSentinel()
        }

        // Dictation end detection WITHOUT the UIResponder dictation hooks.
        // Overriding insertDictationResult / dictationRecordingDidEnd and
        // calling super crashed the app the moment the mic key was tapped:
        // those callbacks land while UIKit is mid-insertion, and our text
        // mutation inside them tore the dictation session's own state apart.
        // Instead we watch the text settle: once it stops changing for a
        // moment and dictation is no longer the active input mode, we flush.
        private var dictationFlushWork: DispatchWorkItem?

        private func scheduleDictationFlush() {
            dictationFlushWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                // Still in dictation mode (mic open, pausing between phrases)?
                // Check again shortly instead of cutting the session short.
                guard !self.isDictating else {
                    self.scheduleDictationFlush()
                    return
                }
                self.wasDictating = false
                self.flushDictationText()
            }
            dictationFlushWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        }

        override func resignFirstResponder() -> Bool {
            // Dismissing the keyboard mid-dictation must not swallow the text.
            dictationFlushWork?.cancel()
            if wasDictating {
                wasDictating = false
                flushDictationText()
            }
            return super.resignFirstResponder()
        }

        private func forward(_ text: String) {
            guard let state = remoteState else { return }
            if text == "\n" {
                state.sendKey(36)  // Return
                return
            }
            if let ch = text.first, text.count == 1 {
                if state.anyModifier, let code = MacKeyMap.code(for: ch) {
                    state.sendKey(code)  // e.g. ⌘C as a real key combo
                    return
                }
                // Prefer real key events over unicode type_text: they behave
                // like a physical keyboard in every app (shortcuts, games,
                // terminals) and can't be corrupted by modifier state.
                if let code = MacKeyMap.codes[ch] {
                    NetworkManager.shared.sendKeyCombo(code)
                    return
                }
                if ch.isUppercase, let code = MacKeyMap.code(for: ch) {
                    NetworkManager.shared.sendKeyCombo(code, shift: true)
                    return
                }
                if let code = MacKeyMap.shifted[ch] {
                    NetworkManager.shared.sendKeyCombo(code, shift: true)
                    return
                }
            }
            NetworkManager.shared.sendTypeText(text)  // emoji, accents, paste
        }

        // Fast path when UIKit does call these (simulator, hardware keyboards);
        // they bypass the text change, so the diff path never double-sends.
        override func insertText(_ text: String) {
            forward(text)
        }

        override func deleteBackward() {
            remoteState?.sendKey(51)  // Delete/Backspace (honors held modifiers)
        }

        // UITextField sends Return through the delegate, NOT insertText("\n").
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            remoteState?.sendKey(36)
            return false
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
