import Foundation

public enum SemanticsMap {
    public static func velocity(for dynamic: DynamicLevel?) -> UInt16 {
        // Map to 16-bit velocity for MIDI 2.0 (0..65535)
        let scale: Double
        switch dynamic {
        case .pp?: scale = 0.25
        case .p?: scale = 0.40
        case .mp?: scale = 0.55
        case .mf?: scale = 0.70
        case .f?: scale = 0.85
        case .ff?: scale = 1.00
        case nil: scale = 0.70
        }
        return UInt16((scale * 65535.0).rounded())
    }
}

