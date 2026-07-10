//
//  GestureAction.swift
//  AirPad — Gesture Studio
//
//  What a custom gesture DOES: a Codable action executed through the
//  existing NetworkManager senders.
//

import Foundation
import Combine

enum GestureAction: Codable, Equatable, Hashable {
    case keyChord(name: String, keyCode: UInt16, command: Bool, option: Bool, control: Bool, shift: Bool)
    case media(name: String, action: String)
    case desktopLeft
    case desktopRight
    case missionControl
    case typeText(String)

    var displayName: String {
        switch self {
        case .keyChord(let name, _, _, _, _, _): return name
        case .media(let name, _): return name
        case .desktopLeft: return "Previous Desktop"
        case .desktopRight: return "Next Desktop"
        case .missionControl: return "Mission Control"
        case .typeText(let t): return "Type “\(t.prefix(18))\(t.count > 18 ? "…" : "")”"
        }
    }

    var icon: String {
        switch self {
        case .keyChord: return "command"
        case .media: return "playpause"
        case .desktopLeft, .desktopRight: return "rectangle.righthalf.inset.filled.arrow.right"
        case .missionControl: return "square.grid.3x3"
        case .typeText: return "keyboard"
        }
    }

    /// Curated choices shown in the Studio's action picker.
    static let presets: [GestureAction] = [
        .missionControl,
        .desktopLeft,
        .desktopRight,
        .media(name: "Play / Pause", action: "play_pause"),
        .media(name: "Next Track", action: "next"),
        .media(name: "Volume Up", action: "volume_up"),
        .media(name: "Volume Down", action: "volume_down"),
        .media(name: "Mute", action: "mute"),
        .keyChord(name: "Copy (⌘C)", keyCode: 8, command: true, option: false, control: false, shift: false),
        .keyChord(name: "Paste (⌘V)", keyCode: 9, command: true, option: false, control: false, shift: false),
        .keyChord(name: "Undo (⌘Z)", keyCode: 6, command: true, option: false, control: false, shift: false),
        .keyChord(name: "Screenshot (⌘⇧4)", keyCode: 21, command: true, option: false, control: false, shift: true),
        .keyChord(name: "Spotlight (⌘Space)", keyCode: 49, command: true, option: false, control: false, shift: false),
        .keyChord(name: "Close Window (⌘W)", keyCode: 13, command: true, option: false, control: false, shift: false),
        .keyChord(name: "New Tab (⌘T)", keyCode: 17, command: true, option: false, control: false, shift: false),
        .media(name: "Lock Screen", action: "lock_screen")
    ]

    func execute() {
        let net = NetworkManager.shared
        switch self {
        case .keyChord(_, let keyCode, let command, let option, let control, let shift):
            var modifiers: [UInt16] = []
            if command { modifiers.append(55) }
            if option { modifiers.append(58) }
            if control { modifiers.append(59) }
            if shift { modifiers.append(56) }
            for m in modifiers { net.sendKeyDown(keyCode: m) }
            net.sendKeyDown(keyCode: keyCode)
            net.sendKeyUp(keyCode: keyCode)
            for m in modifiers.reversed() { net.sendKeyUp(keyCode: m) }
        case .media(_, let action):
            net.sendMedia(action: action)
        case .desktopLeft:
            net.sendSwipe(fingers: 3, direction: "left")
        case .desktopRight:
            net.sendSwipe(fingers: 3, direction: "right")
        case .missionControl:
            net.sendSwipe(fingers: 3, direction: "up")
        case .typeText(let text):
            net.sendTypeText(text)
        }
    }
}

/// A user-recorded gesture: pose template + name + mapped action.
struct CustomGesture: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var vector: [Double]
    var action: GestureAction
    var enabled = true
}

/// Persists custom gestures and exposes the enabled templates for HandEngine.
final class GestureStore: ObservableObject {
    static let shared = GestureStore()
    private static let key = "gestureStudio.v1"

    @Published var gestures: [CustomGesture] {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([CustomGesture].self, from: data) {
            gestures = decoded
        } else {
            gestures = []
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(gestures) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    var enabledTemplates: [UUID: [Double]] {
        Dictionary(uniqueKeysWithValues: gestures.filter(\.enabled).map { ($0.id, $0.vector) })
    }

    func gesture(id: UUID) -> CustomGesture? {
        gestures.first { $0.id == id }
    }
}
