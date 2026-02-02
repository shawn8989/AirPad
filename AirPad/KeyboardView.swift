//
//  KeyboardView.swift
//  AirPad
//
//  Presents a text field to capture key input and sends key down/up events.
//

import SwiftUI

struct KeyboardView: View {
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Type to send keys to your Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Start typing…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: text) { oldValue, newValue in
                        handleTextChange(old: oldValue, new: newValue)
                    }
                    .onSubmit {
                        sendKey(codeFor: "\n")
                    }

                Spacer()
            }
            .padding()
            .navigationTitle("Keyboard")
        }
    }

    private func handleTextChange(old: String, new: String) {
        // Determine inserted or deleted characters and send key events.
        if new.count > old.count, let ch = new.last {
            sendKey(codeFor: ch)
        } else if new.count < old.count {
            // Backspace
            sendKey(codeFor: "\u{8}")
        }
    }

    private func sendKey(codeFor scalar: some StringProtocol) {
        let code = keyCode(for: String(scalar))
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
            "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, " ": 49, "\n": 36, "\u{8}": 51
        ]
        let lower = string.lowercased()
        return map[lower] ?? 0
    }
}

#Preview {
    KeyboardView()
}
