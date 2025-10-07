import Foundation
import CoreGraphics
import ScoreKit

// Canonical staff coordinate mapping shared by renderers.
// - Staff origin (x: padding.left, y: padding.top) is the top staff line.
// - One staff line gap = `staffSpacing` points.
// - Diatonic step (line or space) maps to 0.5 * staffSpacing in device Y (y-down).

enum StaffCoords {
    // Device Y (y-down) using ScoreKit's public mapping
    static func y(for p: Pitch, clef: LayoutOptions.Clef, originY: CGFloat, staffSpacing: CGFloat) -> CGFloat {
        let c: ClefType = (clef == .treble) ? .treble : .bass
        let y = ScoreKit.StaffCoords.y(for: p, clef: c, originY: Double(originY), staffSpacing: Double(staffSpacing))
        return CGFloat(y)
    }
}
