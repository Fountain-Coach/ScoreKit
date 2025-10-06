import Foundation
import CoreGraphics
import ScoreKit

public struct MultiLayoutTree: Sendable {
    public let size: CGSize
    public let elements: [LayoutElement]
    public let barX: [CGFloat]
    public let voices: [Int] // parallel to elements
}

public struct MultiRenderer {
    public init() {}

    public func layout(voices vv: [[NotatedEvent]], in rect: CGRect, options: LayoutOptions) -> MultiLayoutTree {
        let staffHeight = options.staffSpacing * 4
        var width = options.padding.width * 2
        let height = options.padding.height * 2 + staffHeight + 40
        let origin = CGPoint(x: options.padding.width, y: options.padding.height)

        guard let v0 = vv.first, !v0.isEmpty else {
            return MultiLayoutTree(size: rect.size, elements: [], barX: [], voices: [])
        }

        // Compute x anchors from the first voice; align others to the same anchors.
        var anchorsX: [CGFloat] = []
        var cursorX: CGFloat = origin.x
        for e in v0 {
            anchorsX.append(cursorX)
            cursorX += advance(for: e)
            width = max(width, cursorX + options.padding.width)
        }

        var elements: [LayoutElement] = []
        var voices: [Int] = []
        var barX: [CGFloat] = []
        let beatsPerBar = max(1, options.timeSignature.beatsPerBar)
        let beatUnit = max(1, options.timeSignature.beatUnit)
        var beatsInBar = 0

        for (vi, v) in vv.enumerated() {
            var yCache: [Pitch: CGFloat] = [:]
            for i in 0..<min(v.count, anchorsX.count) {
                let e = v[i]
                let xBase = anchorsX[i]
                let x = vi == 0 ? xBase : (xBase + 6) // slight offset for upper/lower voice
                let y: CGFloat
                let frame: CGRect
                switch e.base {
                case let .note(p, d):
                    if let cached = yCache[p] { y = cached } else { let yy = trebleYOffset(for: p, staffSpacing: options.staffSpacing, originY: origin.y); yCache[p] = yy; y = yy }
                    frame = CGRect(x: x - 5, y: y - 5, width: 10, height: 10)
                    elements.append(LayoutElement(index: i, kind: .note(p, d), frame: frame))
                case .rest(let d):
                    y = origin.y + staffHeight/2 - 3
                    frame = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
                    elements.append(LayoutElement(index: i, kind: .rest, frame: frame))
                }
                voices.append(vi)
                let eb = beats(for: e, beatUnit: beatUnit)
                if vi == 0 { // compute barlines from primary voice
                    beatsInBar += eb
                    if beatsInBar >= beatsPerBar { barX.append(x + advance(for: e)); beatsInBar -= beatsPerBar }
                }
            }
        }

        return MultiLayoutTree(size: CGSize(width: max(rect.width, width), height: max(rect.height, height)), elements: elements, barX: barX, voices: voices)
    }

    // MARK: - Helpers (kept in sync with SimpleRenderer)
    private func trebleYOffset(for p: Pitch, staffSpacing: CGFloat, originY: CGFloat) -> CGFloat {
        let stepIndex: Int
        switch p.step { case .C: stepIndex = 0; case .D: stepIndex = 1; case .E: stepIndex = 2; case .F: stepIndex = 3; case .G: stepIndex = 4; case .A: stepIndex = 5; case .B: stepIndex = 6 }
        let diatonic = (p.octave - 4) * 7 + stepIndex
        let c4Y = originY + staffSpacing * 5
        let offset = -CGFloat(diatonic) * (staffSpacing / 2)
        return c4Y + offset
    }

    private func beats(for e: NotatedEvent, beatUnit: Int) -> Int {
        switch e.base {
        case .note(_, let d): return max(1, beatUnit / max(1, d.den))
        case .rest(let d): return max(1, beatUnit / max(1, d.den))
        }
    }

    private func advance(for e: NotatedEvent) -> CGFloat {
        let base: CGFloat = 24
        switch e.base {
        case .rest(let d), .note(_, let d):
            switch d.den {
            case 1: return base * 3.0
            case 2: return base * 2.0
            case 4: return base * 1.4
            case 8: return base * 1.1
            case 16: return base * 0.9
            default: return base
            }
        }
    }
}

