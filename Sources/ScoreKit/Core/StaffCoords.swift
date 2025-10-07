import Foundation

// Public, canonical staff coordinate mapping usable by external renderers.
public enum StaffCoords {
    static func diatonicIndex(_ p: Pitch) -> Int {
        let stepIndex: Int
        switch p.step { case .C: stepIndex = 0; case .D: stepIndex = 1; case .E: stepIndex = 2; case .F: stepIndex = 3; case .G: stepIndex = 4; case .A: stepIndex = 5; case .B: stepIndex = 6 }
        return p.octave * 7 + stepIndex
    }

    static func topLineDI(for clef: ClefType) -> Int {
        switch clef {
        case .treble: return 38 // F5
        case .bass: return 26   // A3
        }
    }

    // Device Y (y-down) for a pitch on a staff with given originY and spacing (Double-precision API)
    public static func y(for p: Pitch, clef: ClefType, originY: Double, staffSpacing: Double) -> Double {
        let di = diatonicIndex(p)
        let top = topLineDI(for: clef)
        let pos = top - di // diatonic steps from top line
        return originY + Double(pos) * (staffSpacing / 2.0)
    }
}

