import XCTest
@testable import ScoreKit

final class LilySessionTests: XCTestCase {
    func testRenderWritesLyWithoutExec() throws {
        let ly = LilyEmitter.emit(events: [
            .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1, 4)),
            .rest(duration: Duration(1, 4)),
            .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1, 4))
        ], title: "ScoreKit Test")

        let artifacts = try LilySession().render(lySource: ly, execute: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.lyURL.path))
        XCTAssertNil(artifacts.pdfURL)
        XCTAssertTrue(artifacts.svgURLs.isEmpty)
    }

    func testExecIfAvailable() throws {
        guard ProcessInfo.processInfo.environment["SCOREKIT_RUN_LILYPOND_TESTS"] == "1" else {
            throw XCTSkip("Skipping lilypond exec test; set SCOREKIT_RUN_LILYPOND_TESTS=1 to enable.")
        }
        let ly = LilyEmitter.emit(events: [
            .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1, 4)),
        ], title: "Exec Test")
        let artifacts = try LilySession().render(lySource: ly, execute: true)
        XCTAssertNotNil(artifacts.pdfURL)
    }
}

