import Foundation

#if canImport(CoreMIDI)
import CoreMIDI

public final class CoreMIDISender {
    private var client = MIDIClientRef()
    private var outPort = MIDIPortRef()
    public init?(clientName: String = "ScoreKit", portName: String = "ScoreKit Out") {
        var c = MIDIClientRef()
        let s1 = MIDIClientCreateWithBlock(clientName as CFString, &c) { _ in }
        guard s1 == noErr else { return nil }
        var p = MIDIPortRef()
        let s2 = MIDIOutputPortCreate(c, portName as CFString, &p)
        guard s2 == noErr else { MIDIClientDispose(c); return nil }
        self.client = c; self.outPort = p
    }
    deinit { MIDIPortDispose(outPort); MIDIClientDispose(client) }

    public func destinationCount() -> Int { Int(MIDIGetNumberOfDestinations()) }
    public func destinationName(at index: Int) -> String? {
        let dest = MIDIGetDestination(index)
        var prop: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(dest, kMIDIPropertyName, &prop) == noErr {
            return prop?.takeRetainedValue() as String?
        }
        return nil
    }

    public func sendUMP(words: [UInt32], to index: Int = 0) {
        guard destinationCount() > 0 else { return }
        let dest = MIDIGetDestination(index)
        // Build a MIDIEventList for UMP (MIDI 2.0)
        var storage = [UInt8](repeating: 0, count: 256)
        storage.withUnsafeMutableBytes { raw in
            let listPtr = raw.baseAddress!.assumingMemoryBound(to: MIDIEventList.self)
            var packet = MIDIEventListInit(listPtr, ._2_0)
            _ = words.withUnsafeBufferPointer { wbuf in
                MIDIEventListAdd(listPtr, 256, packet, 0, wbuf.count, wbuf.baseAddress!)
            }
            MIDISendEventList(outPort, dest, listPtr)
        }
    }

    public func sendScheduledUMP(_ items: [(timeStamp: UInt64, words: [UInt32])], to index: Int = 0) {
        guard destinationCount() > 0, !items.isEmpty else { return }
        let dest = MIDIGetDestination(index)
        let cap = max(1024, items.count * 64)
        var storage = [UInt8](repeating: 0, count: cap)
        storage.withUnsafeMutableBytes { raw in
            let listPtr = raw.baseAddress!.assumingMemoryBound(to: MIDIEventList.self)
            var packet = MIDIEventListInit(listPtr, ._2_0)
            for it in items {
                _ = it.words.withUnsafeBufferPointer { wbuf in
                    MIDIEventListAdd(listPtr, cap, packet, it.timeStamp, wbuf.count, wbuf.baseAddress!)
                }
            }
            MIDISendEventList(outPort, dest, listPtr)
        }
    }
}

#else
public final class CoreMIDISender {
    public init?(clientName: String = "ScoreKit", portName: String = "ScoreKit Out") { return nil }
    public func destinationCount() -> Int { 0 }
    public func destinationName(at index: Int) -> String? { nil }
    public func sendUMP(words: [UInt32], to index: Int = 0) { /* no-op */ }
}
#endif
