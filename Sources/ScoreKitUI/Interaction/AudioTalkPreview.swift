import Foundation
import ScoreKit

/// Lightweight session to apply AI-generated PatchOps to events
/// and report changed indices for incremental reflow + highlight.
@MainActor
public final class AudioTalkPreviewSession {
    public private(set) var events: [NotatedEvent]

    public init(events: [NotatedEvent]) { self.events = events }

    /// Apply a batch of PatchOps and return (newEvents, changedIndices)
    public func apply(ops: [PatchOp]) -> ([NotatedEvent], Set<Int>) {
        var changed: Set<Int> = []
        var voice = Voice(events: events)
        for op in ops {
            switch op {
            case .slur(let s, let e):
                let (nv, _) = Transform.addSlur(to: voice, start: s, end: e)
                voice = nv
                changed.formUnion([s, e])
            case .hairpin(let s, let e, let t):
                let (nv, _) = Transform.applyHairpin(to: voice, start: s, end: e, type: t)
                voice = nv
                changed.formUnion(Set(s...e))
            case .articulation(let i, let a):
                let (nv, _) = Transform.addArticulation(to: voice, index: i, articulation: a)
                voice = nv
                changed.insert(i)
            case .dynamic(let i, let lvl):
                let (nv, _) = Transform.setDynamic(to: voice, index: i, level: lvl)
                voice = nv
                changed.insert(i)
            }
        }
        events = voice.events
        return (events, changed)
    }
}

