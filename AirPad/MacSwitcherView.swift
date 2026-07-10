//
//  MacSwitcherView.swift
//  AirPad
//
//  The organized Mac switcher: tap a desktop to jump straight to it, and see
//  open windows grouped BY APP (not a flat list of every window), expandable
//  to individual windows. Replaces unreliable multi-finger swiping as the way
//  to get to a program on another desktop.
//

import SwiftUI

struct MacSwitcherView: View {
    struct AppGroup: Identifiable {
        let id: String          // bundleID (fallback: app name)
        let name: String
        let bundleID: String?
        var windows: [MacWindowInfo]
    }

    @State private var desktops: [MacDesktopInfo] = []
    @State private var groups: [AppGroup] = []
    @State private var icons: [String: UIImage] = [:]
    @State private var loading = true
    @State private var expanded: Set<String> = []
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true

    // System/agent windows that only add noise to the list.
    private static let junkApps: Set<String> = [
        "Dock", "WindowManager", "Window Server", "Control Center", "Control Centre",
        "Notification Center", "Notification Centre", "Spotlight", "Wallpaper",
        "CoreServicesUIAgent", "TextInputMenuAgent", "Screenshot", "AirBridge",
        "Universal Control", "loginwindow", "Shortcuts Events"
    ]

    var body: some View {
        List {
            Section("Desktops") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(desktops) { desktop in
                            desktopCard(desktop)
                        }
                        if desktops.count < 2 {
                            Text("Add desktops in Mission Control on the Mac to switch between them here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 200)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            Section("Open Apps") {
                if loading && groups.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Reading the Mac's windows…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if groups.isEmpty {
                    Text("No app windows found.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(groups) { group in
                        appRow(group)
                        if expanded.contains(group.id) {
                            ForEach(group.windows) { window in
                                windowRow(window)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Desktops & Apps")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: AppShortcutsView()) {
                    Label("Launcher", systemImage: "plus.app")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: - Rows

    private func desktopCard(_ desktop: MacDesktopInfo) -> some View {
        let windowCount = groups.flatMap(\.windows).filter { $0.space == desktop.index }.count
        return Button {
            NetworkManager.shared.sendFocusDesktop(id: desktop.id)
            if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            // Optimistic highlight, then confirm with a refresh.
            desktops = desktops.map {
                var d = $0; d.isActive = ($0.id == desktop.id); return d
            }
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                await load()
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(desktop.isActive ? Color.accentColor.opacity(0.22) : Color(.secondarySystemBackground))
                        .frame(width: 92, height: 58)
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(desktop.isActive ? Color.accentColor : Color.secondary.opacity(0.25),
                                      lineWidth: desktop.isActive ? 2 : 1)
                        .frame(width: 92, height: 58)
                    VStack(spacing: 2) {
                        Image(systemName: "display")
                            .foregroundStyle(desktop.isActive ? Color.accentColor : .secondary)
                        if windowCount > 0 {
                            Text("\(windowCount) app\(windowCount == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text(desktop.name ?? "Desktop \(desktop.index)")
                    .font(.caption.weight(desktop.isActive ? .semibold : .regular))
                    .foregroundStyle(desktop.isActive ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func appRow(_ group: AppGroup) -> some View {
        HStack(spacing: 12) {
            Group {
                if let bundleID = group.bundleID, let icon = icons[bundleID] {
                    Image(uiImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    Image(systemName: "app.dashed")
                        .font(.title3)
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name)
                    .font(.callout.weight(.semibold))
                Text(windowSummary(group))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if group.windows.count > 1 {
                Button {
                    if expanded.contains(group.id) {
                        expanded.remove(group.id)
                    } else {
                        expanded.insert(group.id)
                    }
                } label: {
                    Image(systemName: expanded.contains(group.id) ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focus(group) }
        .task(id: group.bundleID) {
            guard let bundleID = group.bundleID, icons[bundleID] == nil else { return }
            if let icon = try? await NetworkManager.shared.requestAppIcon(bundleIdentifier: bundleID) {
                icons[bundleID] = icon
            }
        }
    }

    private func windowRow(_ window: MacWindowInfo) -> some View {
        Button {
            NetworkManager.shared.sendFocusWindowAndSpace(windowID: window.id)
            if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                await load()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: window.isMinimized ? "minus.square" : "macwindow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
                Text(window.title.isEmpty ? "(untitled window)" : window.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                if let space = window.space {
                    Text("Desktop \(space)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions & data

    /// Tapping an app focuses its best window (and switches desktop to it).
    private func focus(_ group: AppGroup) {
        if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        if let window = group.windows.first(where: { !$0.isMinimized }) ?? group.windows.first {
            NetworkManager.shared.sendFocusWindowAndSpace(windowID: window.id)
        } else if let bundleID = group.bundleID {
            NetworkManager.shared.sendActivateApp(bundleIdentifier: bundleID)
        }
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            await load()
        }
    }

    private func windowSummary(_ group: AppGroup) -> String {
        let count = group.windows.count
        let spaces = Set(group.windows.compactMap(\.space)).sorted()
        var text = "\(count) window\(count == 1 ? "" : "s")"
        if !spaces.isEmpty {
            text += " · Desktop \(spaces.map(String.init).joined(separator: ", "))"
        }
        return text
    }

    private func load() async {
        loading = true
        defer { loading = false }
        async let desktopsTask = try? NetworkManager.shared.requestDesktops()
        async let windowsTask = try? NetworkManager.shared.requestOpenWindows()
        let (fetchedDesktops, fetchedWindows) = await (desktopsTask, windowsTask)

        if let fetchedDesktops { desktops = fetchedDesktops }

        guard let windows = fetchedWindows else { return }
        // Keep only real, user-relevant windows: named apps, not system agents,
        // and either visible somewhere or minimized.
        let useful = windows.filter { window in
            !Self.junkApps.contains(window.appName) &&
            !window.appName.isEmpty &&
            (window.isOnScreen || window.isMinimized || window.space != nil) &&
            !(window.title.isEmpty && !window.isMinimized && window.space == nil)
        }
        // Group by app so ten Safari windows/tabs read as one "Safari" entry.
        var byApp: [String: AppGroup] = [:]
        for window in useful {
            let key = window.appBundleIdentifier.isEmpty ? window.appName : window.appBundleIdentifier
            if var group = byApp[key] {
                group.windows.append(window)
                byApp[key] = group
            } else {
                byApp[key] = AppGroup(id: key,
                                      name: window.appName,
                                      bundleID: window.appBundleIdentifier.isEmpty ? nil : window.appBundleIdentifier,
                                      windows: [window])
            }
        }
        groups = byApp.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

#Preview {
    NavigationStack { MacSwitcherView() }
}
