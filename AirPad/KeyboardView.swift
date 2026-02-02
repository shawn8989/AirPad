//
//  KeyboardView.swift
//  AirPad
//
//  Presents a text field to capture key input and sends key down/up events.
//

import SwiftUI

struct KeyboardView: View {
    @State private var text: String = ""
    @State private var isCmd = false
    @State private var isOpt = false
    @State private var isCtrl = false
    @State private var isShift = false
    @State private var isFn = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Type to send keys to your Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Start typing…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: text) { oldValue, newValue in
                        handleTextChange(old: oldValue, new: newValue)
                    }
                    .onSubmit { sendKey(codeFor: "\n") }

                // Modifiers
                VStack(alignment: .leading, spacing: 8) {
                    Text("Modifiers").font(.headline)
                    HStack(spacing: 8) {
                        modifierButton(title: "⌘", isOn: $isCmd, keyCode: 55)
                        modifierButton(title: "⌥", isOn: $isOpt, keyCode: 58)
                        modifierButton(title: "⌃", isOn: $isCtrl, keyCode: 59)
                        modifierButton(title: "⇧", isOn: $isShift, keyCode: 56)
                        modifierButton(title: "fn", isOn: $isFn, keyCode: 63)
                        Spacer()
                        Button("Clear") { releaseAllModifiers() }
                            .buttonStyle(.bordered)
                    }
                }

                // Special Keys
                VStack(alignment: .leading, spacing: 8) {
                    Text("Special Keys").font(.headline)
                    specialKeysGrid
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Keyboard")
            .onDisappear { releaseAllModifiers() }
        }
    }

    private func modifierButton(title: String, isOn: Binding<Bool>, keyCode: UInt16) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            if isOn.wrappedValue {
                NetworkManager.shared.sendKeyDown(keyCode: keyCode)
            } else {
                NetworkManager.shared.sendKeyUp(keyCode: keyCode)
            }
        } label: {
            Text(title)
                .frame(minWidth: 44)
        }
        .buttonStyle(.plain)
        .padding(8)
        .background(isOn.wrappedValue ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: Capsule())
    }

    private var specialKeysGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                specialKeyButton("Esc", code: 53)
                specialKeyButton("Tab", code: 48)
                specialKeyButton("Caps", code: 57)
                specialKeyButton("Return", code: 36)
            }
            HStack(spacing: 8) {
                specialKeyButton("←", code: 123)
                specialKeyButton("→", code: 124)
                specialKeyButton("↑", code: 126)
                specialKeyButton("↓", code: 125)
            }
            HStack(spacing: 8) {
                specialKeyButton("Home", code: 115)
                specialKeyButton("End", code: 119)
                specialKeyButton("PgUp", code: 116)
                specialKeyButton("PgDn", code: 121)
            }
            HStack(spacing: 8) {
                specialKeyButton("Del", code: 117) // forward delete
                specialKeyButton("Backspace", code: 51)
                specialKeyButton("Space", code: 49)
            }
        }
    }

    private func specialKeyButton(_ title: String, code: UInt16) -> some View {
        Button(title) { sendKey(code: code) }
            .buttonStyle(.plain)
            .padding(8)
            .background(.thinMaterial, in: Capsule())
    }

    private func sendKey(code: UInt16) {
        NetworkManager.shared.sendKeyDown(keyCode: code)
        NetworkManager.shared.sendKeyUp(keyCode: code)
    }

    private func releaseAllModifiers() {
        if isCmd { NetworkManager.shared.sendKeyUp(keyCode: 55); isCmd = false }
        if isOpt { NetworkManager.shared.sendKeyUp(keyCode: 58); isOpt = false }
        if isCtrl { NetworkManager.shared.sendKeyUp(keyCode: 59); isCtrl = false }
        if isShift { NetworkManager.shared.sendKeyUp(keyCode: 56); isShift = false }
        if isFn { NetworkManager.shared.sendKeyUp(keyCode: 63); isFn = false }
    }

    private func handleTextChange(old: String, new: String) {
        // Determine inserted or deleted characters and send key events.
        if new.count > old.count, let ch = new.last {
            sendKey(codeFor: String(ch))
        } else if new.count < old.count {
            // Backspace
            sendKey(codeFor: "\u{8}")
        }
    }

    private func sendKey(codeFor string: String) {
        let code = keyCode(for: string)
        NetworkManager.shared.sendKeyDown(keyCode: code)
        NetworkManager.shared.sendKeyUp(keyCode: code)
    }

    private func keyCode(for string: String) -> UInt16 {
        // Basic US keyboard mapping for letters, digits, and some special keys.
        let map: [String: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20,
            "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30,
            "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41,
            "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "\t": 48, " ": 49, "\n": 36, "\u{8}": 51,
            "`": 50
        ]
        let lower = string.lowercased()
        return map[lower] ?? 0
    }
}

#Preview {
    KeyboardView()
}
