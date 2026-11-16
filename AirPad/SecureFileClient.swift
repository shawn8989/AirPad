import Foundation
import Network
import Combine

struct RemoteFolder: Identifiable { let id: String; let name: String }
struct RemoteFile: Identifiable {
    let name: String
    let directory: Bool
    let size: Int64
    var id: String { name }
}
struct DownloadedFile: Identifiable { let id = UUID(); let url: URL }

@MainActor
final class RemoteFilesModel: ObservableObject {
    @Published var roots: [RemoteFolder] = []
    @Published var entries: [RemoteFile] = []
    @Published var selectedRoot: RemoteFolder?
    @Published var path = ""
    @Published var busy = false
    @Published var transferring = false
    @Published var progress: Double = 0
    @Published var status = ""
    @Published var error: String?
    @Published var more = false
    @Published var downloaded: DownloadedFile?
    @Published var canRetry = false
    private var task: Task<Void, Never>?
    private var retryAction: (() -> Void)?
    private var client: FileRPC?

    private func connection() async throws -> FileRPC {
        let config = try NetworkManager.shared.fileConfiguration()
        let rpc = FileRPC(config); client = rpc
        try await rpc.authenticate(config)
        return rpc
    }
    func loadRoots() {
        run {
            let rpc = try await self.connection(); defer { rpc.close() }
            let result = try await rpc.request(["op": "roots"])
            self.roots = (result["folders"] as? [[String: Any]] ?? []).compactMap {
                guard let id = $0["id"] as? String, let name = $0["name"] as? String else { return nil }
                return RemoteFolder(id: id, name: name)
            }
        }
    }
    func open(_ root: RemoteFolder) { selectedRoot = root; path = ""; loadDirectory() }
    func openDirectory(_ name: String) { path = path.isEmpty ? name : path + "/" + name; loadDirectory() }
    func goUp() {
        if path.isEmpty { selectedRoot = nil; entries = []; loadRoots() }
        else { path = (path as NSString).deletingLastPathComponent; loadDirectory() }
    }
    func loadDirectory(append: Bool = false) {
        guard let root = selectedRoot else { return }
        let currentPath = path
        let offset = append ? entries.count : 0
        run {
            let rpc = try await self.connection(); defer { rpc.close() }
            let result = try await rpc.request(["op": "list", "root": root.id, "path": currentPath, "offset": offset])
            let files = (result["entries"] as? [[String: Any]] ?? []).compactMap { value -> RemoteFile? in
                guard let name = value["name"] as? String, let directory = value["directory"] as? Bool else { return nil }
                return RemoteFile(name: name, directory: directory, size: (value["size"] as? NSNumber)?.int64Value ?? 0)
            }
            self.entries = append ? self.entries + files : files
            self.more = result["more"] as? Bool ?? false
        }
    }
    func download(_ file: RemoteFile) {
        guard let root = selectedRoot else { return }
        let remotePath = path.isEmpty ? file.name : path + "/" + file.name
        retryAction = { [weak self] in self?.download(file) }
        run(transfer: true) {
            let rpc = try await self.connection(); defer { rpc.close() }
            let reply = try await rpc.request(["op": "download", "root": root.id, "path": remotePath])
            guard let transferID = reply["transfer"] as? String, let number = reply["size"] as? NSNumber else { throw RemoteError.message("Invalid download response.") }
            let size = number.int64Value
            guard size >= 0, !file.name.contains("/"), file.name != ".", file.name != ".." else { throw RemoteError.message("Invalid file name.") }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Wield-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let temporary = directory.appendingPathComponent(".partial")
            FileManager.default.createFile(atPath: temporary.path, contents: nil)
            let handle = try FileHandle(forWritingTo: temporary)
            var completed = false
            defer { try? handle.close(); if !completed { try? FileManager.default.removeItem(at: directory) } }
            var received: Int64 = 0
            repeat {
                try Task.checkCancellation()
                let chunk = try await rpc.request(["op": "read", "transfer": transferID, "offset": received])
                guard let encoded = chunk["data"] as? String, let data = Data(base64Encoded: encoded), data.count <= 48 * 1024,
                      (chunk["offset"] as? NSNumber)?.int64Value == received + Int64(data.count),
                      received + Int64(data.count) <= size, !data.isEmpty || size == 0 else { throw RemoteError.message("Download interrupted. Retry from the beginning.") }
                try handle.write(contentsOf: data)
                received += Int64(data.count)
                self.progress = size == 0 ? 1 : Double(received) / Double(size)
                self.status = "Downloading \(file.name)"
            } while received < size
            try handle.synchronize(); try handle.close()
            let final = directory.appendingPathComponent(file.name)
            try FileManager.default.moveItem(at: temporary, to: final)
            completed = true
            self.downloaded = DownloadedFile(url: final)
            self.status = "Downloaded \(file.name). Use Share to save it to Files."
        }
    }
    func upload(_ url: URL) {
        guard let root = selectedRoot else { return }
        let currentPath = path
        retryAction = { [weak self] in self?.upload(url) }
        run(transfer: true) {
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize else { throw RemoteError.message("Choose an individual file.") }
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let rpc = try await self.connection(); defer { rpc.close() }
            let reply = try await rpc.request(["op": "upload", "root": root.id, "path": currentPath, "name": url.lastPathComponent, "size": size])
            guard let transferID = reply["transfer"] as? String else { throw RemoteError.message("Invalid upload response.") }
            var sent = 0
            while sent < size {
                try Task.checkCancellation()
                guard let data = try handle.read(upToCount: min(48 * 1024, size - sent)), !data.isEmpty else { throw RemoteError.message("The source file changed. Retry the upload.") }
                let result = try await rpc.request(["op": "write", "transfer": transferID, "offset": sent, "data": data.base64EncodedString()])
                sent += data.count
                guard (result["offset"] as? Int) == sent else { throw RemoteError.message("Upload interrupted. Please retry.") }
                self.progress = size == 0 ? 1 : Double(sent) / Double(size)
                self.status = "Uploading \(url.lastPathComponent)"
            }
            try Task.checkCancellation()
            let result = try await rpc.request(["op": "commit", "transfer": transferID])
            self.progress = 1
            self.status = "Saved as \(result["name"] as? String ?? url.lastPathComponent). Refresh to see it."
        }
    }
    func cancel() { task?.cancel(); client?.close() }
    func retry() { retryAction?() }
    private func run(transfer: Bool = false, operation: @escaping () async throws -> Void) {
        guard !busy else { return }
        error = nil; canRetry = false; busy = true; transferring = transfer; progress = 0
        task = Task {
            defer { self.busy = false; self.transferring = false; self.client?.close(); self.client = nil }
            do { try await operation() }
            catch {
                self.error = Task.isCancelled ? "Cancelled. Any incomplete upload will be removed by the Mac." : error.localizedDescription
                self.canRetry = transfer
            }
        }
    }
}
