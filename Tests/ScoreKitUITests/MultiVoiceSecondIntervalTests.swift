import XCTest
@testable import ScoreKitUI
import ScoreKit

final class MultiVoiceSecondIntervalTests: XCTestCase {
    func testSecondIntervalSplit() {
        let c4 = Pitch(step: .C, alter: 0, octave: 4)
        let d4 = Pitch(step: .D, alter: 0, octave: 4)
        let v0: [NotatedEvent] = [ .init(base: .note(pitch: c4, duration: Duration(1,4))) ]
        let v1: [NotatedEvent] = [ .init(base: .note(pitch: d4, duration: Duration(1,4))) ]
        let r = MultiRenderer()
        let t = r.layout(voices: [v0, v1], in: CGRect(x: 0, y: 0, width: 300, height: 160), options: LayoutOptions())
        // Fetch elements for index 0 voice 0 and voice 1
        var a: LayoutElement?; var b: LayoutElement?
        a = nil; b = nil
        for el in t.elements.enumerated() {
            if t.voices[el.offset] == 0 && el.element.index == 0 { a = el.element }
            if t.voices[el.offset] == 1 && el.element.index == 0 { b = el.element }
        }
        guard let a0 = a, let b0 = b else { XCTFail("Missing elements"); return }
        let dx = abs(b0.frame.midXVal - a0.frame.midXVal)
        XCTAssertGreaterThan(dx, 6.0)
        XCTAssertLessThan(dx, 12.0)
    }
}

