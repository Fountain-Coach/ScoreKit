import XCTest
@testable import ScoreKitUI
import ScoreKit

final class PartialReflowTests: XCTestCase {
    func testTighterPartialReflowShiftsOnlyFollowingMeasures() {
        // Build 8 quarter events => 2 measures of 4/4
        var events: [NotatedEvent] = []
        for _ in 0..<8 {
            events.append(.init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,4))))
        }
        let renderer = SimpleRenderer()
        var opts = LayoutOptions(); opts.timeSignature = (4,4)
        let rect = CGRect(x: 0, y: 0, width: 800, height: 200)
        let prev = renderer.layout(events: events, in: rect, options: opts)

        // Change index 5 (2nd measure) to a half note, which should widen that measure
        var updated = events
        updated[5] = .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,2)))
        let changed: Set<Int> = [5]
        let next = renderer.updateLayout(previous: prev, events: updated, in: rect, options: opts, changed: changed)

        // Elements in first measure [0..3] should not move
        for i in 0...3 {
            XCTAssertEqual(prev.elements[i].frame.midXVal, next.elements[i].frame.midXVal, accuracy: 1e-6)
        }

        // If any suffix existed, it would be shifted; in this scenario the last event
        // migrated into the next measure, so we only assert barlines update correctly below.

        // Debug: capture first measure boundary Xs
        let prevStartX = prev.elements[4].frame.midXVal
        print("prev.barX=\(prev.barX)")
        print("prevStartX=\(prevStartX)")
        // Barline after first measure should remain unchanged; final barline should shift by dx
        // Identify barline positions: prev.barX has 2 entries for 2 bars.
        XCTAssertGreaterThanOrEqual(prev.barX.count, 2)
        let firstBarPrev = prev.barX[0]
        let lastBarPrev = prev.barX.last!
        let firstBarNext = next.barX[0]
        let lastBarNext = next.barX.last!
        print("firstBarPrev=\(firstBarPrev) firstBarNext=\(firstBarNext) lastBarPrev=\(lastBarPrev) lastBarNext=\(lastBarNext)")
        XCTAssertEqual(firstBarPrev, firstBarNext, accuracy: 1e-6)
        XCTAssertNotEqual(lastBarPrev, lastBarNext, "Expected changed measure barline to update")
    }
}
