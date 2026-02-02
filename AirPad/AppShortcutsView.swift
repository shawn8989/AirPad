import SwiftUI
import UIKit
import Combine

// MARK: - Model
public struct MacAppInfo: Identifiable, Hashable {
    public let id: String // bundle identifier
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

// MARK: - View Model
@MainActor
final class AppCatalogViewModel: ObservableObject {
    @Published var favorites: [MacAppInfo] = [] { didSet { persistFavorites() } }
    @Published var recents: [MacAppInfo] = [] { didSet { persistRecents() } }
    @Published var allApps: [MacAppInfo] = []

    @Published var openWindows: [MacWindowInfo] = []
    @Published var desktops: [MacDesktopInfo] = []
    private var windowsAutoRefreshTask: Task<Void, Never>? = nil
    private var appsAutoRefreshTask: Task<Void, Never>? = nil
    private var desktopsAutoRefreshTask: Task<Void, Never>? = nil
    private var cancellables = Set<AnyCancellable>()

    @Published var searchText: String = ""
    @Published var isLoading: Bool = false

    private let favoritesKey = "AppShortcuts.Favorites"
    private let recentsKey = "AppShortcuts.Recents"
    
    private let iconCache = NSCache<NSString, UIImage>()
    @Published var profileKey: String = "default" // TODO: set per-Mac profile if available
    
    @Published var bannerMessage: String? = nil
    let isPreview: Bool

    init(isPreview: Bool = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1") {
        self.isPreview = isPreview
        if isPreview {
            // Seed demo data for previews and avoid network work.
            self.isLoading = false
            let demo: [MacAppInfo] = [
                .init(id: "com.apple.Safari", name: "Safari"),
                .init(id: "com.apple.finder", name: "Finder", isRunning: true),
                .init(id: "com.apple.Terminal", name: "Terminal"),
                .init(id: "com.apple.Music", name: "Music"),
                .init(id: "com.apple.Notes", name: "Notes"),
                .init(id: "com.apple.dt.Xcode", name: "Xcode")
            ]
            self.allApps = demo.sorted { $0.name < $1.name }
            // Provide some sample favorites/recents to reduce visual clutter in previews.
            self.favorites = Array(self.allApps.prefix(3))
            self.recents = Array(self.allApps.dropFirst(1).prefix(2))
        } else {
            Task { await loadInitial() }
        }
        bindNetworkPushes()
    }

    private func showBanner(_ message: String, autoHide: Bool = true, duration: TimeInterval = 2.0) {
        self.bannerMessage = message
        guard autoHide else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if self.bannerMessage == message {
                self.bannerMessage = nil
            }
        }
    }

    func loadInitial() async {
        await refresh()
        loadPersisted()
    }

    func refresh(silent: Bool = false) async {
        isLoading = true
        if isPreview {
            isLoading = false
            return
        }
        defer { isLoading = false }
        do {
            let apps = try await NetworkManager.shared.requestInstalledApps()
            // Disambiguate duplicate bundle identifiers by synthesizing a stable unique id
            // Sort to prefer running apps first, then by name
            let ordered = apps.sorted { (lhs, rhs) in
                if lhs.isRunning != rhs.isRunning { return lhs.isRunning && !rhs.isRunning }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            // Count how many entries share the same bundle identifier
            let countsByBundle = ordered.reduce(into: [String: Int]()) { acc, a in
                acc[a.bundleIdentifier, default: 0] += 1
            }

            // Helper to slugify names for id suffixes
            func slug(_ s: String) -> String {
                let lower = s.lowercased()
                let pattern = "[^a-z0-9]+"
                let slugged = lower.replacingOccurrences(of: pattern, with: "-", options: .regularExpression)
                return slugged.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            }

            // Build adjusted list with unique ids
            var usedIDs = Set<String>()
            var adjusted: [MacAppInfo] = []
            for a in ordered {
                let needsDisambiguation = (countsByBundle[a.bundleIdentifier] ?? 0) > 1
                var newID = a.id
                if needsDisambiguation {
                    let base = a.bundleIdentifier + "|" + slug(a.name)
                    var candidate = base.isEmpty ? a.bundleIdentifier : base
                    var n = 2
                    while usedIDs.contains(candidate) {
                        candidate = base + "-\(n)"; n += 1
                    }
                    newID = candidate
                }
                usedIDs.insert(newID)
                adjusted.append(MacAppInfo(id: newID,
                                           name: a.name,
                                           bundleIdentifier: a.bundleIdentifier,
                                           icon: a.icon,
                                           isRunning: a.isRunning,
                                           lastLaunched: a.lastLaunched))
            }

            // Preserve existing icons by bundleIdentifier
            var existingIconForBundle: [String: UIImage] = [:]
            for e in self.allApps {
                if let ic = e.icon, existingIconForBundle[e.bundleIdentifier] == nil {
                    existingIconForBundle[e.bundleIdentifier] = ic
                }
            }
            var merged = adjusted
            for i in merged.indices {
                if merged[i].icon == nil, let ic = existingIconForBundle[merged[i].bundleIdentifier] {
                    merged[i].icon = ic
                }
            }

            self.allApps = merged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            // After refresh, rehydrate favorites/recents by bundle ID
            rehydrateCollections()
            if !silent { showBanner("Updated \(apps.count) apps") }
        } catch {
            // Fallback demo data
            let demo: [MacAppInfo] = [
                .init(id: "com.apple.Safari", name: "Safari"),
                .init(id: "com.apple.finder", name: "Finder", isRunning: true),
                .init(id: "com.apple.Terminal", name: "Terminal"),
                .init(id: "com.apple.Music", name: "Music"),
                .init(id: "com.apple.Notes", name: "Notes"),
                .init(id: "com.apple.dt.Xcode", name: "Xcode")
            ]
            self.allApps = demo.sorted { $0.name < $1.name }
            rehydrateCollections()
            if !silent { showBanner("Failed to load apps: \(error.localizedDescription). Showing demo list.") }
        }
    }

    func refreshWindows(silent: Bool = false) async {
        if isPreview { return }
        guard NetworkManager.shared.isConnected else {
            // Avoid noisy banners when disconnected; clear the list if needed
            if !openWindows.isEmpty { openWindows = [] }
            return
        }
        do {
            let windows = try await NetworkManager.shared.requestOpenWindows()
            self.openWindows = windows
            if !silent { showBanner("Found \(windows.count) windows") }
        } catch {
            if !silent { showBanner("Failed to load windows: \(error.localizedDescription)", autoHide: false) }
        }
    }
    
    func refreshDesktops(silent: Bool = false) async {
        if isPreview { return }
        guard NetworkManager.shared.isConnected else {
            if !desktops.isEmpty { desktops = [] }
            return
        }
        do {
            let spaces = try await NetworkManager.shared.requestDesktops()
            self.desktops = spaces.sorted { $0.index < $1.index }
            if !silent { showBanner("Found \(spaces.count) desktops") }
        } catch {
            if !silent { showBanner("Failed to load desktops: \(error.localizedDescription)", autoHide: false) }
        }
    }

    func focus(window: MacWindowInfo) {
        // In previews, do nothing.
        if isPreview { return }

        // Pause auto-refresh to avoid UI flicker while the server switches space/app/window.
        stopWindowsAutoRefresh()
        stopDesktopsAutoRefresh()

        // Ask the server to perform the composite focus and push updated state back.
        NetworkManager.shared.sendFocusWindowAndSpace(windowID: window.id)

        // Resume auto-refresh shortly after to keep periodic updates.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s grace period
            self.startWindowsAutoRefresh()
            self.startDesktopsAutoRefresh()
        }
    }
    
    func focus(desktop: MacDesktopInfo) {
        if isPreview { return }
        stopWindowsAutoRefresh()
        stopDesktopsAutoRefresh()
        NetworkManager.shared.sendFocusDesktop(id: desktop.id)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s to allow switch
            await self.refreshDesktops(silent: true)
            await self.refreshWindows(silent: true)
            self.startDesktopsAutoRefresh()
            self.startWindowsAutoRefresh()
        }
    }

    func ensureAppIcon(for window: MacWindowInfo) async {
        if isPreview { return }
        if window.appIcon != nil { return }
        if let cached = iconCache.object(forKey: window.appBundleIdentifier as NSString) {
            if let idx = openWindows.firstIndex(where: { $0.id == window.id }) {
                openWindows[idx].appIcon = cached
            }
            return
        }
        do {
            if let image = try await NetworkManager.shared.requestAppIcon(bundleIdentifier: window.appBundleIdentifier) {
                iconCache.setObject(image, forKey: window.appBundleIdentifier as NSString)
                if let idx = openWindows.firstIndex(where: { $0.id == window.id }) {
                    openWindows[idx].appIcon = image
                }
            }
        } catch {
            // Ignore icon errors; keep placeholder
        }
    }

    func startWindowsAutoRefresh(interval: TimeInterval = 2.0) {
        if isPreview { return }
        windowsAutoRefreshTask?.cancel()
        windowsAutoRefreshTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                await self.refreshWindows(silent: true)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }
    
    func startDesktopsAutoRefresh(interval: TimeInterval = 4.0) {
        if isPreview { return }
        desktopsAutoRefreshTask?.cancel()
        desktopsAutoRefreshTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                await self.refreshDesktops(silent: true)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopWindowsAutoRefresh() {
        windowsAutoRefreshTask?.cancel()
        windowsAutoRefreshTask = nil
    }
    
    func stopDesktopsAutoRefresh() {
        desktopsAutoRefreshTask?.cancel()
        desktopsAutoRefreshTask = nil
    }

    func startAppsAutoRefresh(interval: TimeInterval = 6.0) {
        if isPreview { return }
        appsAutoRefreshTask?.cancel()
        appsAutoRefreshTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                if NetworkManager.shared.isConnected {
                    await self.refresh(silent: true)
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopAppsAutoRefresh() {
        appsAutoRefreshTask?.cancel()
        appsAutoRefreshTask = nil
    }

    func toggleFavorite(_ app: MacAppInfo) {
        if let idx = favorites.firstIndex(where: { $0.id == app.id }) {
            favorites.remove(at: idx)
        } else {
            favorites.insert(app, at: 0)
        }
    }

    func launch(_ app: MacAppInfo) {
        NetworkManager.shared.sendLaunchApp(bundleIdentifier: app.bundleIdentifier)
        bumpRecent(app)
    }

    func quit(_ app: MacAppInfo) {
        NetworkManager.shared.sendQuitApp(bundleIdentifier: app.bundleIdentifier)
    }

    func forceQuit(_ app: MacAppInfo) {
        NetworkManager.shared.sendForceQuitApp(bundleIdentifier: app.bundleIdentifier)
    }

    func activate(_ app: MacAppInfo) {
        NetworkManager.shared.sendActivateApp(bundleIdentifier: app.bundleIdentifier)
    }

    func hide(_ app: MacAppInfo) {
        NetworkManager.shared.sendHideApp(bundleIdentifier: app.bundleIdentifier)
    }
    
    func launchOrActivate(_ app: MacAppInfo) {
        if app.isRunning {
            activate(app)
        } else {
            launch(app)
        }
    }
    
    func ensureIcon(for app: MacAppInfo) async {
        if isPreview { return }
        if app.icon != nil { return }
        if let cached = iconCache.object(forKey: app.id as NSString) {
            updateIcon(cached, for: app.id)
            return
        }
        do {
            if let image = try await NetworkManager.shared.requestAppIcon(bundleIdentifier: app.bundleIdentifier) {
                iconCache.setObject(image, forKey: app.id as NSString)
                updateIcon(image, for: app.id)
            }
        } catch {
            // Ignore icon errors; keep placeholder
        }
    }

    private func updateIcon(_ image: UIImage, for id: String) {
        if let idx = allApps.firstIndex(where: { $0.id == id }) {
            allApps[idx].icon = image
        }
        if let fidx = favorites.firstIndex(where: { $0.id == id }) {
            favorites[fidx].icon = image
        }
        if let ridx = recents.firstIndex(where: { $0.id == id }) {
            recents[ridx].icon = image
        }
    }

    func openURL(_ urlString: String, with app: MacAppInfo?) {
        let bundle = app?.bundleIdentifier
        NetworkManager.shared.sendOpenURL(urlString, bundleIdentifier: bundle)
        if let app { bumpRecent(app) }
    }

    // MARK: - Helpers
    enum Section: String, CaseIterable, Identifiable { case favorites = "Favorites", recents = "Recents", all = "All"; var id: String { rawValue } }

    func apps(in section: Section) -> [MacAppInfo] {
        let base: [MacAppInfo]
        switch section {
        case .favorites: base = favorites
        case .recents: base = recents
        case .all: base = allApps
        }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return base }
        let q = searchText.lowercased()
        return base.filter { $0.name.lowercased().contains(q) || $0.bundleIdentifier.lowercased().contains(q) }
    }

    private func bumpRecent(_ app: MacAppInfo) {
        var a = app
        a.lastLaunched = Date()
        recents.removeAll { $0.id == a.id }
        recents.insert(a, at: 0)
        // Cap recents
        if recents.count > 30 { recents = Array(recents.prefix(30)) }
    }

    private func loadPersisted() {
        let favIDs = (UserDefaults.standard.array(forKey: favoritesKey) as? [String]) ?? []
        let recentIDs = (UserDefaults.standard.array(forKey: recentsKey) as? [String]) ?? []
        favorites = favIDs.compactMap { id in allApps.first { $0.id == id } }
        recents = recentIDs.compactMap { id in allApps.first { $0.id == id } }
    }

    private func rehydrateCollections() {
        // Rebuild persisted lists using the refreshed catalog
        let favIDs = (UserDefaults.standard.array(forKey: favoritesKey) as? [String]) ?? []
        favorites = favIDs.compactMap { id in allApps.first { $0.id == id } }
        let recentIDs = (UserDefaults.standard.array(forKey: recentsKey) as? [String]) ?? []
        recents = recentIDs.compactMap { id in allApps.first { $0.id == id } }
    }

    private func persistFavorites() {
        UserDefaults.standard.set(favorites.map { $0.id }, forKey: favoritesKey)
    }

    private func persistRecents() {
        UserDefaults.standard.set(recents.map { $0.id }, forKey: recentsKey)
    }

    private func bindNetworkPushes() {
        NetworkManager.shared.$pushedOpenWindows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windows in
                guard let self = self else { return }
                // Update immediately with server-pushed state
                self.openWindows = windows
            }
            .store(in: &cancellables)

        NetworkManager.shared.$pushedDesktops
            .receive(on: DispatchQueue.main)
            .sink { [weak self] desktops in
                guard let self = self else { return }
                self.desktops = desktops.sorted { $0.index < $1.index }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Views
struct AppShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: AppCatalogViewModel
    @State private var section: AppCatalogViewModel.Section = .all
    
    @State private var showOpenURLSheet = false
    @State private var openURLText: String = ""
    @State private var appForOpen: MacAppInfo? = nil
    @State private var showManageFavorites = false
    @State private var showWindowsSheet = false
    @State private var showDesktopsSheet = false

    @AppStorage("hasSeenAppShortcutsTips") private var hasSeenTips: Bool = false

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 96), spacing: 16)]

    init() {
        _vm = StateObject(wrappedValue: AppCatalogViewModel())
    }

    init(vm: AppCatalogViewModel) {
        _vm = StateObject(wrappedValue: vm)
    }

    private var visibleApps: [MacAppInfo] {
        vm.apps(in: section)
    }
    
    @ViewBuilder
    private var overlayContent: some View {
        if vm.isLoading {
            ProgressView("Loading apps…")
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        } else if vm.apps(in: section).isEmpty {
            ContentUnavailableView(
                "No Apps",
                systemImage: "app.dashed",
                description: Text("Try refreshing or adjusting your search.")
            )
        } else {
            EmptyView()
        }
    }

    // Break out segmented control to help the type-checker
    private var sectionPicker: some View {
        let sections = AppCatalogViewModel.Section.allCases
        return Picker("Section", selection: $section) {
            ForEach(sections) { s in
                Text(s.rawValue).tag(s)
            }
        }
        .pickerStyle(.segmented)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Task { await vm.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showManageFavorites = true
            } label: {
                Label("Manage Favorites", systemImage: "star")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showWindowsSheet = true
            } label: {
                Label("Windows", systemImage: "macwindow")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showDesktopsSheet = true
            } label: {
                Label("Desktops", systemImage: "rectangle.3.group")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { dismiss() }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sectionPicker
                    .padding([.horizontal, .top])

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(visibleApps, id: \.id) { app in
                            AppShortcutItem(
                                app: app,
                                isFavorite: isFavorite(app),
                                onLaunch: { vm.launchOrActivate(app); haptic(.light) },
                                onActivate: { vm.activate(app); haptic(.light) },
                                onQuit: { vm.quit(app) },
                                onForceQuit: { vm.forceQuit(app) },
                                onHide: { vm.hide(app) },
                                onToggleFavorite: { vm.toggleFavorite(app) },
                                onAppear: { Task { await vm.ensureIcon(for: app) } },
                                onOpenURL: { appForOpen = app; openURLText = ""; showOpenURLSheet = true }
                            )
                        }
                    }
                    .padding()
                    .refreshable {
                        await vm.refresh()
                    }
                }
                .overlay(overlayContent)
                .overlay(alignment: .top) {
                    if let msg = vm.bannerMessage {
                        BannerView(message: msg) { vm.bannerMessage = nil }
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .padding(.top, 8)
                    }
                }
                .overlay(alignment: .bottom) {
                    if !hasSeenTips, !vm.isLoading, !visibleApps.isEmpty {
                        TipsOverlay(dismiss: { hasSeenTips = true })
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.bottom, 12)
                    }
                }
            }
            .navigationTitle("App Shortcuts")
            .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search apps")
            .toolbar {
                toolbarContent
            }
            .task {
                vm.startWindowsAutoRefresh()
                vm.startAppsAutoRefresh()
                vm.startDesktopsAutoRefresh()
            }
            .onDisappear {
                vm.stopWindowsAutoRefresh()
                vm.stopAppsAutoRefresh()
                vm.stopDesktopsAutoRefresh()
            }
            .sheet(isPresented: $showOpenURLSheet) {
                NavigationStack {
                    Form {
                        SwiftUI.Section("URL") {
                            TextField("https://… or file:///…", text: $openURLText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                        }
                    }
                    .navigationTitle("Open URL")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { showOpenURLSheet = false }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Open") {
                                vm.openURL(openURLText, with: appForOpen)
                                showOpenURLSheet = false
                            }.disabled(openURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .sheet(isPresented: $showManageFavorites) {
                NavigationStack {
                    FavoritesManagerView(favorites: $vm.favorites)
                        .navigationTitle("Manage Favorites")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showManageFavorites = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showWindowsSheet) {
                NavigationStack {
                    WindowsSwitcherView(
                        windows: $vm.openWindows,
                        onRefresh: { await vm.refreshWindows() },
                        onFocus: { vm.focus(window: $0) },
                        onRequestIcon: { await vm.ensureAppIcon(for: $0) }
                    )
                    .navigationTitle("Windows")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showWindowsSheet = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showDesktopsSheet) {
                NavigationStack {
                    DesktopsSwitcherView(
                        desktops: $vm.desktops,
                        onRefresh: { await vm.refreshDesktops() },
                        onFocus: { vm.focus(desktop: $0) }
                    )
                    .navigationTitle("Desktops")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showDesktopsSheet = false }
                        }
                    }
                }
            }
        }
    }

    private func isFavorite(_ app: MacAppInfo) -> Bool {
        vm.favorites.contains(where: { $0.id == app.id })
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.impactOccurred()
    }
}

private struct AppShortcutItem: View {
    let app: MacAppInfo
    let isFavorite: Bool
    let onLaunch: () -> Void
    let onActivate: () -> Void
    let onQuit: () -> Void
    let onForceQuit: () -> Void
    let onHide: () -> Void
    let onToggleFavorite: () -> Void
    let onAppear: () -> Void
    let onOpenURL: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                AppIconView(image: app.icon)
                    .frame(width: 76, height: 76)

                if app.isRunning {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                        .offset(x: 4, y: -4)
                        .accessibilityLabel("Running")
                }
            }
            Text(app.name)
                .font(.footnote)
                .lineLimit(1)
                .frame(maxWidth: 96)
        }
        .contentShape(Rectangle())
        .onTapGesture { onLaunch() }
        .onAppear(perform: onAppear)
        .contextMenu {
            Button { onLaunch() } label: { Label("Open (Launch/Activate)", systemImage: "play.fill") }
            Button { onOpenURL() } label: { Label("Open URL…", systemImage: "link") }
            Divider()
            Button(role: .none) { onHide() } label: { Label("Hide", systemImage: "eye.slash") }
            Button(role: .destructive) { onQuit() } label: { Label("Quit", systemImage: "xmark.circle") }
            Button(role: .destructive) { onForceQuit() } label: { Label("Force Quit", systemImage: "exclamationmark.octagon") }
            Divider()
            Button { onToggleFavorite() } label: {
                Label(isFavorite ? "Remove Favorite" : "Add to Favorites", systemImage: isFavorite ? "star.slash" : "star")
            }
        }
        .buttonStyle(.plain)
    }
}

struct AppIconView: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            if let ui = image {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.thinMaterial)
                    Image(systemName: "app.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct FavoritesManagerView: View {
    @Binding var favorites: [MacAppInfo]
    @State private var editMode: EditMode = .active

    var body: some View {
        List {
            ForEach(favorites) { app in
                HStack(spacing: 12) {
                    AppIconView(image: app.icon).frame(width: 28, height: 28)
                    Text(app.name)
                        .lineLimit(1)
                }
            }
            .onMove { indices, newOffset in
                favorites.move(fromOffsets: indices, toOffset: newOffset)
            }
        }
        .environment(\.editMode, $editMode)
    }
}

struct WindowsSwitcherView: View {
    @Binding var windows: [MacWindowInfo]
    var onRefresh: () async -> Void
    var onFocus: (MacWindowInfo) -> Void
    var onRequestIcon: (MacWindowInfo) async -> Void

    var body: some View {
        List {
            // Group windows by their space if present
            let grouped = Dictionary(grouping: windows, by: { $0.space ?? -1 })
            ForEach(grouped.keys.sorted(), id: \.self) { key in
                Section(header: Text(key >= 0 ? "Desktop \(key)" : "Windows")) {
                    ForEach(grouped[key] ?? []) { win in
                        Button(action: { onFocus(win) }) {
                            HStack(spacing: 12) {
                                // Thumbnail
                                ZStack {
                                    if let thumb = win.thumbnail {
                                        Image(uiImage: thumb)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 56, height: 36)
                                            .clipped()
                                            .cornerRadius(6)
                                    } else {
                                        RoundedRectangle(cornerRadius: 6).fill(.thinMaterial)
                                            .frame(width: 56, height: 36)
                                            .overlay(Image(systemName: "macwindow.on.rectangle").foregroundStyle(.secondary))
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(win.title.isEmpty ? "Untitled" : win.title)
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        AppIconView(image: win.appIcon).frame(width: 16, height: 16)
                                        Text(win.appName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                if win.isMinimized { Image(systemName: "arrow.down.right.and.arrow.up.left").foregroundStyle(.secondary) }
                                if !win.isOnScreen { Image(systemName: "rectangle.slash").foregroundStyle(.secondary) }
                            }
                        }
                        .task {
                            // Request icon and thumbnail lazily
                            await onRequestIcon(win)
                            if win.thumbnail == nil, let img = try? await NetworkManager.shared.requestWindowThumbnail(windowID: win.id) {
                                if let idx = (windows.firstIndex { $0.id == win.id }) {
                                    windows[idx].thumbnail = img
                                }
                            }
                        }
                    }
                }
            }
        }
        .refreshable { await onRefresh() }
        .overlay {
            if windows.isEmpty {
                ContentUnavailableView("No Windows", systemImage: "macwindow", description: Text("No open windows were reported by the Mac."))
            }
        }
    }
}

struct DesktopsSwitcherView: View {
    @Binding var desktops: [MacDesktopInfo]
    var onRefresh: () async -> Void
    var onFocus: (MacDesktopInfo) -> Void

    var body: some View {
        List {
            ForEach(desktops) { d in
                Button(action: { onFocus(d) }) {
                    HStack(spacing: 12) {
                        Image(systemName: d.isActive ? "rectangle.on.rectangle" : "rectangle")
                            .imageScale(.large)
                            .foregroundStyle(d.isActive ? .blue : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name ?? "Desktop \(d.index)")
                                .lineLimit(1)
                            if !d.isActive {
                                Text("Desktop \(d.index)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if d.isActive { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                    }
                }
            }
        }
        .refreshable { await onRefresh() }
        .overlay {
            if desktops.isEmpty {
                ContentUnavailableView("No Desktops", systemImage: "square.grid.3x3", description: Text("No desktops were reported by the Mac."))
            }
        }
    }
}

struct BannerView: View {
    var message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill").foregroundStyle(.blue)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal)
    }
}

struct TipsOverlay: View {
    var dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                Text("Tips").font(.headline)
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark.circle.fill") }
            }
            Text("• Tap an app icon to launch or activate it.")
            Text("• Long-press for more actions like Hide, Quit, or Force Quit.")
            Text("• Pull to refresh app list. Use the toolbar to view Windows and Desktops.")
        }
        .font(.footnote)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }
}

struct AppShortcutsPreviewContainer: View {
    @StateObject private var vm = AppCatalogViewModel(isPreview: true)
    var body: some View {
        AppShortcutsView(vm: vm)
    }
}

#Preview {
    AppShortcutsPreviewContainer()
}

