import Foundation

public enum Articulation: Codable, Sendable, Equatable {
    case staccato
    case accent
}

public enum Hairpin: Codable, Sendable, Equatable {
    case crescendo
    case decrescendo
}

public enum DynamicLevel: String, Codable, Sendable, Equatable {
    case p, f, mp, mf, pp, ff
}

public struct NotatedEvent: Codable, Sendable {
    public var base: Event
    public var slurStart: Bool
    public var slurEnd: Bool
    public var articulations: [Articulation]
    public var hairpinStart: Hairpin?
    public var hairpinEnd: Bool
    public var dynamic: DynamicLevel?

    public init(base: Event,
                slurStart: Bool = false,
                slurEnd: Bool = false,
                articulations: [Articulation] = [],
                hairpinStart: Hairpin? = nil,
                hairpinEnd: Bool = false,
                dynamic: DynamicLevel? = nil) {
        self.base = base
        self.slurStart = slurStart
        self.slurEnd = slurEnd
        self.articulations = articulations
        self.hairpinStart = hairpinStart
        self.hairpinEnd = hairpinEnd
        self.dynamic = dynamic
    }
}

public struct Voice: Codable, Sendable {
    public var events: [NotatedEvent]
    public init(events: [NotatedEvent]) { self.events = events }
}

public enum PatchOp: Codable, Sendable {
    case slur(start: Int, end: Int)
    case hairpin(start: Int, end: Int, type: Hairpin)
    case articulation(index: Int, articulation: Articulation)
    case dynamic(index: Int, level: DynamicLevel)
}

public enum Transform {
    public static func addSlur(to voice: Voice, start: Int, end: Int) -> (Voice, [PatchOp]) {
        var v = voice
        guard start >= 0, end < v.events.count, start < end else { return (v, []) }
        v.events[start].slurStart = true
        v.events[end].slurEnd = true
        return (v, [.slur(start: start, end: end)])
    }

    public static func applyHairpin(to voice: Voice, start: Int, end: Int, type: Hairpin) -> (Voice, [PatchOp]) {
        var v = voice
        guard start >= 0, end < v.events.count, start < end else { return (v, []) }
        v.events[start].hairpinStart = type
        v.events[end].hairpinEnd = true
        return (v, [.hairpin(start: start, end: end, type: type)])
    }

    public static func addArticulation(to voice: Voice, index: Int, articulation: Articulation) -> (Voice, [PatchOp]) {
        var v = voice
        guard index >= 0, index < v.events.count else { return (v, []) }
        if !v.events[index].articulations.contains(where: { $0.kind == articulation.kind }) {
            v.events[index].articulations.append(articulation)
        }
        return (v, [.articulation(index: index, articulation: articulation)])
    }

    public static func setDynamic(to voice: Voice, index: Int, level: DynamicLevel) -> (Voice, [PatchOp]) {
        var v = voice
        guard index >= 0, index < v.events.count else { return (v, []) }
        v.events[index].dynamic = level
        return (v, [.dynamic(index: index, level: level)])
    }
}

private extension Articulation {
    var kind: String {
        switch self {
        case .staccato: return "staccato"
        case .accent: return "accent"
        }
    }
}
