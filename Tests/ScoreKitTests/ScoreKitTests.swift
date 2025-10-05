import XCTest
@testable import ScoreKit

final class ScoreKitTests: XCTestCase {
    func testPositionInit() {
        let p = Position(measure: 1, beat: Beat(1, 4))
        XCTAssertEqual(p.measure, 1)
        XCTAssertEqual(p.beat.num, 1)
        XCTAssertEqual(p.beat.den, 4)
    }
}

