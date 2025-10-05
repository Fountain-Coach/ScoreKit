import XCTest
@testable import ScoreKitUI
import ScoreKit

final class RendererLayoutTests: XCTestCase {
    func testLayoutPositionsAndHitTest() {
        let events: [NotatedEvent] = [
            .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1, 4))),
            .init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1, 4)), slurStart: true),
            .init(base: .note(pitch: Pitch(step: .G, alter: 0, octave: 4), duration: Duration(1, 4)), slurEnd: true),
            .init(base: .rest(duration: Duration(1, 4)))
        ]
        let r = SimpleRenderer()
        var opts = LayoutOptions(); opts.barIndices = [2]
        let tree = r.layout(events: events, in: CGRect(x: 0, y: 0, width: 400, height: 200), options: opts)
        XCTAssertEqual(tree.elements.count, 4)
        // ascending x positions
        XCTAssertLessThan(tree.elements[0].frame.minX, tree.elements[1].frame.minX)
        XCTAssertLessThan(tree.elements[1].frame.minX, tree.elements[2].frame.minX)
        // hit test near first note
        let p = CGPoint(x: tree.elements[0].frame.midXVal, y: tree.elements[0].frame.midYVal)
        let hit = r.hitTest(tree, at: p)
        XCTAssertEqual(hit?.index, 0)
        // slur captured
        XCTAssertEqual(tree.slurs.count, 1)
        XCTAssertEqual(tree.slurs[0].startIndex, 1)
        XCTAssertEqual(tree.slurs[0].endIndex, 2)
        // at least one barline present
        XCTAssertGreaterThanOrEqual(tree.barX.count, 1)
    }
}
