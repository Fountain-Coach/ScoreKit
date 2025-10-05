import Foundation

public enum SemanticValue: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
}

public struct SemanticTag: Hashable, Codable, Sendable {
    public let key: String
    public let value: SemanticValue
    public init(_ key: String, _ value: SemanticValue) { self.key = key; self.value = value }
}
