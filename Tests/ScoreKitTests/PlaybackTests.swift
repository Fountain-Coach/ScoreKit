import XCTest
@testable import ScoreKit

final class PlaybackTests: XCTestCase {
    func testSchedulingTimesAndVelocities() throws {
        let events: [NotatedEvent] = [
            .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,4)), hairpinStart: .crescendo, dynamic: .p),
            .init(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1,4))),
            .init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,4)), hairpinEnd: true, dynamic: .f)
        ]
        let engine = PlaybackEngine()
        let sink = CollectingSink()
        try engine.schedule(events: events, channel: 0, tempo: Tempo(bpm: 120), startTime: 0, sink: sink)
        // Expect 6 messages: on/off for each note
        XCTAssertEqual(sink.scheduled.count, 6)
        // Times: 0.0 on C, 0.5 off C, 0.5 on D, 1.0 off D, 1.0 on E, 1.5 off E
        let times = sink.scheduled.map { $0.time }
        XCTAssertEqual(times[0], 0.0, accuracy: 0.0001)
        XCTAssertEqual(times[1], 0.5, accuracy: 0.0001)
        XCTAssertEqual(times[2], 0.5, accuracy: 0.0001)
        XCTAssertEqual(times[3], 1.0, accuracy: 0.0001)
        XCTAssertEqual(times[4], 1.0, accuracy: 0.0001)
        XCTAssertEqual(times[5], 1.5, accuracy: 0.0001)
        // Velocities should ramp from p -> f
        func vel(_ idx: Int) -> UInt16 {
            if case let .noteOn(_, _, v) = sink.scheduled[idx].message { return v }; return 0
        }
        XCTAssertLessThan(vel(0), vel(2))
        XCTAssertLessThan(vel(2), vel(4))
    }
}
