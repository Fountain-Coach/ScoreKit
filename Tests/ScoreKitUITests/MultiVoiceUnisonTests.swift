import XCTest
@testable import ScoreKitUI
import ScoreKit

final class MultiVoiceUnisonTests: XCTestCase {
    func testUnisonSplitHeads() {
        let c4 = Pitch(step: .C, alter: 0, octave: 4)
        let d4 = Pitch(step: .D, alter: 0, octave: 4)
        let e4 = Pitch(step: .E, alter: 0, octave: 4)
        let v0: [NotatedEvent] = [
            .init(base: .note(pitch: c4, duration: Duration(1,4))),
            .init(base: .note(pitch: d4, duration: Duration(1,4)))
        ]
        let v1: [NotatedEvent] = [
            .init(base: .note(pitch: c4, duration: Duration(1,4))), // unison at index 0
            .init(base: .note(pitch: e4, duration: Duration(1,4)))
        ]
        let r = MultiRenderer()
        let t = r.layout(voices: [v0, v1], in: CGRect(x: 0, y: 0, width: 400, height: 200), options: LayoutOptions())
        // Helper to find element by voice/index
        func elem(_ voice: Int, _ idx: Int) -> LayoutElement? {
            for k in 0..<t.elements.count where t.voices[k] == voice && t.elements[k].index == idx { return t.elements[k] }
            return nil
        }
        guard let a0 = elem(0, 0), let b0 = elem(1, 0), let a1 = elem(0, 1), let b1 = elem(1, 1) else {
            XCTFail("Missing elements"); return
        }
        // Unison pair split: small symmetric separation around anchor (~8 px total)
        let dx0 = abs(b0.frame.midXVal - a0.frame.midXVal)
        XCTAssertGreaterThan(dx0, 6.0)
        XCTAssertLessThan(dx0, 12.0)
        // Non-unison pair uses default larger offset (~9 px), allow similar band
        let dx1 = abs(b1.frame.midXVal - a1.frame.midXVal)
        XCTAssertGreaterThan(dx1, 6.0)
        XCTAssertLessThan(dx1, 14.0)
    }
}

