import Foundation
import UIKit

extension NetworkManager {
    // MARK: - Apps API (JSON over AirBridge)

    func requestInstalledApps() async throws -> [MacAppInfo] {
        // If already waiting, cancel the previous one
        if let cont = installedAppsContinuation {
            cont.resume(throwing: NSError(domain: "AirPad.Network", code: -2, userInfo: [NSLocalizedDescriptionKey: "Superseded by new request"]))
            installedAppsContinuation = nil
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[MacAppInfo], Error>) in
            self.installedAppsContinuation = cont
            try? self.send(type: "request_installed_apps", payload: [:])
        }
    }

    func sendLaunchApp(bundleIdentifier: String) {
        try? send(type: "launch_app", payload: ["bundleIdentifier": bundleIdentifier])
    }

    func sendQuitApp(bundleIdentifier: String) {
        try? send(type: "quit_app", payload: ["bundleIdentifier": bundleIdentifier])
    }

    func sendForceQuitApp(bundleIdentifier: String) {
        try? send(type: "force_quit_app", payload: ["bundleIdentifier": bundleIdentifier])
    }

    func sendActivateApp(bundleIdentifier: String) {
        try? send(type: "activate_app", payload: ["bundleIdentifier": bundleIdentifier])
    }

    func sendHideApp(bundleIdentifier: String) {
        try? send(type: "hide_app", payload: ["bundleIdentifier": bundleIdentifier])
    }

    func requestAppIcon(bundleIdentifier: String) async throws -> UIImage? {
        if let existing = appIconContinuations[bundleIdentifier] {
            existing.resume(returning: nil)
            appIconContinuations.removeValue(forKey: bundleIdentifier)
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UIImage?, Error>) in
            appIconContinuations[bundleIdentifier] = cont
            try? self.send(type: "request_app_icon", payload: ["bundleIdentifier": bundleIdentifier, "maxSize": 128])
        }
    }

    func sendOpenURL(_ urlString: String, bundleIdentifier: String?) {
        var payload: [String: Any] = ["url": urlString]
        if let bundleIdentifier { payload["bundleIdentifier"] = bundleIdentifier }
        try? send(type: "open_url", payload: payload)
    }

    // MARK: - Windows API
    func requestOpenWindows() async throws -> [MacWindowInfo] {
        if let cont = openWindowsContinuation {
            cont.resume(throwing: NSError(domain: "AirPad.Network", code: -2, userInfo: [NSLocalizedDescriptionKey: "Superseded by new request"]))
            openWindowsContinuation = nil
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[MacWindowInfo], Error>) in
            self.openWindowsContinuation = cont
            try? self.send(type: "request_open_windows", payload: [:])
        }
    }

    func sendFocusWindow(windowID: String) {
        try? send(type: "focus_window", payload: ["windowID": windowID])
    }
    
    func sendFocusWindowAndSpace(windowID: String) {
        // Composite command: ask the Mac agent to switch to the window's space, activate its app, and focus the window.
        try? send(type: "focus_window_and_space", payload: ["windowID": windowID])
    }

    // MARK: - Desktops API
    func requestDesktops() async throws -> [MacDesktopInfo] {
        if let cont = desktopsContinuation {
            cont.resume(throwing: NSError(domain: "AirPad.Network", code: -2, userInfo: [NSLocalizedDescriptionKey: "Superseded by new request"]))
            desktopsContinuation = nil
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[MacDesktopInfo], Error>) in
            self.desktopsContinuation = cont
            try? self.send(type: "request_desktops", payload: [:])
        }
    }

    func sendFocusDesktop(id: String) {
        try? send(type: "focus_desktop", payload: ["id": id])
    }

    // MARK: - Window Thumbnails
    func requestWindowThumbnail(windowID: String, maxWidth: Int = 320) async throws -> UIImage? {
        if let existing = windowThumbnailContinuations[windowID] {
            existing.resume(returning: nil)
            windowThumbnailContinuations.removeValue(forKey: windowID)
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UIImage?, Error>) in
            windowThumbnailContinuations[windowID] = cont
            try? self.send(type: "request_window_thumbnail", payload: ["windowID": windowID, "maxWidth": maxWidth])
        }
    }

    // Optional: request windows grouped by desktop (server may respond with open_windows including space info)
    func requestOpenWindowsByDesktop() async throws -> [MacWindowInfo] {
        try await requestOpenWindows() // fallback to flat list; grouping done client-side if space provided
    }
}
