import Foundation

public struct DailyBucketRecord: Identifiable, Hashable, Sendable {
    public let id: String
    public let sourceID: String
    public let bucketDate: Date
    public let totalTokens: Int
    public let sessionCount: Int

    public init(id: String, sourceID: String, bucketDate: Date, totalTokens: Int, sessionCount: Int) {
        self.id = id
        self.sourceID = sourceID
        self.bucketDate = bucketDate
        self.totalTokens = totalTokens
        self.sessionCount = sessionCount
    }
}
