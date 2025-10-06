import XCTest
@testable import ScoreKitUI
import ScoreKit

final class MultiVoiceTests: XCTestCase {
    func testTwoVoicesAlignedQuartersOffset() {
        // Voice 0: C4..F4, Voice 1: E4..A4, same quarters
        let v0: [NotatedEvent] = [
            .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,4))),
            .init(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1,4))),
            .init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,4))),
            .init(base: .note(pitch: Pitch(step: .F, alter: 0, octave: 4), duration: Duration(1,4)))
        ]
        let v1: [NotatedEvent] = [
            .init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,4))),
            .init(base: .note(pitch: Pitch(step: .F, alter: 0, octave: 4), duration: Duration(1,4))),
            .init(base: .note(pitch: Pitch(step: .G, alter: 0, octave: 4), duration: Duration(1,4))),
            .init(base: .note(pitch: Pitch(step: .A, alter: 0, octave: 4), duration: Duration(1,4)))
        ]
        let r = MultiRenderer()
        let opts = LayoutOptions()
        let t = r.layout(voices: [v0, v1], in: CGRect(x: 0, y: 0, width: 600, height: 200), options: opts)
        // Expect 8 elements total and same-time x alignment with slight offset for voice 1
        XCTAssertEqual(t.elements.count, 8)
        // Compare first pair (indices 0 and 4 in flattened order)
        let x0 = t.elements[0].frame.midXVal
        let x1 = t.elements[4].frame.midXVal
        XCTAssertGreaterThan(x1, x0)
        XCTAssertLessThan(x1 - x0, 10.0)
    }
}

