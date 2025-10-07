import Foundation
import CoreGraphics
import ScoreKit

// Canonical staff coordinate mapping shared by renderers.
// - Staff origin (x: padding.left, y: padding.top) is the top staff line.
// - One staff line gap = `staffSpacing` points.
// - Diatonic step (line or space) maps to 0.5 * staffSpacing in device Y (y-down).

enum StaffCoords {
    // Diatonic index DI = 7*octave + stepIndex (C=0..B=6)
    static func diatonicIndex(_ p: Pitch) -> Int {
        let stepIndex: Int
        switch p.step { case .C: stepIndex = 0; case .D: stepIndex = 1; case .E: stepIndex = 2; case .F: stepIndex = 3; case .G: stepIndex = 4; case .A: stepIndex = 5; case .B: stepIndex = 6 }
        return p.octave * 7 + stepIndex
    }

    // Top-line diatonic index per clef
    static func topLineDI(for clef: LayoutOptions.Clef) -> Int {
        switch clef {
        case .treble:
            // Treble top line = F5 (oct 5, step F=3) -> 5*7+3 = 38
            return 38
        case .bass:
            // Bass top line = A3 (oct 3, step A=5) -> 3*7+5 = 26
            return 26
        }
    }

    // Device Y (y-down) for a pitch on a staff with given originY and spacing
    static func y(for p: Pitch, clef: LayoutOptions.Clef, originY: CGFloat, staffSpacing: CGFloat) -> CGFloat {
        let di = diatonicIndex(p)
        let top = topLineDI(for: clef)
        let pos = top - di // diatonic steps from top line
        return originY + CGFloat(pos) * (staffSpacing / 2)
    }
}

