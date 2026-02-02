import Foundation

public struct MacDesktopInfo: Identifiable, Hashable {
    public let id: String         // stable identifier for space/desktop
    public let index: Int         // 1-based index in Mission Control order
    public var name: String?      // optional user-visible name
    public var isActive: Bool     // currently active desktop

    public init(id: String, index: Int, name: String? = nil, isActive: Bool = false) {
        self.id = id
        self.index = index
        self.name = name
        self.isActive = isActive
    }
}
