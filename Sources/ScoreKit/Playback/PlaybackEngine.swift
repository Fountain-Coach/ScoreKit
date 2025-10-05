import Foundation

public struct Tempo: Sendable, Equatable {
    public let bpm: Double // beats per minute, where beat = quarter note
    public init(bpm: Double) { self.bpm = bpm }
    public var secondsPerQuarter: Double { 60.0 / bpm }
}

public enum PlaybackError: Error { case empty }

public final class PlaybackEngine: Sendable {
    public init() {}

    /// Schedule note on/off messages for a simple monophonic voice of notated events.
    /// - Parameters:
    ///   - events: notated events (notes/rests) with dynamics and hairpins
    ///   - channel: MIDI channel (0..15)
    ///   - tempo: tempo (quarter BPM)
    ///   - startTime: start time offset in seconds (usually 0)
    ///   - sink: receiver for scheduled UMP messages
    public func schedule(events: [NotatedEvent], channel: UInt8 = 0, tempo: Tempo, startTime: TimeInterval = 0, sink: PlaybackSink) throws {
        guard !events.isEmpty else { throw PlaybackError.empty }
        // Precompute linear hairpin dynamic ramps across ranges
        let dyns = effectiveDynamics(events: events)
        var t = startTime
        var scheduled: [ScheduledUMP] = []
        for (i, e) in events.enumerated() {
            switch e.base {
            case let .note(p, d):
                let key = midiFrom(pitch: p)
                let vel = SemanticsMap.velocity(for: dyns[i])
                scheduled.append(.init(time: t, message: .noteOn(channel: channel, key: key, velocity: vel)))
                let durSec = seconds(for: d, tempo: tempo)
                scheduled.append(.init(time: t + durSec, message: .noteOff(channel: channel, key: key, velocity: 0)))
                t += durSec
            case let .rest(d):
                t += seconds(for: d, tempo: tempo)
            }
        }
        sink.schedule(scheduled)
    }

    private func seconds(for d: Duration, tempo: Tempo) -> TimeInterval {
        // Duration is num/den of whole note; quarter = 1/4.
        let quarters = (Double(d.num) / Double(d.den)) * 4.0
        return quarters * tempo.secondsPerQuarter
    }

    private func midiFrom(pitch: Pitch) -> UInt8 {
        // Middle C (C4) = 60
        let base: Int
        switch pitch.step { case .C: base = 0; case .D: base = 2; case .E: base = 4; case .F: base = 5; case .G: base = 7; case .A: base = 9; case .B: base = 11 }
        let semitone = (pitch.octave - 4) * 12 + base + pitch.alter
        let note = 60 + semitone
        return UInt8(max(0, min(127, note)))
    }

    private func effectiveDynamics(events: [NotatedEvent]) -> [DynamicLevel?] {
        var result = events.map { $0.dynamic }
        // Handle hairpins by distributing dynamics between explicit anchors
        var i = 0
        while i < events.count {
            if let startDyn = events[i].dynamic ?? result[i], events[i].hairpinStart != nil {
                if let endIdx = events[(i+1)...].firstIndex(where: { $0.hairpinEnd }) {
                    let endDyn = events[endIdx].dynamic ?? startDyn
                    // Compute ramp between i..endIdx inclusive
                    let steps = max(1, endIdx - i)
                    for k in 0...steps {
                        let t = Double(k) / Double(steps)
                        let from = SemanticsMap.velocity(for: startDyn)
                        let to = SemanticsMap.velocity(for: endDyn)
                        let lerp = UInt16(Double(from) * (1.0 - t) + Double(to) * t)
                        // Map back to nearest dynamic approximation; keep as mf if unknown
                        result[i + k] = nearestDynamic(to: lerp)
                    }
                    i = endIdx + 1
                    continue
                }
            }
            i += 1
        }
        return result
    }

    private func nearestDynamic(to velocity: UInt16) -> DynamicLevel {
        // Heuristic map to the closest defined dynamic
        let pairs: [(DynamicLevel, UInt16)] = [
            (.pp, SemanticsMap.velocity(for: .pp)),
            (.p, SemanticsMap.velocity(for: .p)),
            (.mp, SemanticsMap.velocity(for: .mp)),
            (.mf, SemanticsMap.velocity(for: .mf)),
            (.f, SemanticsMap.velocity(for: .f)),
            (.ff, SemanticsMap.velocity(for: .ff))
        ]
        return pairs.min(by: { abs(Int($0.1) - Int(velocity)) < abs(Int($1.1) - Int(velocity)) })!.0
    }
}

