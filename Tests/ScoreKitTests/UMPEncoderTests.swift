import XCTest
@testable import ScoreKit

final class UMPEncoderTests: XCTestCase {
    func testMIDI1NoteOnWord() {
        let words = UMPEncoder.encode(.noteOn(channel: 1, key: 60, velocity: 65535), group: 0, mode: .midi1_32bit)
        XCTAssertEqual(words.count, 1)
        let w = words[0]
        // Expect MT=0x2, status=0x91, key=60, vel~127
        let b0 = UInt8((w >> 24) & 0xFF)
        let b1 = UInt8((w >> 16) & 0xFF)
        let b2 = UInt8((w >> 8) & 0xFF)
        let b3 = UInt8(w & 0xFF)
        XCTAssertEqual(b0, 0x20)
        XCTAssertEqual(b1, 0x91)
        XCTAssertEqual(b2, 60)
        XCTAssertGreaterThanOrEqual(b3, 120)
    }

    func testMIDI2NoteOnWords() {
        let words = UMPEncoder.encode(.noteOn(channel: 0, key: 64, velocity: 0x8000), group: 2, mode: .midi2_64bit)
        XCTAssertEqual(words.count, 2)
        let w1 = words[0]
        let w2 = words[1]
        let b0 = UInt8((w1 >> 24) & 0xFF)
        let b1 = UInt8((w1 >> 16) & 0xFF)
        let b2 = UInt8((w1 >> 8) & 0xFF)
        let b3 = UInt8(w1 & 0xFF)
        XCTAssertEqual(b0, 0x42) // MT=0x4, group=2
        XCTAssertEqual(b1, 0x90)
        XCTAssertEqual(b2, 64)
        XCTAssertEqual(b3, 0)
        // velocity 0x8000 at top 16 bits of word2
        XCTAssertEqual(UInt16((w2 >> 16) & 0xFFFF), 0x8000)
    }
}

