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
    case launchApp(name: String, bundleID: String)
    case openURL(name: String, url: String)

    var displayName: String {
        switch self {
        case .keyChord(let name, _, _, _, _, _): return name
        case .media(let name, _): return name
        case .desktopLeft: return "Previous Desktop"
        case .desktopRight: return "Next Desktop"
        case .missionControl: return "Mission Control"
        case .typeText(let t): return "Type “\(t.prefix(18))\(t.count > 18 ? "…" : "")”"
        case .launchApp(let name, _): return "Open \(name)"
        case .openURL(let name, _): return name.isEmpty ? "Open Website" : "Open \(name)"
        }
    }

    var icon: String {
        switch self {
        case .keyChord: return "command"
        case .media: return "playpause"
        case .desktopLeft, .desktopRight: return "rectangle.righthalf.inset.filled.arrow.right"
        case .missionControl: return "square.grid.3x3"
        case .typeText: return "keyboard"
        case .launchApp: return "app.badge"
        case .openURL: return "safari"
        }
    }

    /// Curated choices shown in the Studio's action picker, grouped for the UI.
    static let presetGroups: [(title: String, actions: [GestureAction])] = [
        ("Navigation", [
            .missionControl,
            .desktopLeft,
            .desktopRight,
            .keyChord(name: "App Switcher (⌘Tab)", keyCode: 48, command: true, option: false, control: false, shift: false),
            .keyChord(name: "Spotlight (⌘Space)", keyCode: 49, command: true, option: false, control: false, shift: false),
        ]),
        ("Media & System", [
            .media(name: "Play / Pause", action: "play_pause"),
            .media(name: "Next Track", action: "next"),
            .media(name: "Previous Track", action: "previous"),
            .media(name: "Volume Up", action: "volume_up"),
            .media(name: "Volume Down", action: "volume_down"),
            .media(name: "Mute", action: "mute"),
            .media(name: "Brightness Up", action: "brightness_up"),
            .media(name: "Brightness Down", action: "brightness_down"),
            .media(name: "Lock Screen", action: "lock_screen"),
        ]),
        ("Editing", [
            .keyChord(name: "Copy (⌘C)", keyCode: 8, command: true, option: false, control: false, shift: false),
            .keyChord(name: "Paste (⌘V)", keyCode: 9, command: true, option: false, control: false, shift: false),
            .keyChord(name: "Cut (⌘X)", keyCode: 7, command: true, option: false, control: false, shift: false),
            .keyChord(name: "Undo (⌘Z)", keyCode: 6, command: true, option: false, control: false, shift: false),
            .keyChord(name: "Redo (⌘⇧Z)", keyCode: 6, command: true, option: false, control: false, shift: true),
            .keyChord(name: "Select All (⌘A)", keyCode: 0, command: true, option: false, control: false, shift: false),
            .keyChord(name: "Save (⌘S)", keyCode: 1, command: true, option: false, control: false, shift: false),
            .keyChord(name: "Find (⌘F)", keyCode: 3, command: true, option: false, control: false, shift: false),
        ]),
        ("Windows & Tabs", [
            .keyChord(name: "Close Window (⌘W)", keyCode: 13, command: true, option: false, control: false, shift: false),
            .keyChord(name: "New Window (⌘N)", keyCode: 45, command: true, option: false, control: false, shift: false),
            .keyChord(name: "New Tab (⌘T)", keyCode: 17, command: true, option: false, control: false, shift: false),
            .keyChord(name: "Reopen Tab (⌘⇧T)", keyCode: 17, command: true, option: false, control: false, shift: true),
            .keyChord(name: "Minimize (⌘M)", keyCode: 46, command: true, option: false, control: false, shift: false),
            .keyChord(name: "Hide App (⌘H)", keyCode: 4, command: true, option: false, control: false, shift: false),
            .keyChord(name: "Quit App (⌘Q)", keyCode: 12, command: true, option: false, control: false, shift: false),
            .keyChord(name: "Refresh (⌘R)", keyCode: 15, command: true, option: false, control: false, shift: false),
        ]),
        ("Screenshots", [
            .keyChord(name: "Screenshot Area (⌘⇧4)", keyCode: 21, command: true, option: false, control: false, shift: true),
            .keyChord(name: "Screenshot Screen (⌘⇧3)", keyCode: 20, command: true, option: false, control: false, shift: true),
        ]),
    ]

    /// Flat list (first entry is the recorder's default selection).
    static let presets: [GestureAction] = presetGroups.flatMap(\.actions)

    func execute() {
        let net = NetworkManager.shared
        switch self {
        case .keyChord(_, let keyCode, let command, let option, let control, let shift):
            // One atomic key_combo: modifier flags ride on the event itself.
            // (The old separate modifier key_down/key_up sequence could latch
            // a modifier forever if one packet was lost, which then corrupted
            // ALL later input — typed text became silent ⌘-shortcuts.)
            net.sendKeyCombo(keyCode, command: command, option: option,
                             control: control, shift: shift)
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
        case .launchApp(_, let bundleID):
            net.sendLaunchApp(bundleIdentifier: bundleID)
        case .openURL(_, let url):
            net.sendOpenURL(url)
        }
    }
}

/// The three built-in hold gestures whose actions users can remap (e.g. make
/// shaka open Mission Control instead of switching desktops). Defaults match
/// the original hard-wired behavior; AirPop keeps its own fixed meanings.
enum BuiltinGestureSlot: String, CaseIterable, Codable {
    case palmHold, thumbsUp, shaka

    var displayName: String {
        switch self {
        case .palmHold: return "Open palm (hold)"
        case .thumbsUp: return "Thumbs up 👍"
        case .shaka: return "Shaka 🤙"
        }
    }

    var defaultAction: GestureAction {
        switch self {
        case .palmHold: return .missionControl
        case .thumbsUp: return .media(name: "Play / Pause", action: "play_pause")
        case .shaka: return .desktopRight
        }
    }
}

enum BuiltinGestureMap {
    private static let key = "builtinGestures.v1"

    static func action(for slot: BuiltinGestureSlot) -> GestureAction {
        guard let data = UserDefaults.standard.data(forKey: key),
              let map = try? JSONDecoder().decode([BuiltinGestureSlot: GestureAction].self, from: data),
              let action = map[slot] else { return slot.defaultAction }
        return action
    }

    static func set(_ action: GestureAction, for slot: BuiltinGestureSlot) {
        var map: [BuiltinGestureSlot: GestureAction] = [:]
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([BuiltinGestureSlot: GestureAction].self, from: data) {
            map = decoded
        }
        map[slot] = action
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key)
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
