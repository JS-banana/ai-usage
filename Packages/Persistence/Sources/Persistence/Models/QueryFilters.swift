import Foundation

public struct QueryFilters: Hashable, Sendable {
    public let sourceIDs: [String]
    public let models: [String]
    public let projects: [String]
    public let startDate: Date?
    public let endDate: Date?

    public init(sourceIDs: [String] = [], models: [String] = [], projects: [String] = [], startDate: Date? = nil, endDate: Date? = nil) {
        self.sourceIDs = sourceIDs
        self.models = models
        self.projects = projects
        self.startDate = startDate
        self.endDate = endDate
    }
}
