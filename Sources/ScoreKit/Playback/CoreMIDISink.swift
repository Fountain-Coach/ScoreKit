import Foundation

#if canImport(CoreMIDI)
import CoreMIDI
import CoreAudio

public final class CoreMIDISink: PlaybackSink {
    private let sender: CoreMIDISender
    private let destinationIndex: Int
    private let baseHostTime: UInt64

    public init?(destinationIndex: Int = 0) {
        guard let s = CoreMIDISender() else { return nil }
        self.sender = s
        self.destinationIndex = destinationIndex
        self.baseHostTime = AudioGetCurrentHostTime()
    }

    public func schedule(_ items: [ScheduledUMP]) {
        // Convert scheduled messages to timestamped UMP words and send as one event list
        guard sender.destinationCount() > 0 else { return }
        var scheduled: [(timeStamp: UInt64, words: [UInt32])] = []
        scheduled.reserveCapacity(items.count)
        for it in items {
            let words = UMPEncoder.encode(it.message, group: 0, mode: .midi2_64bit)
            let nanos = UInt64(max(0, it.time) * 1_000_000_000.0)
            let ts: UInt64 = baseHostTime &+ AudioConvertNanosToHostTime(nanos)
            scheduled.append((timeStamp: ts, words: words))
        }
        sender.sendScheduledUMP(scheduled, to: destinationIndex)
    }
}
#else
public final class CoreMIDISink: PlaybackSink {
    public init?(destinationIndex: Int = 0) { return nil }
    public func schedule(_ items: [ScheduledUMP]) { /* no-op */ }
}
#endif
