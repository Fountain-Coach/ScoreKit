import Foundation
import CoreGraphics
import ScoreKit

public struct MultiLayoutTree: Sendable {
    public let size: CGSize
    public let elements: [LayoutElement]
    public let barX: [CGFloat]
    public let voices: [Int] // parallel to elements
    public let slurs: [LayoutSlur]
    public let ties: [LayoutTie]
}

public struct MultiRenderer {
    public init() {}

    public func layout(voices vv: [[NotatedEvent]], in rect: CGRect, options: LayoutOptions) -> MultiLayoutTree {
        let staffHeight = options.staffSpacing * 4
        var width = options.padding.width * 2
        let height = options.padding.height * 2 + staffHeight + 40
        let origin = CGPoint(x: options.padding.width, y: options.padding.height)

        guard let v0 = vv.first, !v0.isEmpty else {
            return MultiLayoutTree(size: rect.size, elements: [], barX: [], voices: [], slurs: [], ties: [])
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
        var indexMap: [[Int]] = vv.map { _ in Array(repeating: -1, count: anchorsX.count) }
        let beatsPerBar = max(1, options.timeSignature.beatsPerBar)
        let beatUnit = max(1, options.timeSignature.beatUnit)
        var beatsInBar = 0

        // Precompute per-voice, per-index horizontal offsets for unisons (two voices only for now)
        var offsets: [[CGFloat]] = vv.map { _ in Array(repeating: 0, count: anchorsX.count) }
        if vv.count >= 2 {
            let m = min(vv[0].count, vv[1].count, anchorsX.count)
            for i in 0..<m {
                switch (vv[0][i].base, vv[1][i].base) {
                case (.note(let p0, _), .note(let p1, _)) where p0.step == p1.step && p0.alter == p1.alter && p0.octave == p1.octave:
                    // Unison: split heads left/right around anchor
                    offsets[0][i] = -4
                    offsets[1][i] = +4
                default:
                    // Default separation: voice 1 nudged right
                    offsets[1][i] = +9
                }
            }
        }

        for (vi, v) in vv.enumerated() {
            var yCache: [Pitch: CGFloat] = [:]
            for i in 0..<min(v.count, anchorsX.count) {
                let e = v[i]
                let xBase = anchorsX[i]
                let defaultOffset: CGFloat = (vi == 0 ? 0 : 9)
                let off = (vi < offsets.count && i < offsets[vi].count) ? offsets[vi][i] : defaultOffset
                let x = xBase + off
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
                indexMap[vi][i] = elements.count - 1
                let eb = beats(for: e, beatUnit: beatUnit)
                if vi == 0 { // compute barlines from primary voice
                    beatsInBar += eb
                    if beatsInBar >= beatsPerBar { barX.append(x + advance(for: e)); beatsInBar -= beatsPerBar }
                }
            }
        }
        // Build slurs and ties per voice mapped to flattened indices
        var slurs: [LayoutSlur] = []
        var ties: [LayoutTie] = []
        for vi in 0..<vv.count {
            let v = vv[vi]
            for i in 0..<min(v.count, anchorsX.count) {
                if v[i].slurStart, let end = v[(i+1)...].firstIndex(where: { $0.slurEnd }) {
                    let a = indexMap[vi][i], b = indexMap[vi][end]
                    if a >= 0, b >= 0 { slurs.append(LayoutSlur(startIndex: a, endIndex: b)) }
                }
                if v[i].tieStart, case let .note(p, _) = v[i].base {
                    if let end = v[(i+1)...].firstIndex(where: { ev in
                        guard ev.tieEnd else { return false }
                        if case let .note(p2, _) = ev.base { return p2.step == p.step && p2.alter == p.alter && p2.octave == p.octave }
                        return false
                    }) {
                        let a = indexMap[vi][i], b = indexMap[vi][end]
                        if a >= 0, b >= 0 { ties.append(LayoutTie(startIndex: a, endIndex: b)) }
                    }
                }
            }
        }

        return MultiLayoutTree(size: CGSize(width: max(rect.width, width), height: max(rect.height, height)), elements: elements, barX: barX, voices: voices, slurs: slurs, ties: ties)
    }

    public func draw(_ tree: MultiLayoutTree, in ctx: CGContext, options: LayoutOptions) {
        ctx.saveGState(); defer { ctx.restoreGState() }
        // Staff
        let origin = CGPoint(x: options.padding.width, y: options.padding.height)
        ctx.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
        ctx.setLineWidth(1)
        for i in 0..<5 {
            let y = origin.y + CGFloat(i) * options.staffSpacing
            ctx.move(to: CGPoint(x: origin.x, y: y))
            ctx.addLine(to: CGPoint(x: tree.size.width - options.padding.width, y: y))
        }
        ctx.strokePath()
        // Barlines
        let top = options.padding.height
        let bottom = tree.size.height - options.padding.height
        for x in tree.barX {
            ctx.move(to: CGPoint(x: x, y: top))
            ctx.addLine(to: CGPoint(x: x, y: bottom))
            ctx.strokePath()
        }
        // Noteheads
        for el in tree.elements {
            switch el.kind {
            case .note:
                ctx.setFillColor(CGColor(gray: 0.0, alpha: 1.0))
                ctx.fillEllipse(in: el.frame)
            case .rest:
                ctx.setFillColor(CGColor(gray: 0.5, alpha: 1.0))
                ctx.fill(el.frame)
            }
        }
        // Stems per voice: voice 0 up (right), voice 1 down (left)
        let middleY = (options.padding.height + options.staffSpacing * 2)
        for (idx, el) in tree.elements.enumerated() {
            guard case let .note(_, dur) = el.kind else { continue }
            let voice = tree.voices[idx]
            let stemUp = (voice == 0)
            let stemLength: CGFloat = options.staffSpacing * 3.5
            let x = stemUp ? (el.frame.maxX + 0.5) : (el.frame.minX - 0.5)
            let y1 = el.frame.midYVal
            let y2 = stemUp ? (y1 - stemLength) : (y1 + stemLength)
            ctx.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: x, y: y1))
            ctx.addLine(to: CGPoint(x: x, y: y2))
            ctx.strokePath()
            // simple flags for eighth+ if needed
            let flags = self.flagCount(for: dur)
            for i in 0..<flags {
                let offset: CGFloat = CGFloat(i) * 6
                if stemUp {
                    ctx.move(to: CGPoint(x: x, y: y2 + offset))
                    ctx.addQuadCurve(to: CGPoint(x: x + 10, y: y2 + offset + 4), control: CGPoint(x: x + 6, y: y2 + offset))
                } else {
                    ctx.move(to: CGPoint(x: x, y: y2 - offset))
                    ctx.addQuadCurve(to: CGPoint(x: x - 10, y: y2 - offset - 4), control: CGPoint(x: x - 6, y: y2 - offset))
                }
                ctx.strokePath()
            }
        }

        // Slurs
        for s in tree.slurs {
            guard s.startIndex < tree.elements.count, s.endIndex < tree.elements.count else { continue }
            let a = tree.elements[s.startIndex].frame
            let b = tree.elements[s.endIndex].frame
            let start = CGPoint(x: a.midXVal, y: a.minY - 6)
            let end = CGPoint(x: b.midXVal, y: b.minY - 6)
            let ctrl = CGPoint(x: (start.x + end.x)/2, y: min(start.y, end.y) - 12)
            ctx.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
            ctx.setLineWidth(1)
            ctx.move(to: start)
            ctx.addQuadCurve(to: end, control: ctrl)
            ctx.strokePath()
        }

        // Ties
        for t in tree.ties {
            guard t.startIndex < tree.elements.count, t.endIndex < tree.elements.count else { continue }
            let a = tree.elements[t.startIndex].frame
            let b = tree.elements[t.endIndex].frame
            let above = a.midYVal <= middleY
            let y = above ? (min(a.minY, b.minY) - 6) : (max(a.maxY, b.maxY) + 6)
            let start = CGPoint(x: a.maxX + 2, y: y)
            let end = CGPoint(x: b.minX - 2, y: y)
            let ctrlLift: CGFloat = above ? -4 : 4
            let ctrl = CGPoint(x: (start.x + end.x)/2, y: y + ctrlLift)
            ctx.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
            ctx.setLineWidth(1)
            ctx.move(to: start)
            ctx.addQuadCurve(to: end, control: ctrl)
            ctx.strokePath()
            let ctrl2 = CGPoint(x: ctrl.x, y: ctrl.y + (above ? -1.2 : 1.2))
            let start2 = CGPoint(x: start.x, y: start.y + (above ? -1.0 : 1.0))
            let end2 = CGPoint(x: end.x, y: end.y + (above ? -1.0 : 1.0))
            ctx.move(to: start2)
            ctx.addQuadCurve(to: end2, control: ctrl2)
            ctx.strokePath()
        }
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

    private func flagCount(for d: Duration) -> Int {
        switch d.den {
        case 1,2,4: return 0
        case 8: return 1
        case 16: return 2
        case 32: return 3
        default: return 0
        }
    }
}
