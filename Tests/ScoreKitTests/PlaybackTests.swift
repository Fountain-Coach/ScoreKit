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

    func testArticulationAffectsDurationAndVelocity() throws {
        let engine = PlaybackEngine()
        let sink = CollectingSink()
        let c4 = Pitch(step: .C, alter: 0, octave: 4)
        // Base event with mf
        let base = NotatedEvent(base: .note(pitch: c4, duration: Duration(1,4)), dynamic: .mf)
        // Staccato should shorten duration significantly
        let stacc = NotatedEvent(base: .note(pitch: c4, duration: Duration(1,4)), articulations: [.staccato], dynamic: .mf)
        try engine.schedule(events: [base, stacc], channel: 0, tempo: Tempo(bpm: 120), startTime: 0, sink: sink)
        // Scheduled messages: on/off for base, on/off for stacc
        XCTAssertEqual(sink.scheduled.count, 4)
        let baseOn = sink.scheduled[0]; let baseOff = sink.scheduled[1]
        let staccOn = sink.scheduled[2]; let staccOff = sink.scheduled[3]
        // Base quarter at 120 BPM = 0.5s
        XCTAssertEqual(baseOff.time - baseOn.time, 0.5, accuracy: 1e-6)
        // Staccato shortened to ~0.275s
        XCTAssertEqual(staccOff.time - staccOn.time, 0.275, accuracy: 1e-3)
        // Velocities: both > 0 and defined
        if case let .noteOn(_, _, v0) = baseOn.message, case let .noteOn(_, _, v1) = staccOn.message {
            XCTAssertGreaterThan(v0, 0)
            XCTAssertGreaterThan(v1, 0)
        } else { XCTFail("Expected noteOn messages") }
    }
}
