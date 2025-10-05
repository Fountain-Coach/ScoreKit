import Foundation

public struct Beat: Equatable, Codable, Sendable {
    public let num: Int
    public let den: Int
    public init(_ num: Int, _ den: Int) {
        precondition(num > 0 && den > 0, "Beat must be positive")
        self.num = num; self.den = den
    }
}

public struct Position: Equatable, Codable, Sendable {
    public let measure: Int
    public let beat: Beat
    public init(measure: Int, beat: Beat) {
        precondition(measure >= 1, "Measure index is 1-based")
        self.measure = measure; self.beat = beat
    }
}

public enum Step: String, Codable, Sendable { case C, D, E, F, G, A, B }

public struct Pitch: Equatable, Hashable, Codable, Sendable {
    public let step: Step
    public let alter: Int // -1 flat, 0 natural, +1 sharp (can be >1 for double)
    public let octave: Int
    public init(step: Step, alter: Int = 0, octave: Int) { self.step = step; self.alter = alter; self.octave = octave }
}

public struct Duration: Equatable, Codable, Sendable {
    public let num: Int
    public let den: Int
    public init(_ num: Int, _ den: Int) {
        precondition(num > 0 && den > 0, "Duration must be positive")
        self.num = num; self.den = den
    }
}

public enum Event: Codable, Sendable {
    case note(pitch: Pitch, duration: Duration)
    case rest(duration: Duration)
}
