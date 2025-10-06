import Foundation
import CoreText
import CoreGraphics
import ScoreKit

public enum SMuFL {
    // Fonts
    public static let fontCandidates: [String] = [
        "Bravura", "Petaluma", "Leland", "Emmentaler Text", "HelveticaNeue"
    ]

    public static func font(ofSize size: CGFloat) -> CTFont {
        for name in fontCandidates {
            let font = CTFontCreateWithName(name as CFString, size, nil)
            if CTFontGetSize(font) > 0 { return font }
        }
        return CTFontCreateWithName("HelveticaNeue" as CFString, size, nil)
    }

    // Clefs
    public static let trebleClef = "\u{E050}"
    public static let bassClef = "\u{E062}"

    // Accidentals
    public static func accidentalGlyph(for alter: Int) -> String {
        switch alter {
        case 2: return "\u{E263}" // double sharp
        case 1: return "\u{E262}" // sharp
        case -1: return "\u{E260}" // flat
        case -2: return "\u{E264}" // double flat
        default: return "\u{E261}" // natural
        }
    }

    // Time signature digits (0..9 -> U+E080..E089)
    public static func timeSigGlyph(digit: Int) -> String {
        let base: UInt32 = 0xE080
        let code = base + UInt32(max(0, min(9, digit)))
        return String(UnicodeScalar(code)!)
    }

    // Dynamics
    public static func dynamicsGlyphs(for level: DynamicLevel) -> [String] {
        func g(_ ch: Character) -> String {
            switch ch {
            case "m": return "\u{E521}"
            case "p": return "\u{E520}"
            case "f": return "\u{E522}"
            default: return String(ch)
            }
        }
        let seq: [Character]
        switch level {
        case .pp: seq = ["p","p"]
        case .p:  seq = ["p"]
        case .mp: seq = ["m","p"]
        case .mf: seq = ["m","f"]
        case .f:  seq = ["f"]
        case .ff: seq = ["f","f"]
        }
        return seq.map(g)
    }

    // Articulations
    public static func articulationGlyph(_ a: Articulation) -> String {
        switch a {
        case .staccato: return "\u{E4A2}"
        case .tenuto:   return "\u{E4A4}"
        case .accent:   return "\u{E4AC}"
        case .marcato:  return "\u{E4AE}"
        }
    }

    // Noteheads (duration denominators)
    public static func noteheadGlyph(forDen den: Int) -> String {
        if den == 1 { return "\u{E0A2}" }     // whole
        if den == 2 { return "\u{E0A3}" }     // half
        return "\u{E0A4}"                     // black (quarter and shorter)
    }

    // Rests (approximate mapping)
    public static func restGlyph(forDen den: Int) -> String {
        switch den {
        case 1: return "\u{E4E3}"
        case 2: return "\u{E4E4}"
        case 4: return "\u{E4E5}"
        case 8: return "\u{E4E6}"
        case 16: return "\u{E4E7}"
        case 32: return "\u{E4E8}"
        case 64: return "\u{E4E9}"
        default: return "\u{E4E5}"
        }
    }

    // Flags (number of flags -> glyph). Includes multi-tail glyphs when present.
    public static func flagGlyph(flags: Int, stemUp: Bool) -> String? {
        switch (flags, stemUp) {
        case (1, true): return "\u{E240}"
        case (2, true): return "\u{E242}"
        case (3, true): return "\u{E244}"
        case (4, true): return "\u{E246}"
        case (1, false): return "\u{E241}"
        case (2, false): return "\u{E243}"
        case (3, false): return "\u{E245}"
        case (4, false): return "\u{E247}"
        default: return nil
        }
    }
}

