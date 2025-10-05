import Foundation

public enum LilyParser {
    public static func parse(source: String) -> [NotatedEvent] {
        // Tokenize by whitespace, keep punctuation attached for simple cases.
        // Handle dynamics (\\p, \\mf), hairpins (\\<, \\>, \\!), and braces are ignored.
        var events: [NotatedEvent] = []
        var pendingDynamic: DynamicLevel? = nil
        // Remove comments (% to end-of-line) and braces
        let cleaned: String = source
            .components(separatedBy: .newlines)
            .map { line in
                if let i = line.firstIndex(of: "%") { return String(line[..<i]) }
                return line
            }
            .joined(separator: " ")
            .replacingOccurrences(of: "{", with: " ")
            .replacingOccurrences(of: "}", with: " ")
        let tokens = cleaned.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        var lastTiePending: (idx: Int, pitch: Pitch)? = nil
        for tok in tokens {
            if tok.hasPrefix("%") { continue } // comment
            if tok.hasPrefix("\\header") { continue }
            if tok == "\\!" { // end hairpin on previous event
                if let last = events.indices.last { events[last].hairpinEnd = true }
                continue
            }
            if tok == "\\<" { // start crescendo on previous event
                if let last = events.indices.last { events[last].hairpinStart = .crescendo }
                continue
            }
            if tok == "\\>" { // start decrescendo on previous event
                if let last = events.indices.last { events[last].hairpinStart = .decrescendo }
                continue
            }
            if tok.hasPrefix("\\") {
                // dynamics
                switch tok {
                case "\\pp": pendingDynamic = .pp
                case "\\p": pendingDynamic = .p
                case "\\mp": pendingDynamic = .mp
                case "\\mf": pendingDynamic = .mf
                case "\\f": pendingDynamic = .f
                case "\\ff": pendingDynamic = .ff
                default: break
                }
                continue
            }
            // Notes or rests with optional duration and articulations/slurs
            if tok.first == "r" {
                let (dur, hasSlurStart, hasSlurEnd) = parseDurationAndSuffixes(from: String(tok.dropFirst()))
                var ev = NotatedEvent(base: .rest(duration: dur ?? Duration(1, 4)))
                ev.slurStart = hasSlurStart
                ev.slurEnd = hasSlurEnd
                if let dyn = pendingDynamic { ev.dynamic = dyn; pendingDynamic = nil }
                events.append(ev)
                continue
            }
            if let stepChar = tok.first, "cdefgab".contains(stepChar) {
                // parse pitch spelling
                var idx = tok.startIndex
                let step = Step(from: stepChar)
                idx = tok.index(after: idx)
                var alter = 0
                var octaveDelta = 0
                // accidentals: is/es sequences
                while tok[idx...].hasPrefix("is") || tok[idx...].hasPrefix("es") {
                    if tok[idx...].hasPrefix("is") { alter += 1; idx = tok.index(idx, offsetBy: 2) }
                    else { alter -= 1; idx = tok.index(idx, offsetBy: 2) }
                }
                // octave marks: ' or , repeated
                while idx < tok.endIndex, tok[idx] == "'" || tok[idx] == "," {
                    if tok[idx] == "'" { octaveDelta += 1 } else { octaveDelta -= 1 }
                    idx = tok.index(after: idx)
                }
                // duration and suffixes from remaining string
                let rest = String(tok[idx...])
                let (dur, hasSlurStart, hasSlurEnd, hasTie, arts) = parseDurSlurArt(from: rest)
                let octave = 3 + octaveDelta
                let pitch = Pitch(step: step, alter: alter, octave: octave)
                var ev = NotatedEvent(base: .note(pitch: pitch, duration: dur ?? Duration(1, 4)))
                ev.slurStart = hasSlurStart
                ev.slurEnd = hasSlurEnd
                ev.tieStart = hasTie
                ev.articulations = arts
                if let dyn = pendingDynamic { ev.dynamic = dyn; pendingDynamic = nil }
                if let pending = lastTiePending, pending.pitch == pitch {
                    events[pending.idx].tieStart = true
                    ev.tieEnd = true
                    lastTiePending = nil
                }
                if hasTie { lastTiePending = (events.count, pitch) }
                events.append(ev)
                continue
            }
        }
        return events
    }

    private static func parseDurationAndSuffixes(from s: String) -> (Duration?, Bool, Bool) {
        // find leading digits for denominator, detect slur '(' or ')' in suffix
        var i = s.startIndex
        var digits = ""
        while i < s.endIndex && s[i].isNumber { digits.append(s[i]); i = s.index(after: i) }
        let den = Int(digits)
        var hasStart = false
        var hasEnd = false
        if s[i...].contains("(") { hasStart = true }
        if s[i...].contains(")") { hasEnd = true }
        let dur = den != nil ? Duration(1, den!) : nil
        return (dur, hasStart, hasEnd)
    }

    private static func parseDurSlurArt(from s: String) -> (Duration?, Bool, Bool, Bool, [Articulation]) {
        var i = s.startIndex
        var digits = ""
        while i < s.endIndex && s[i].isNumber { digits.append(s[i]); i = s.index(after: i) }
        let den = Int(digits)
        var hasStart = false
        var hasEnd = false
        var hasTie = false
        var arts: [Articulation] = []
        let suffix = String(s[i...])
        if suffix.contains("(") { hasStart = true }
        if suffix.contains(")") { hasEnd = true }
        if suffix.contains("-.") { arts.append(.staccato) }
        if suffix.contains("->") { arts.append(.accent) }
        if suffix.contains("-^") { arts.append(.marcato) }
        if suffix.contains("-_") { arts.append(.tenuto) }
        if suffix.contains("~") { hasTie = true }
        let dur = den != nil ? Duration(1, den!) : nil
        return (dur, hasStart, hasEnd, hasTie, arts)
    }
}

private extension Step {
    init(from ch: Character) {
        switch ch { case "c": self = .C; case "d": self = .D; case "e": self = .E; case "f": self = .F; case "g": self = .G; case "a": self = .A; default: self = .B }
    }
}
