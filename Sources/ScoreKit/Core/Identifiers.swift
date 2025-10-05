import Foundation

public struct ScoreID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = .init()) { self.rawValue = rawValue }
}

public protocol ScoreNode: Sendable {
    var id: ScoreID { get }
    var tags: [SemanticTag] { get }
}

