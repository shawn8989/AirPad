import Foundation
import UIKit

// Model representing an open window on the Mac.
public struct MacWindowInfo: Identifiable, Hashable {
    public let id: String                 // window identifier (agent-defined, stable for focusing)
    public var title: String
    public var appBundleIdentifier: String
    public var appName: String
    public var isMinimized: Bool
    public var isOnScreen: Bool
    public var space: Int?
    public var ownerPID: Int?
    public var appIcon: UIImage?

    public init(id: String,
                title: String,
                appBundleIdentifier: String,
                appName: String,
                isMinimized: Bool = false,
                isOnScreen: Bool = true,
                space: Int? = nil,
                ownerPID: Int? = nil,
                appIcon: UIImage? = nil) {
        self.id = id
        self.title = title
        self.appBundleIdentifier = appBundleIdentifier
        self.appName = appName
        self.isMinimized = isMinimized
        self.isOnScreen = isOnScreen
        self.space = space
        self.ownerPID = ownerPID
        self.appIcon = appIcon
    }
}
