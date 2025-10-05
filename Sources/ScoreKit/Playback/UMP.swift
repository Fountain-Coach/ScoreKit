import Foundation

public enum UMPMessage: Sendable, Equatable {
    case noteOn(channel: UInt8, key: UInt8, velocity: UInt16)
    case noteOff(channel: UInt8, key: UInt8, velocity: UInt16)
    case controlChange(channel: UInt8, controller: UInt8, value: UInt16)
}

public struct ScheduledUMP: Sendable, Equatable {
    public let time: TimeInterval // seconds relative to start
    public let message: UMPMessage
}

public protocol PlaybackSink: AnyObject {
    func schedule(_ items: [ScheduledUMP])
}

public final class CollectingSink: PlaybackSink {
    public private(set) var scheduled: [ScheduledUMP] = []
    public init() {}
    public func schedule(_ items: [ScheduledUMP]) { scheduled.append(contentsOf: items) }
}

