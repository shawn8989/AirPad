import SwiftUI
import UIKit

public struct MacAppInfo: Identifiable, Hashable {
    public let id: String // bundleIdentifier
    public let name: String
    public let bundleIdentifier: String
    public let icon: UIImage?
    public var isRunning: Bool = false
    public var lastLaunched: Date? = nil

    public init(id: String, name: String, bundleIdentifier: String, icon: UIImage? = nil, isRunning: Bool = false, lastLaunched: Date? = nil) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.icon = icon
        self.isRunning = isRunning
        self.lastLaunched = lastLaunched
    }
}

@MainActor
public class AppCatalogViewModel: ObservableObject {
    @Published public var favorites: [MacAppInfo] = []
    @Published public var recents: [MacAppInfo] = []
    @Published public var allApps: [MacAppInfo] = []

    @Published public var searchText: String = ""
    @Published public var isLoading: Bool = false

    public init() {}

    // MARK: - Loading

    public func loadInitial() {
        Task {
            await refresh()
        }
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let apps = try await networkRequestInstalledApps()
            allApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            // Remove favorites not in allApps anymore
            favorites.removeAll(where: { app in !allApps.contains(where: { $0.id == app.id }) })
            // Remove recents not in allApps anymore
            recents.removeAll(where: { app in !allApps.contains(where: { $0.id == app.id }) })
        } catch {
            // Demo fallback
            allApps = Self.demoApps()
        }
    }

    // MARK: - Favorites

    public func toggleFavorite(_ app: MacAppInfo) {
        if let idx = favorites.firstIndex(of: app) {
            favorites.remove(at: idx)
        } else {
            favorites.insert(app, at: 0)
        }
    }

    // MARK: - App Actions

    public func launch(_ app: MacAppInfo) {
        networkSendLaunch(bundleIdentifier: app.bundleIdentifier)
        updateRecentLaunched(app)
    }

    public func quit(_ app: MacAppInfo) {
        networkSendQuit(bundleIdentifier: app.bundleIdentifier)
    }

    public func forceQuit(_ app: MacAppInfo) {
        networkSendForceQuit(bundleIdentifier: app.bundleIdentifier)
    }

    public func activate(_ app: MacAppInfo) {
        networkSendActivate(bundleIdentifier: app.bundleIdentifier)
    }

    public func hide(_ app: MacAppInfo) {
        networkSendHide(bundleIdentifier: app.bundleIdentifier)
    }

    // MARK: - Recent Management

    private func updateRecentLaunched(_ app: MacAppInfo) {
        var updatedApp = app
        updatedApp.lastLaunched = Date()
        // Remove if exists
        recents.removeAll(where: { $0.id == app.id })
        // Insert at front
        recents.insert(updatedApp, at: 0)
    }

    // MARK: - NetworkManager Integration with fallback stubs

    private func networkRequestInstalledApps() async throws -> [MacAppInfo] {
        #if canImport(NetworkManager)
        if let nm = NetworkManager.shared {
            return try await nm.requestInstalledApps()
        }
        #endif
        throw NSError(domain: "NetworkManager not available", code: -1)
    }

    private func networkSendLaunch(bundleIdentifier: String) {
        #if canImport(NetworkManager)
        NetworkManager.shared?.sendLaunchApp(bundleIdentifier: bundleIdentifier)
        #endif
    }

    private func networkSendQuit(bundleIdentifier: String) {
        #if canImport(NetworkManager)
        NetworkManager.shared?.sendQuitApp(bundleIdentifier: bundleIdentifier)
        #endif
    }

    private func networkSendForceQuit(bundleIdentifier: String) {
        #if canImport(NetworkManager)
        NetworkManager.shared?.sendForceQuitApp(bundleIdentifier: bundleIdentifier)
        #endif
    }

    private func networkSendActivate(bundleIdentifier: String) {
        #if canImport(NetworkManager)
        NetworkManager.shared?.sendActivateApp(bundleIdentifier: bundleIdentifier)
        #endif
    }

    private func networkSendHide(bundleIdentifier: String) {
        #if canImport(NetworkManager)
        NetworkManager.shared?.sendHideApp(bundleIdentifier: bundleIdentifier)
        #endif
    }

    // MARK: - Demo Apps

    public static func demoApps() -> [MacAppInfo] {
        [
            MacAppInfo(
                id: "com.apple.Safari",
                name: "Safari",
                bundleIdentifier: "com.apple.Safari",
                icon: UIImage(systemName: "safari"),
                isRunning: true
            ),
            MacAppInfo(
                id: "com.apple.Mail",
                name: "Mail",
                bundleIdentifier: "com.apple.Mail",
                icon: UIImage(systemName: "envelope"),
                isRunning: false
            ),
            MacAppInfo(
                id: "com.apple.TextEdit",
                name: "TextEdit",
                bundleIdentifier: "com.apple.TextEdit",
                icon: UIImage(systemName: "doc.plaintext"),
                isRunning: false
            ),
            MacAppInfo(
                id: "com.apple.Music",
                name: "Music",
                bundleIdentifier: "com.apple.Music",
                icon: UIImage(systemName: "music.note"),
                isRunning: true
            )
        ]
    }
}

public struct AppIconView: View {
    let image: UIImage?

    public init(image: UIImage?) {
        self.image = image
    }

    public var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(20)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

public struct AppShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AppCatalogViewModel()

    @State private var selectedSegment: Int = 2

    private enum Section: Int, CaseIterable, Identifiable {
        case favorites = 0
        case recents = 1
        case all = 2

        var id: Int { rawValue }
        var title: String {
            switch self {
            case .favorites: return "Favorites"
            case .recents: return "Recents"
            case .all: return "All"
            }
        }
    }

    private var filteredApps: [MacAppInfo] {
        let apps: [MacAppInfo]
        switch Section(rawValue: selectedSegment) {
        case .favorites: apps = vm.favorites
        case .recents: apps = vm.recents
        default: apps = vm.allApps
        }

        guard !vm.searchText.isEmpty else { return apps }

        let lowercased = vm.searchText.lowercased()
        return apps.filter {
            $0.name.lowercased().contains(lowercased)
            || $0.bundleIdentifier.lowercased().contains(lowercased)
        }
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Picker(selection: $selectedSegment) {
                    ForEach(Section.allCases) { section in
                        Text(section.title).tag(section.rawValue)
                    }
                } label: {
                    Text("Section")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Loading apps")
                } else if filteredApps.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        Text("No matching apps")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                            ForEach(filteredApps) { app in
                                AppItemView(app: app, isFavorite: vm.favorites.contains(app)) {
                                    vm.launch(app)
                                    Haptics.light()
                                } contextMenu: {
                                    Button("Launch") { vm.launch(app) }
                                    Button("Activate") { vm.activate(app) }
                                    Button("Quit") { vm.quit(app) }
                                    Button("Force Quit") { vm.forceQuit(app) }
                                    Button("Hide") { vm.hide(app) }
                                    Divider()
                                    Button(vm.favorites.contains(app) ? "Remove Favorite" : "Add Favorite") {
                                        vm.toggleFavorite(app)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Apps")
            .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { Task { await vm.refresh() } }) {
                        Label("Refresh", systemImage: "arrow.clockwise.circle")
                    }
                    .disabled(vm.isLoading)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                vm.loadInitial()
            }
        }
    }

    struct AppItemView: View {
        let app: MacAppInfo
        let isFavorite: Bool
        let launchAction: () -> Void
        let contextMenu: () -> Void

        @ViewBuilder var body: some View {
            Button {
                launchAction()
            } label: {
                VStack(spacing: 6) {
                    AppIconView(image: app.icon)
                        .frame(height: 80)
                    Text(app.name)
                        .font(.footnote)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
            }
            .contextMenu {
                contextMenu()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(app.name), \(isFavorite ? "Favorite" : "Not Favorite")")
        }
    }
}

// MARK: - Haptics helper

fileprivate enum Haptics {
    static func light() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}

// MARK: - Dummy NetworkManager Stub for Compilation

#if DEBUG
// Provide NetworkManager.shared stub only if NetworkManager is not imported to avoid compile errors
#if !canImport(NetworkManager)
public class NetworkManager {
    public static let shared: NetworkManager? = NetworkManager()

    public init() {}

    public func requestInstalledApps() async throws -> [MacAppInfo] {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000)
        return AppCatalogViewModel.demoApps()
    }

    public func sendLaunchApp(bundleIdentifier: String) {
        // no-op
    }

    public func sendQuitApp(bundleIdentifier: String) {
        // no-op
    }

    public func sendForceQuitApp(bundleIdentifier: String) {
        // no-op
    }

    public func sendActivateApp(bundleIdentifier: String) {
        // no-op
    }

    public func sendHideApp(bundleIdentifier: String) {
        // no-op
    }
}
#endif
#endif

// MARK: - Preview

#Preview {
    AppShortcutsView()
}
