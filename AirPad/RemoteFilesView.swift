import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct RemoteFilesView: View {
    @ObservedObject private var network = NetworkManager.shared
    @StateObject private var model = RemoteFilesModel()
    @State private var importing = false
    var body: some View {
        Group {
            if !network.isSecureConnection || !network.bridgeSupports(BridgeFeature.fileTransfer) {
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.questionmark").font(.largeTitle)
                    Text("Set up secure file access").font(.headline)
                    Text("Update Wield Host, scan its pairing QR, and choose the folders you want to share on your Mac.").multilineTextAlignment(.center)
                    NavigationLink("Access away from home") { RemoteAccessSetupView() }
                }.padding()
            } else {
                List {
                    if let root = model.selectedRoot {
                        Section {
                            Button("Up one level", systemImage: "arrow.up") { model.goUp() }.disabled(model.busy)
                            Text(root.name + (model.path.isEmpty ? "" : "/" + model.path)).font(.caption).foregroundStyle(.secondary)
                            ForEach(model.entries) { file in
                                Button {
                                    if file.directory { model.openDirectory(file.name) } else { model.download(file) }
                                } label: {
                                    HStack {
                                        Image(systemName: file.directory ? "folder" : "doc")
                                        Text(file.name).foregroundStyle(.primary)
                                        Spacer()
                                        if !file.directory { Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }.disabled(model.busy)
                            }
                            if model.more { Button("Load more") { model.loadDirectory(append: true) }.disabled(model.busy) }
                        }
                    } else {
                        Section("Shared folders") {
                            ForEach(model.roots) { root in Button(root.name, systemImage: "folder") { model.open(root) }.disabled(model.busy) }
                            if model.roots.isEmpty && !model.busy { Text("Choose folders in Wield Host on your Mac to make them available here.") }
                        }
                    }
                    if model.busy {
                        Section {
                            if model.transferring { ProgressView(value: model.progress); Text(model.status) }
                            else { ProgressView("Loading…") }
                            Button("Cancel", role: .cancel) { model.cancel() }
                        }
                    } else if !model.status.isEmpty { Text(model.status).font(.footnote) }
                    if let error = model.error {
                        Section {
                            Text(error).foregroundStyle(.red)
                            if model.canRetry { Button("Retry transfer") { model.retry() } }
                        }
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            if model.selectedRoot == nil { model.loadRoots() } else { model.loadDirectory() }
                        }.disabled(model.busy)
                        Button("Upload", systemImage: "square.and.arrow.up") { importing = true }
                            .disabled(model.selectedRoot == nil || model.busy)
                    }
                }
                .task { model.loadRoots() }
            }
        }
        .navigationTitle("Files")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            switch result { case .success(let url): model.upload(url); case .failure(let error): model.error = error.localizedDescription }
        }
        .sheet(item: $model.downloaded) { file in FileShareSheet(url: file.url) }
        .onDisappear { model.cancel() }
    }
}

private struct FileShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
