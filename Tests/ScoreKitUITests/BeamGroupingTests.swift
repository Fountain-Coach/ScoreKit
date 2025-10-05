import XCTest
@testable import ScoreKitUI
import ScoreKit

final class BeamGroupingTests: XCTestCase {
    func testEighthsGroupWithinBeat() {
        // 4/4: two eighths per beat => 4 eighths should form two groups [0,1], [2,3]
        let events: [NotatedEvent] = [
            .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,8))),
            .init(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1,8))),
            .init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,8))),
            .init(base: .note(pitch: Pitch(step: .F, alter: 0, octave: 4), duration: Duration(1,8)))
        ]
        let r = SimpleRenderer()
        var opts = LayoutOptions(); opts.timeSignature = (4,4)
        let tree = r.layout(events: events, in: CGRect(x: 0, y: 0, width: 400, height: 160), options: opts)
        XCTAssertEqual(tree.beamGroups.count, 2)
        XCTAssertEqual(tree.beamGroups[0], [0,1])
        XCTAssertEqual(tree.beamGroups[1], [2,3])
    }

    func testSixteenthBeamLevels() {
        // 4/4: four 16ths in one beat should form one group with level >= 2
        let events: [NotatedEvent] = [
            .init(base: .note(pitch: Pitch(step: .G, alter: 0, octave: 4), duration: Duration(1,16))),
            .init(base: .note(pitch: Pitch(step: .A, alter: 0, octave: 4), duration: Duration(1,16))),
            .init(base: .note(pitch: Pitch(step: .B, alter: 0, octave: 4), duration: Duration(1,16))),
            .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 5), duration: Duration(1,16)))
        ]
        let r = SimpleRenderer()
        var opts = LayoutOptions(); opts.timeSignature = (4,4)
        let tree = r.layout(events: events, in: CGRect(x: 0, y: 0, width: 400, height: 160), options: opts)
        XCTAssertEqual(tree.beamGroups.count, 1)
        XCTAssertEqual(tree.beamGroups[0], [0,1,2,3])
        // beamLevels should indicate at least 2 between adjacent notes
        let level01 = min(tree.beamLevels[0], tree.beamLevels[1])
        let level12 = min(tree.beamLevels[1], tree.beamLevels[2])
        XCTAssertGreaterThanOrEqual(level01, 2)
        XCTAssertGreaterThanOrEqual(level12, 2)
    }
}

