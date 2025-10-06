import XCTest
@testable import ScoreKit

final class ModelTransformTests: XCTestCase {
#if ENABLE_LILYPOND
    func testSlurTransformEmitsParens() throws {
        let base: [NotatedEvent] = [
            .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1, 4))),
            .init(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1, 4))),
            .init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1, 4)))
        ]
        let voice = Voice(events: base)
        let (v2, _) = Transform.addSlur(to: voice, start: 0, end: 2)
        let ly = LilyEmitter.emit(notated: v2.events, title: "Slur Test")
        print("SLUR_LY=\n\(ly)")
        XCTAssertTrue(ly.contains("c'4("))
        XCTAssertTrue(ly.contains("e'4)"))
    }

    func testHairpinTransformEmitsSpanners() throws {
        let base: [NotatedEvent] = [
            .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1, 4))),
            .init(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1, 4))),
            .init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1, 4)))
        ]
        let voice = Voice(events: base)
        let (v2, _) = Transform.applyHairpin(to: voice, start: 0, end: 2, type: .crescendo)
        let ly = LilyEmitter.emit(notated: v2.events, title: "Hairpin Test")
        print("HAIRPIN_LY=\n\(ly)")
        XCTAssertTrue(ly.contains("c'4 \\<"))
        XCTAssertTrue(ly.contains("e'4 \\!"))
    }

    func testArticulationTransformEmitsSuffix() throws {
        let base: [NotatedEvent] = [
            .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1, 4)))
        ]
        let voice = Voice(events: base)
        let (v2, _) = Transform.addArticulation(to: voice, index: 0, articulation: .staccato)
        let ly = LilyEmitter.emit(notated: v2.events, title: "Articulation Test")
        print("ARTIC_LY=\n\(ly)")
        XCTAssertTrue(ly.contains("c'4-."))
    }

    func testDynamicEmission() throws {
        let base: [NotatedEvent] = [
            .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1, 4)))
        ]
        let voice = Voice(events: base)
        let (v2, _) = Transform.setDynamic(to: voice, index: 0, level: .mf)
        let ly = LilyEmitter.emit(notated: v2.events, title: "Dynamic Test")
        XCTAssertTrue(ly.contains("\\mf c'4"))
    }
#else
    func testTransformsModifyModelFlags() throws {
        let base: [NotatedEvent] = [
            .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1, 4))),
            .init(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1, 4))),
            .init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1, 4)))
        ]
        let voice = Voice(events: base)
        let (v1, _) = Transform.addSlur(to: voice, start: 0, end: 2)
        XCTAssertTrue(v1.events[0].slurStart)
        XCTAssertTrue(v1.events[2].slurEnd)
        let (v2, _) = Transform.applyHairpin(to: v1, start: 0, end: 2, type: .crescendo)
        XCTAssertEqual(v2.events[0].hairpinStart, .crescendo)
        XCTAssertTrue(v2.events[2].hairpinEnd)
        let (v3, _) = Transform.addArticulation(to: v2, index: 1, articulation: .staccato)
        XCTAssertTrue(v3.events[1].articulations.contains(.staccato))
        let (v4, _) = Transform.setDynamic(to: v3, index: 0, level: .mf)
        XCTAssertEqual(v4.events[0].dynamic, .mf)
    }
#endif
}
