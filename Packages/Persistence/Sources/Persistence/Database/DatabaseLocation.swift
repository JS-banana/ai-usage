import Foundation

public struct DatabaseLocation: Hashable, Sendable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}
