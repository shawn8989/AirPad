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
        let id: String          // lowercased app name
        let name: String
        var bundleID: String?
        var windows: [MacWindowInfo]
    }

    @ObservedObject private var network = NetworkManager.shared
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
                            if loading {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Loading desktops…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 160, height: 82)
                            } else {
                                Text("Add desktops in Mission Control on the Mac to switch between them here.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 200)
                            }
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
                    // Live preview composited on the Mac; placeholder until it streams in.
                    if let preview = network.desktopPreviews[desktop.id] {
                        Image(uiImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 132, height: 82)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        if windowCount > 0 {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Text("\(windowCount)")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .padding(4)
                                }
                            }
                            .frame(width: 132, height: 82)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(desktop.isActive ? Color.accentColor.opacity(0.22) : Color(.secondarySystemBackground))
                            .frame(width: 132, height: 82)
                        VStack(spacing: 2) {
                            Image(systemName: "display")
                                .foregroundStyle(desktop.isActive ? Color.accentColor : .secondary)
                            // Previews are real screenshots cached per visit.
                            Text("Visit once\nto preview")
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(desktop.isActive ? Color.accentColor : Color.secondary.opacity(0.25),
                                      lineWidth: desktop.isActive ? 2.5 : 1)
                        .frame(width: 132, height: 82)
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
        // Prefer a window whose desktop is known — that's the one the Mac can
        // jump to; otherwise fall back to any visible window, then activation.
        if let window = group.windows.first(where: { !$0.isMinimized && $0.space != nil })
            ?? group.windows.first(where: { !$0.isMinimized })
            ?? group.windows.first {
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
        var (fetchedDesktops, fetchedWindows) = await (desktopsTask, windowsTask)

        // The Spaces list is occasionally empty/stale right after connecting —
        // retry a few times before believing "there's only one desktop", so the
        // user isn't told to go add desktops that already exist.
        var attempts = 0
        while (fetchedDesktops?.count ?? 0) <= 1 && attempts < 3 && !Task.isCancelled {
            attempts += 1
            try? await Task.sleep(nanoseconds: 900_000_000)
            if let retried = try? await NetworkManager.shared.requestDesktops(),
               retried.count > (fetchedDesktops?.count ?? 0) {
                fetchedDesktops = retried
            }
        }

        if let fetchedDesktops { desktops = fetchedDesktops }
        // Kick off preview rendering on the Mac; images stream in as
        // desktop_preview messages and land in network.desktopPreviews.
        NetworkManager.shared.requestDesktopPreviews()

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
            // Group by app NAME: some of an app's windows report a bundle id
            // and some don't (Safari with many tabs), which split one app into
            // several look-alike groups when keyed by bundle id.
            let key = window.appName.lowercased()
            if var group = byApp[key] {
                group.windows.append(window)
                if group.bundleID == nil && !window.appBundleIdentifier.isEmpty {
                    group.bundleID = window.appBundleIdentifier
                }
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
