import Foundation
import CoreGraphics
import ScoreKit
import CoreText

public struct MultiLayoutTree: Sendable {
    public let size: CGSize
    public let elements: [LayoutElement]
    public let barX: [CGFloat]
    public let voices: [Int] // parallel to elements
    public let slurs: [LayoutSlur]
    public let ties: [LayoutTie]
    public let articulations: [Int: [Articulation]]
}

public struct MultiRenderer {
    public init() {}

    public func layout(voices vv: [[NotatedEvent]], in rect: CGRect, options: LayoutOptions) -> MultiLayoutTree {
        let staffHeight = options.staffSpacing * 4
        var width = options.padding.width * 2
        let height = options.padding.height * 2 + staffHeight + 40
        let origin = CGPoint(x: options.padding.width, y: options.padding.height)

        guard let v0 = vv.first, !v0.isEmpty else {
            return MultiLayoutTree(size: rect.size, elements: [], barX: [], voices: [], slurs: [], ties: [], articulations: [:])
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
        var artMap: [Int: [Articulation]] = [:]
        let beatsPerBar = max(1, options.timeSignature.beatsPerBar)
        let beatUnit = max(1, options.timeSignature.beatUnit)
        var barProgress: Double = 0

        // Precompute per-voice, per-index horizontal offsets for unisons (two voices only for now)
        var offsets: [[CGFloat]] = vv.map { _ in Array(repeating: 0, count: anchorsX.count) }
        if vv.count >= 2 {
            let m = min(vv[0].count, vv[1].count, anchorsX.count)
            for i in 0..<m {
                switch (vv[0][i].base, vv[1][i].base) {
                case (.note(let p0, _), .note(let p1, _)):
                    if p0.step == p1.step && p0.alter == p1.alter && p0.octave == p1.octave {
                        offsets[0][i] = -4; offsets[1][i] = +4
                    } else {
                        let y0 = StaffCoords.y(for: p0, clef: options.clef, originY: origin.y, staffSpacing: options.staffSpacing)
                        let y1 = StaffCoords.y(for: p1, clef: options.clef, originY: origin.y, staffSpacing: options.staffSpacing)
                        let dy = abs(y0 - y1)
                        if abs(dy - (options.staffSpacing/2)) <= 0.75 {
                            // Second interval: split heads
                            offsets[0][i] = -4; offsets[1][i] = +4
                        } else {
                            offsets[1][i] = +9
                        }
                    }
                default:
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
                    if let cached = yCache[p] { y = cached } else { let yy = StaffCoords.y(for: p, clef: options.clef, originY: origin.y, staffSpacing: options.staffSpacing); yCache[p] = yy; y = yy }
                    frame = CGRect(x: x - 5, y: y - 5, width: 10, height: 10)
                    elements.append(LayoutElement(index: i, kind: .note(p, d), frame: frame))
                case .rest(let d):
                    y = origin.y + staffHeight/2 - 3
                    frame = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
                    elements.append(LayoutElement(index: i, kind: .rest, frame: frame))
                }
                voices.append(vi)
                indexMap[vi][i] = elements.count - 1
                let frac = beatFraction(for: e, beatUnit: beatUnit)
                if vi == 0 { // primary voice decides barlines (fractional beats)
                    barProgress += frac
                    if barProgress >= Double(beatsPerBar) { barX.append(x + advance(for: e)); barProgress -= Double(beatsPerBar) }
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
                if !v[i].articulations.isEmpty {
                    let a = indexMap[vi][i]
                    if a >= 0 { artMap[a] = v[i].articulations }
                }
            }
        }

        return MultiLayoutTree(size: CGSize(width: max(rect.width, width), height: max(rect.height, height)), elements: elements, barX: barX, voices: voices, slurs: slurs, ties: ties, articulations: artMap)
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
        // Clef/Key/Time
        drawTrebleClefSMuFL(in: ctx, canvasHeight: tree.size.height, origin: origin, staffSpacing: options.staffSpacing)
        drawKeySignatureSMuFL(in: ctx, canvasHeight: tree.size.height, origin: origin, staffSpacing: options.staffSpacing, clef: .treble, fifths: 0)
        drawTimeSignatureSMuFL(in: ctx, canvasHeight: tree.size.height, origin: origin, staffSpacing: options.staffSpacing, time: options.timeSignature)

        // Noteheads and rests (SMuFL)
        for el in tree.elements {
            switch el.kind {
            case .note(let p, let d):
                if p.alter != 0 { drawAccidentalSMuFL(in: ctx, canvasHeight: tree.size.height, at: CGPoint(x: el.frame.minX - 12, y: el.frame.midYVal), alter: p.alter, staffSpacing: options.staffSpacing) }
                drawNoteheadSMuFL(in: ctx, canvasHeight: tree.size.height, at: CGPoint(x: el.frame.midXVal, y: el.frame.midYVal), durationDen: d.den, staffSpacing: options.staffSpacing)
            case .rest:
                drawRestSMuFL(in: ctx, canvasHeight: tree.size.height, at: CGPoint(x: el.frame.midXVal, y: el.frame.midYVal), durationDen: 4, staffSpacing: options.staffSpacing)
            }
        }
        // Stems per voice: voice 0 up (right), voice 1 down (left)
        let middleY = (options.padding.height + options.staffSpacing * 2)
        for (idx, el) in tree.elements.enumerated() {
            guard case let .note(_, dur) = el.kind else { continue }
            let voice = tree.voices[idx]
            let stemUp = (voice == 0)
            let stemLength: CGFloat = options.staffSpacing * 3.5
            let halfW = noteheadHalfWidth(forDen: (durationDenMulti(for: el)), staffSpacing: options.staffSpacing)
            let x = stemUp ? (el.frame.midXVal + halfW) : (el.frame.midXVal - halfW)
            let y1 = el.frame.midYVal
            let y2 = stemUp ? (y1 - stemLength) : (y1 + stemLength)
            ctx.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: x, y: y1))
            ctx.addLine(to: CGPoint(x: x, y: y2))
            ctx.strokePath()
            // SMuFL flags for un-beamed notes (MultiRenderer does not compute beaming yet)
            let flags = self.flagCount(for: dur)
            if flags > 0 {
                drawFlagSMuFL(in: ctx, canvasHeight: tree.size.height, atStemX: x, stemTipY: y2, stemUp: stemUp, flags: flags, staffSpacing: options.staffSpacing)
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

        // Articulations per element index
        for (idx, el) in tree.elements.enumerated() {
            guard case .note = el.kind else { continue }
            guard let arts = tree.articulations[idx], !arts.isEmpty else { continue }
            let voice = tree.voices[idx]
            let stemUp = (voice == 0)
            let baseY = stemUp ? (el.frame.minY - options.staffSpacing * 1.0) : (el.frame.maxY + options.staffSpacing * 0.9)
            let font = smuflFont(ofSize: options.staffSpacing * 1.4)
            var x = el.frame.midXVal
            for (i, a) in arts.enumerated() {
                let glyph = SMuFL.articulationGlyph(a)
                let y = baseY + (stemUp ? -CGFloat(i) * (options.staffSpacing * 0.6) : CGFloat(i) * (options.staffSpacing * 0.6))
                drawSMuFLText(ctx, canvasHeight: tree.size.height, text: glyph, at: CGPoint(x: x, y: y), font: font, alignCenter: true)
                x += options.staffSpacing * 0.9
            }
        }
    }

    // MARK: - Helpers (kept in sync with SimpleRenderer)
    // y mapping unified in StaffCoords.y

    private func beats(for e: NotatedEvent, beatUnit: Int) -> Int {
        switch e.base {
        case .note(_, let d): return max(1, beatUnit / max(1, d.den))
        case .rest(let d): return max(1, beatUnit / max(1, d.den))
        }
    }

    private func beatFraction(for e: NotatedEvent, beatUnit: Int) -> Double {
        switch e.base {
        case .note(_, let d): return Double(beatUnit) / Double(max(1, d.den))
        case .rest(let d): return Double(beatUnit) / Double(max(1, d.den))
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

    private func durationDenMulti(for el: LayoutElement) -> Int {
        if case let .note(_, d) = el.kind { return d.den }
        return 4
    }

    // SMuFL helpers (subset, centralized via SMuFLCatalog)
    private func smuflFont(ofSize size: CGFloat) -> CTFont { SMuFL.font(ofSize: size) }
    private func drawSMuFLText(_ ctx: CGContext, canvasHeight: CGFloat, text: String, at p: CGPoint, font: CTFont, alignCenter: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CGColor(gray: 0.0, alpha: 1.0)]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attr)
        ctx.saveGState(); ctx.textMatrix = .identity; ctx.translateBy(x: 0, y: canvasHeight); ctx.scaleBy(x: 1, y: -1)
        var pos = CGPoint(x: p.x, y: canvasHeight - p.y)
        if alignCenter {
            let b = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            pos.x -= b.midX; pos.y -= b.midY
        }
        ctx.textPosition = pos; CTLineDraw(line, ctx); ctx.restoreGState()
    }
    private func drawAccidentalSMuFL(in ctx: CGContext, canvasHeight: CGFloat, at p: CGPoint, alter: Int, staffSpacing: CGFloat) {
        let font = smuflFont(ofSize: staffSpacing * 1.3)
        drawSMuFLText(ctx, canvasHeight: canvasHeight, text: SMuFL.accidentalGlyph(for: alter), at: p, font: font)
    }
    private func smuflNoteheadGlyph(forDen den: Int) -> String { SMuFL.noteheadGlyph(forDen: den) }
    private func drawNoteheadSMuFL(in ctx: CGContext, canvasHeight: CGFloat, at center: CGPoint, durationDen: Int, staffSpacing: CGFloat) {
        let glyph = smuflNoteheadGlyph(forDen: durationDen)
        let font = smuflFont(ofSize: staffSpacing * 1.6)
        drawSMuFLText(ctx, canvasHeight: canvasHeight, text: glyph, at: center, font: font, alignCenter: true)
    }
    private func noteheadHalfWidth(forDen den: Int, staffSpacing: CGFloat) -> CGFloat {
        let glyph = smuflNoteheadGlyph(forDen: den); let font = smuflFont(ofSize: staffSpacing * 1.6)
        let attr = NSAttributedString(string: glyph, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attr)
        let b = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        return max(b.width, staffSpacing * 1.2) / 2
    }
    private func drawRestSMuFL(in ctx: CGContext, canvasHeight: CGFloat, at center: CGPoint, durationDen: Int, staffSpacing: CGFloat) {
        let font = smuflFont(ofSize: staffSpacing * 2.0)
        drawSMuFLText(ctx, canvasHeight: canvasHeight, text: SMuFL.restGlyph(forDen: durationDen), at: center, font: font, alignCenter: true)
    }
    private func drawTrebleClefSMuFL(in ctx: CGContext, canvasHeight: CGFloat, origin: CGPoint, staffSpacing: CGFloat) {
        let font = smuflFont(ofSize: staffSpacing * 4.6); let p = CGPoint(x: origin.x - staffSpacing * 0.8, y: origin.y + staffSpacing * 4.0)
        drawSMuFLText(ctx, canvasHeight: canvasHeight, text: SMuFL.trebleClef, at: p, font: font)
    }
    private func drawKeySignatureSMuFL(in ctx: CGContext, canvasHeight: CGFloat, origin: CGPoint, staffSpacing: CGFloat, clef: LayoutOptions.Clef, fifths: Int) {
        // No‑op in Multi for now (treble only)
    }
    private func drawTimeSignatureSMuFL(in ctx: CGContext, canvasHeight: CGFloat, origin: CGPoint, staffSpacing: CGFloat, time: (beatsPerBar: Int, beatUnit: Int)) {
        let font = smuflFont(ofSize: staffSpacing * 2.2)
        let x = origin.x + staffSpacing * 6.4
        let centerY = origin.y + staffSpacing * 2
        let numY = centerY - staffSpacing * 0.9
        let denY = centerY + staffSpacing * 1.0
        let numStr = String(time.beatsPerBar).compactMap { Int(String($0)) }
        let denStr = String(time.beatUnit).compactMap { Int(String($0)) }
        var adv: CGFloat = 0
        for d in numStr { drawSMuFLText(ctx, canvasHeight: canvasHeight, text: SMuFL.timeSigGlyph(digit: d), at: CGPoint(x: x + adv, y: numY), font: font, alignCenter: true); adv += staffSpacing * 1.2 }
        adv = 0
        for d in denStr { drawSMuFLText(ctx, canvasHeight: canvasHeight, text: SMuFL.timeSigGlyph(digit: d), at: CGPoint(x: x + adv, y: denY), font: font, alignCenter: true); adv += staffSpacing * 1.2 }
    }
    // Flags
    private func drawFlagSMuFL(in ctx: CGContext, canvasHeight: CGFloat, atStemX x: CGFloat, stemTipY y: CGFloat, stemUp: Bool, flags: Int, staffSpacing: CGFloat) {
        guard let glyph = SMuFL.flagGlyph(flags: flags, stemUp: stemUp) else { return }
        let font = smuflFont(ofSize: staffSpacing * 2.0)
        drawSMuFLText(ctx, canvasHeight: canvasHeight, text: glyph, at: CGPoint(x: x, y: y), font: font, alignCenter: false)
    }
}
