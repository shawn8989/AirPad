import SwiftUI
import UIKit

// If the main NetworkManager is available in the project, this extension will attach to it.
// Otherwise, define a minimal placeholder so this file compiles. Replace/merge as needed.
#if canImport(Foundation)
#endif

// Forward declaration of MacAppInfo if not visible in this file's scope.
// If the main type from AppShortcutsView.swift is visible, this will be ignored by the linker.
public struct MacAppInfo: Identifiable, Hashable {
    public let id: String
    public var name: String
    public var bundleIdentifier: String
    public var icon: UIImage?
    public var isRunning: Bool
    public var lastLaunched: Date?

    public init(id: String, name: String, bundleIdentifier: String? = nil, icon: UIImage? = nil, isRunning: Bool = false, lastLaunched: Date? = nil) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier ?? id
        self.icon = icon
        self.isRunning = isRunning
        self.lastLaunched = lastLaunched
    }
}

// Try to extend an existing NetworkManager. If it doesn't exist, provide a stub class.
class NetworkManager {
    static let shared = NetworkManager()
    // Existing properties and methods should be in your project; this is a stub for compilation.
}

extension NetworkManager {
    // MARK: - Apps API (Stub implementations)

    // TODO: Wire these to your real backend: send JSON over your socket/tunnel to macOS agent

    func requestInstalledApps() async throws -> [MacAppInfo] {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 300_000_000)
        let sample: [MacAppInfo] = [
            .init(id: "com.apple.Safari", name: "Safari"),
            .init(id: "com.apple.finder", name: "Finder", isRunning: true),
            .init(id: "com.apple.Terminal", name: "Terminal"),
            .init(id: "com.apple.Music", name: "Music"),
            .init(id: "com.apple.Notes", name: "Notes"),
            .init(id: "com.apple.dt.Xcode", name: "Xcode")
        ]
        return sample
    }

    func sendLaunchApp(bundleIdentifier: String) {
        print("[Apps] Launch app: \(bundleIdentifier)")
        // TODO: send { type: 'launch_app', bundleIdentifier } to macOS agent
    }

    func sendQuitApp(bundleIdentifier: String) {
        print("[Apps] Quit app: \(bundleIdentifier)")
        // TODO: send { type: 'quit_app', bundleIdentifier }
    }

    func sendForceQuitApp(bundleIdentifier: String) {
        print("[Apps] Force Quit app: \(bundleIdentifier)")
        // TODO: send { type: 'force_quit_app', bundleIdentifier }
    }

    func sendActivateApp(bundleIdentifier: String) {
        print("[Apps] Activate app: \(bundleIdentifier)")
        // TODO: send { type: 'activate_app', bundleIdentifier }
    }

    func sendHideApp(bundleIdentifier: String) {
        print("[Apps] Hide app: \(bundleIdentifier)")
        // TODO: send { type: 'hide_app', bundleIdentifier }
    }
}
