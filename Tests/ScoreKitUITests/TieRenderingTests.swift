import XCTest
@testable import ScoreKitUI
import ScoreKit

final class TieRenderingTests: XCTestCase {
    func testTieBetweenAdjacentNotes() {
        let c4 = Pitch(step: .C, alter: 0, octave: 4)
        let events: [NotatedEvent] = [
            .init(base: .note(pitch: c4, duration: Duration(1,4)), tieStart: true),
            .init(base: .note(pitch: c4, duration: Duration(1,4)), tieEnd: true)
        ]
        let r = SimpleRenderer()
        var opts = LayoutOptions(); opts.timeSignature = (4,4)
        let tree = r.layout(events: events, in: CGRect(x: 0, y: 0, width: 300, height: 160), options: opts)
        // A single tie is expected between 0 and 1
        XCTAssertEqual(tree.ties.count, 1)
        XCTAssertEqual(tree.ties[0].startIndex, 0)
        XCTAssertEqual(tree.ties[0].endIndex, 1)
    }
}

