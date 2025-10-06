import XCTest
@testable import ScoreKitUI
import ScoreKit

final class MultiVoiceSlurTieTests: XCTestCase {
    func testSlurAndTiePerVoice() {
        let c4 = Pitch(step: .C, alter: 0, octave: 4)
        let d4 = Pitch(step: .D, alter: 0, octave: 4)
        let v0: [NotatedEvent] = [
            .init(base: .note(pitch: c4, duration: Duration(1,4)), slurStart: true),
            .init(base: .note(pitch: d4, duration: Duration(1,4)), slurEnd: true)
        ]
        let v1: [NotatedEvent] = [
            .init(base: .note(pitch: c4, duration: Duration(1,4)), tieStart: true),
            .init(base: .note(pitch: c4, duration: Duration(1,4)), tieEnd: true)
        ]
        let r = MultiRenderer()
        let t = r.layout(voices: [v0, v1], in: CGRect(x: 0, y: 0, width: 400, height: 200), options: LayoutOptions())
        XCTAssertEqual(t.slurs.count, 1)
        XCTAssertEqual(t.ties.count, 1)
        // Slur indices should refer to voice 0 region; tie to voice 1 region
        let sl = t.slurs[0]
        let ti = t.ties[0]
        XCTAssertLessThan(sl.startIndex, 2)
        XCTAssertGreaterThanOrEqual(ti.startIndex, 2)
    }
}

