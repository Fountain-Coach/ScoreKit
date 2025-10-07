import Foundation
import CoreGraphics
import SwiftUI
import CoreText
import ScoreKit
import RulesKit

public struct LayoutOptions: Sendable {
    public var staffSpacing: CGFloat = 10 // distance between staff lines
    public var noteSpacing: CGFloat = 24  // nominal horizontal advance per event
    public var padding: CGSize = .init(width: 20, height: 20)
    public var barIndices: [Int] = []
    public var timeSignature: (beatsPerBar: Int, beatUnit: Int) = (4,4)
    public enum Clef: Sendable { case treble, bass }
    public var clef: Clef = .treble
    // Key signature in fifths: positive = sharps, negative = flats
    public var keySignatureFifths: Int = 0
    public init() {}
}

public struct LayoutElement: Sendable {
    public enum Kind: Sendable { case note(Pitch, Duration), rest }
    public let index: Int
    public let kind: Kind
    public let frame: CGRect
}

public struct LayoutSlur: Sendable { public let startIndex: Int; public let endIndex: Int }
public struct LayoutHairpin: Sendable { public let startIndex: Int; public let endIndex: Int; public let crescendo: Bool }
public struct LayoutTie: Sendable { public let startIndex: Int; public let endIndex: Int }

    public struct LayoutTree: Sendable {
    public let size: CGSize
    public let elements: [LayoutElement]
    public let slurs: [LayoutSlur]
    public let hairpins: [LayoutHairpin]
    public let ties: [LayoutTie]
    public let articulations: [Int: [Articulation]]
    public let dynamics: [Int: DynamicLevel]
    public struct LayoutMarks: Sendable { public let clef: ClefType?; public let keyFifths: Int?; public let time: (Int,Int)? }
    public let marks: [Int: LayoutMarks]
    public let barX: [CGFloat]
    public let beatPos: [Double]
    public let beamGroups: [[Int]]
    public let beamLevels: [Int]
}

public struct ScoreHit: Sendable { public let index: Int }

public protocol ScoreRenderable {
    func layout(events: [NotatedEvent], in rect: CGRect, options: LayoutOptions) -> LayoutTree
    func draw(_ tree: LayoutTree, in ctx: CGContext, options: LayoutOptions)
    func hitTest(_ tree: LayoutTree, at point: CGPoint) -> ScoreHit?
}

public struct SimpleRenderer: ScoreRenderable {
    private let rules = RulesService()
    public init() {}

    public func layout(events: [NotatedEvent], in rect: CGRect, options: LayoutOptions) -> LayoutTree {
        let staffHeight = options.staffSpacing * 4 // 5 lines = 4 gaps
        var width = options.padding.width * 2
        let height = options.padding.height * 2 + staffHeight + 40 // extra for hairpins/ledger
        var elements: [LayoutElement] = []
        var slurs: [LayoutSlur] = []
        var hairpins: [LayoutHairpin] = []
        var ties: [LayoutTie] = []
        var barX: [CGFloat] = []
        var artMap: [Int: [Articulation]] = [:]
        var dynMap: [Int: DynamicLevel] = [:]
        var marks: [Int: LayoutTree.LayoutMarks] = [:]
        let origin = CGPoint(x: options.padding.width, y: options.padding.height)
        let optionsBarIndices = Set(options.barIndices)

        var cursorX = origin.x
        var beatsInBar: Int = 0
        let beatsPerBar = max(1, options.timeSignature.beatsPerBar)
        let beatUnit = max(1, options.timeSignature.beatUnit)
        var yCache: [Pitch: CGFloat] = [:]
        var beatPos: [Double] = []
        var beatAccum: Double = 0
        for (i, e) in events.enumerated() {
            let x = cursorX
            if optionsBarIndices.contains(i) { barX.append(x) }
            let y: CGFloat
            let frame: CGRect
            switch e.base {
            case let .note(p, d):
                if let cached = yCache[p] {
                    y = cached
                } else {
                    let yy = yOffset(for: p, clef: options.clef, staffSpacing: options.staffSpacing, originY: origin.y)
                    yCache[p] = yy; y = yy
                }
                frame = CGRect(x: x - 5, y: y - 5, width: 10, height: 10)
                elements.append(LayoutElement(index: i, kind: .note(p, d), frame: frame))
            case .rest:
                y = origin.y + staffHeight/2 - 3
                frame = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
                elements.append(LayoutElement(index: i, kind: .rest, frame: frame))
            }
            // advance cursor based on duration
            cursorX += advance(for: e)
            width = max(width, cursorX + options.padding.width)
            // accumulate beat position within current bar
            let frac = beatFraction(for: e, beatUnit: beatUnit)
            beatAccum += frac
            let posInBar = beatAccum.truncatingRemainder(dividingBy: Double(beatsPerBar))
            beatPos.append(posInBar)
            // insert computed barlines based on time signature
            let eb = beats(for: e, beatUnit: beatUnit)
            beatsInBar += eb
            while beatsInBar >= beatsPerBar {
                barX.append(cursorX)
                beatsInBar -= beatsPerBar
                // align accumulator to bar
                beatAccum = floor(beatAccum)
            }
            if e.slurStart {
                if let end = events[(i+1)...].firstIndex(where: { $0.slurEnd }) {
                    slurs.append(LayoutSlur(startIndex: i, endIndex: end))
                }
            }
            if let hp = e.hairpinStart {
                if let end = events[(i+1)...].firstIndex(where: { $0.hairpinEnd }) {
                    hairpins.append(LayoutHairpin(startIndex: i, endIndex: end, crescendo: hp == .crescendo))
                }
            }
        }
        // Build ties from events (match same pitch start/end)
        for i in 0..<events.count {
            if events[i].tieStart, case let .note(p, _) = events[i].base {
                if let end = events[(i+1)...].firstIndex(where: { ev in
                    guard ev.tieEnd else { return false }
                    if case let .note(p2, _) = ev.base { return p2.step == p.step && p2.alter == p.alter && p2.octave == p.octave }
                    return false
                }) {
                    ties.append(LayoutTie(startIndex: i, endIndex: end))
                }
            }
            if !events[i].articulations.isEmpty { artMap[i] = events[i].articulations }
            if let dyn = events[i].dynamic { dynMap[i] = dyn }
            if events[i].clefChange != nil || events[i].keyChangeFifths != nil || events[i].timeChange != nil {
                let clef = events[i].clefChange
                let keyF = events[i].keyChangeFifths
                let t = events[i].timeChange.map { ($0.beatsPerBar, $0.beatUnit) }
                marks[i] = LayoutTree.LayoutMarks(clef: clef, keyFifths: keyF, time: t)
            }
        }
        let (beamGroups, beamLevels) = computeBeams(elements: elements, beatPos: beatPos, beatsPerBar: beatsPerBar, beatUnit: beatUnit)
        return LayoutTree(size: CGSize(width: max(rect.width, width), height: max(rect.height, height)), elements: elements, slurs: slurs, hairpins: hairpins, ties: ties, articulations: artMap, dynamics: dynMap, marks: marks, barX: barX, beatPos: beatPos, beamGroups: beamGroups, beamLevels: beamLevels)
    }

    public func draw(_ tree: LayoutTree, in ctx: CGContext, options: LayoutOptions) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        // Draw staff (treble) baseline at padding origin
        let origin = CGPoint(x: options.padding.width, y: options.padding.height)
        ctx.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
        ctx.setLineWidth(1)
        for i in 0..<5 {
            let y = origin.y + CGFloat(i) * options.staffSpacing
            ctx.move(to: CGPoint(x: origin.x, y: y))
            ctx.addLine(to: CGPoint(x: tree.size.width - options.padding.width, y: y))
        }
        ctx.strokePath()

        // SMuFL clef rendering (treble), best-effort if font present
        switch options.clef {
        case .treble:
            drawTrebleClefSMuFL(in: ctx, canvasHeight: tree.size.height, origin: origin, staffSpacing: options.staffSpacing)
        case .bass:
            drawBassClefSMuFL(in: ctx, canvasHeight: tree.size.height, origin: origin, staffSpacing: options.staffSpacing)
        }
        drawKeySignatureSMuFL(in: ctx, canvasHeight: tree.size.height, origin: origin, staffSpacing: options.staffSpacing, clef: options.clef, fifths: options.keySignatureFifths)
        drawTimeSignatureSMuFL(in: ctx, canvasHeight: tree.size.height, origin: origin, staffSpacing: options.staffSpacing, time: options.timeSignature)

        // Draw barlines
        let top = options.padding.height
        let bottom = tree.size.height - options.padding.height
        for x in tree.barX {
            ctx.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: x, y: top))
            ctx.addLine(to: CGPoint(x: x, y: bottom))
            ctx.strokePath()
        }

        // Draw notes/rests (ledger lines handled below) with accidentals and SMuFL noteheads
        for el in tree.elements {
            switch el.kind {
            case .note(let p, _):
                if p.alter != 0 {
                    drawAccidentalSMuFL(in: ctx, canvasHeight: tree.size.height, at: CGPoint(x: el.frame.minX - 12, y: el.frame.midYVal), alter: p.alter, staffSpacing: options.staffSpacing)
                }
                drawNoteheadSMuFL(in: ctx, canvasHeight: tree.size.height, at: CGPoint(x: el.frame.midXVal, y: el.frame.midYVal), durationDen: durationDen(for: el), staffSpacing: options.staffSpacing)
            case .rest:
                // SMuFL rest glyph (best effort), with simple fallback rectangle
                // We don't have direct access to duration here; fallback to quarter rest glyph size
                drawRestSMuFL(in: ctx, canvasHeight: tree.size.height, at: CGPoint(x: el.frame.midXVal, y: el.frame.midYVal), durationDen: 4, staffSpacing: options.staffSpacing)
                ctx.setFillColor(CGColor(gray: 0.5, alpha: 0.12))
                ctx.fill(el.frame)
            }
        }

        // Render mid-score clef/key/time changes near the event positions
        for el in tree.elements {
            let idx = el.index
            guard let mark = tree.marks[idx] else { continue }
            var x = el.frame.minX - options.staffSpacing * 1.2
            if let clef = mark.clef {
                switch clef {
                case .treble: drawTrebleClefSMuFL(in: ctx, canvasHeight: tree.size.height, origin: CGPoint(x: x, y: options.padding.height), staffSpacing: options.staffSpacing)
                case .bass: drawBassClefSMuFL(in: ctx, canvasHeight: tree.size.height, origin: CGPoint(x: x, y: options.padding.height), staffSpacing: options.staffSpacing)
                }
                x += options.staffSpacing * 1.6
            }
            if let k = mark.keyFifths {
                drawKeySignatureSMuFL(in: ctx, canvasHeight: tree.size.height, origin: CGPoint(x: x, y: options.padding.height), staffSpacing: options.staffSpacing, clef: options.clef, fifths: k)
                x += CGFloat(abs(k)) * options.staffSpacing * 0.9
            }
            if let t = mark.time { drawTimeSignatureSMuFL(in: ctx, canvasHeight: tree.size.height, origin: CGPoint(x: x, y: options.padding.height), staffSpacing: options.staffSpacing, time: t) }
        }

        // Draw dynamics glyphs at events with dynamics (apply kerning offsets if available)
        for (idx, dyn) in tree.dynamics {
            guard idx < tree.elements.count else { continue }
            let el = tree.elements[idx]
            let y = max(el.frame.maxY + options.staffSpacing * 1.4, options.padding.height + options.staffSpacing * 2.2)
            // Compute a simple dynamic bbox around the nominal position; hairpin context omitted in this basic pass
            let dynRect = CGRect(x: el.frame.midXVal - options.staffSpacing * 0.6,
                                 y: y - options.staffSpacing * 0.6,
                                 width: options.staffSpacing * 1.2,
                                 height: options.staffSpacing * 1.2)
            let k = rules.kerningOffset(dynamicRect: dynRect, hairpinRect: nil)
            drawDynamicsSMuFL(in: ctx, canvasHeight: tree.size.height, at: CGPoint(x: el.frame.midXVal + k.x, y: y + k.y), level: dyn, staffSpacing: options.staffSpacing)
        }

        // Ledger lines for notes beyond staff
        let topLine = origin.y
        let bottomLine = origin.y + options.staffSpacing * 4
        ctx.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
        ctx.setLineWidth(1)
        for el in tree.elements {
            guard case .note = el.kind else { continue }
            let midY = el.frame.midYVal
            let x1 = el.frame.midXVal - 7
            let x2 = el.frame.midXVal + 7
            if midY < topLine {
                var ly = topLine - options.staffSpacing
                while ly >= midY {
                    ctx.move(to: CGPoint(x: x1, y: ly))
                    ctx.addLine(to: CGPoint(x: x2, y: ly))
                    ly -= options.staffSpacing
                }
                ctx.strokePath()
            } else if midY > bottomLine {
                var ly = bottomLine + options.staffSpacing
                while ly <= midY {
                    ctx.move(to: CGPoint(x: x1, y: ly))
                    ctx.addLine(to: CGPoint(x: x2, y: ly))
                    ly += options.staffSpacing
                }
                ctx.strokePath()
            }
        }

        // Precompute which indices are in beam groups to suppress individual flags
        var beamedIndices: Set<Int> = []
        for g in tree.beamGroups { for idx in g { beamedIndices.insert(idx) } }

        // Draw stems and flags (use SMuFL flag glyphs for un-beamed notes)
        for el in tree.elements {
            guard case let .note(_, dur) = el.kind else { continue }
            // Stems up when notehead is below middle line (greater Y in screen coords).
            // Enforce "middle line stems down" by using strict > for up, equality/down -> down.
            let middleY = (options.padding.height + options.staffSpacing * 2)
            let stemUp = el.frame.midYVal > middleY
            // Standard stem length ≈ 3.5 staff spaces for single notes
            let stemLength: CGFloat = options.staffSpacing * 3.5
            // Attach relative to SMuFL notehead width (approx)
            let halfW = noteheadHalfWidth(forDen: durationDen(for: el), staffSpacing: options.staffSpacing)
            let x = stemUp ? (el.frame.midXVal + halfW) : (el.frame.midXVal - halfW)
            let y1 = el.frame.midYVal
            let y2 = stemUp ? (y1 - stemLength) : (y1 + stemLength)
            ctx.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: x, y: y1))
            ctx.addLine(to: CGPoint(x: x, y: y2))
            ctx.strokePath()
            // flags for eighth and beyond
            let flags = flagCount(for: dur)
            if flags > 0 && !beamedIndices.contains(el.index) {
                drawFlagSMuFL(in: ctx,
                              canvasHeight: tree.size.height,
                              atStemX: x,
                              stemTipY: y2,
                              stemUp: stemUp,
                              flags: flags,
                              staffSpacing: options.staffSpacing)
            }
        }

        // Draw slurs (simple bezier above notes)
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

        // Draw hairpins below staff
        for h in tree.hairpins {
            guard h.startIndex < tree.elements.count, h.endIndex < tree.elements.count else { continue }
            let a = tree.elements[h.startIndex].frame
            let b = tree.elements[h.endIndex].frame
            let baseline = max(a.maxY, b.maxY) + 18
            let start = CGPoint(x: a.midXVal, y: baseline)
            let end = CGPoint(x: b.midXVal, y: baseline)
            ctx.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
            ctx.setLineWidth(1)
            if h.crescendo {
                // opening wedge
                ctx.move(to: start)
                ctx.addLine(to: CGPoint(x: end.x, y: end.y - 6))
                ctx.move(to: start)
                ctx.addLine(to: CGPoint(x: end.x, y: end.y + 6))
            } else {
                // closing wedge
                ctx.move(to: end)
                ctx.addLine(to: CGPoint(x: start.x, y: start.y - 6))
                ctx.move(to: end)
                ctx.addLine(to: CGPoint(x: start.x, y: start.y + 6))
            }
            ctx.strokePath()
        }

        // Draw ties (shallow bezier near noteheads)
        let middleY = (options.padding.height + options.staffSpacing * 2)
        if !tree.elements.isEmpty {
            for t in tree.ties {
                guard t.startIndex < tree.elements.count, t.endIndex < tree.elements.count else { continue }
                let a = tree.elements[t.startIndex].frame
                let b = tree.elements[t.endIndex].frame
                // Only draw if both are notes
                switch (tree.elements[t.startIndex].kind, tree.elements[t.endIndex].kind) {
                case (.note, .note):
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
                default:
                    continue
                }
            }
        }

        // Draw articulations (SMuFL) per note by event index
        for el in tree.elements {
            guard case .note = el.kind else { continue }
            guard let arts = tree.articulations[el.index], !arts.isEmpty else { continue }
            let middleY = (options.padding.height + options.staffSpacing * 2)
            let stemUp = el.frame.midYVal > middleY
            let baseY = stemUp ? (el.frame.minY - options.staffSpacing * 1.0) : (el.frame.maxY + options.staffSpacing * 0.9)
            var x = el.frame.midXVal
            let font = smuflFont(ofSize: options.staffSpacing * 1.4)
            for (idx, a) in arts.enumerated() {
                let glyph = SMuFL.articulationGlyph(a)
                let y = baseY + (stemUp ? -CGFloat(idx) * (options.staffSpacing * 0.6) : CGFloat(idx) * (options.staffSpacing * 0.6))
                drawSMuFLText(ctx, canvasHeight: tree.size.height, text: glyph, at: CGPoint(x: x, y: y), font: font, alignCenter: true)
                x += options.staffSpacing * 0.9
            }
        }

        // Draw beaming across consecutive eighth-or-shorter notes; compound meters group by dotted beats
        var i = 0
        while i < tree.elements.count {
            guard case .note(_, let d) = tree.elements[i].kind, d.den >= 8 else { i += 1; continue }
            let isCompound = (options.timeSignature.beatUnit == 8) && (options.timeSignature.beatsPerBar % 3 == 0)
            let groupSize: Double = isCompound ? 3.0 : 1.0
            let startGroup = isCompound ? Int(floor(((i == 0) ? 0.0 : tree.beatPos[i-1]) / groupSize)) : intBeatIndex(tree.beatPos[i])
            var j = i + 1
            var group: [Int] = [i]
            while j < tree.elements.count, case .note(_, let d2) = tree.elements[j].kind, d2.den >= 8 {
                let gIdx = isCompound ? Int(floor(((j == 0) ? 0.0 : tree.beatPos[j-1]) / groupSize)) : intBeatIndex(tree.beatPos[j])
                if gIdx != startGroup { break }
                group.append(j)
                j += 1
            }
            if group.count >= 2 {
                // Slanted beam using stem tip of first/last notes
                let stemLength: CGFloat = options.staffSpacing * 3.5
                let first = tree.elements[group.first!]
                let last = tree.elements[group.last!]
                let middleY = (options.padding.height + options.staffSpacing * 2)
                let stemUp = first.frame.midYVal > middleY
                let halfW = noteheadHalfWidth(forDen: durationDen(for: first), staffSpacing: options.staffSpacing)
                let tipYFirst = stemUp ? (first.frame.midYVal - stemLength) : (first.frame.midYVal + stemLength)
                let tipYLast = stemUp ? (last.frame.midYVal - stemLength) : (last.frame.midYVal + stemLength)
                ctx.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
                ctx.setLineWidth(3)
                let xStart = first.frame.midXVal + (stemUp ? halfW : -halfW)
                let xEnd = last.frame.midXVal + (stemUp ? halfW : -halfW)
                ctx.move(to: CGPoint(x: xStart, y: tipYFirst))
                ctx.addLine(to: CGPoint(x: xEnd, y: tipYLast))
                ctx.strokePath()
                // second/third beams between adjacent notes depending on duration levels
                for k in 0..<(group.count - 1) {
                    let a = group[k]; let b = group[k+1]
                    let level = min(beamLevelFor(tree.elements[a]), beamLevelFor(tree.elements[b]))
                    if level >= 2 {
                        // Draw segment along slanted beam with offset
                        let xa = tree.elements[a].frame.midXVal + (stemUp ? halfW : -halfW)
                        let xb = tree.elements[b].frame.midXVal + (stemUp ? halfW : -halfW)
                        // Interpolate y along main beam
                        let yMainA = tipYFirst + (tipYLast - tipYFirst) * ((xa - xStart) / max(1e-6, (xEnd - xStart)))
                        let yMainB = tipYFirst + (tipYLast - tipYFirst) * ((xb - xStart) / max(1e-6, (xEnd - xStart)))
                        let y2a = stemUp ? yMainA - 4 : yMainA + 4
                        let y2b = stemUp ? yMainB - 4 : yMainB + 4
                        ctx.setLineWidth(2)
                        ctx.move(to: CGPoint(x: xa, y: y2a))
                        ctx.addLine(to: CGPoint(x: xb, y: y2b))
                        ctx.strokePath()
                    }
                    if level >= 3 {
                        let xa = tree.elements[a].frame.midXVal + (stemUp ? halfW : -halfW)
                        let xb = tree.elements[b].frame.midXVal + (stemUp ? halfW : -halfW)
                        let yMainA = tipYFirst + (tipYLast - tipYFirst) * ((xa - xStart) / max(1e-6, (xEnd - xStart)))
                        let yMainB = tipYFirst + (tipYLast - tipYFirst) * ((xb - xStart) / max(1e-6, (xEnd - xStart)))
                        let y3a = stemUp ? yMainA - 8 : yMainA + 8
                        let y3b = stemUp ? yMainB - 8 : yMainB + 8
                        ctx.setLineWidth(2)
                        ctx.move(to: CGPoint(x: xa, y: y3a))
                        ctx.addLine(to: CGPoint(x: xb, y: y3b))
                        ctx.strokePath()
                    }
                }
            }
            i = j
        }
    }

    public func hitTest(_ tree: LayoutTree, at point: CGPoint) -> ScoreHit? {
        if let el = tree.elements.first(where: { $0.frame.insetBy(dx: -4, dy: -4).contains(point) }) {
            return ScoreHit(index: el.index)
        }
        return nil
    }

    // Incremental update API with tighter partial reflow (per-measure window).
    // Reflows only the affected measure range and shifts subsequent content.
    public func updateLayout(previous: LayoutTree?, events: [NotatedEvent], in rect: CGRect, options: LayoutOptions, changed: Set<Int>) -> LayoutTree {
        guard let prev = previous, !changed.isEmpty else {
            return layout(events: events, in: rect, options: options)
        }
        // Determine window to reflow: from start of first affected measure to end of last affected measure.
        let beatsPerBar = max(1, options.timeSignature.beatsPerBar)
        let beatUnit = max(1, options.timeSignature.beatUnit)
        // No prev beat map? Fallback
        guard prev.elements.count == events.count, prev.beatPos.count == events.count else {
            return layout(events: events, in: rect, options: options)
        }
        var firstChanged = max(0, changed.min()!)
        var lastChanged = min(events.count - 1, changed.max()!)

        // Layer-in neighbor-span expansion: include entire slurs/hairpins and beam groups that intersect the change set.
        // Use previous layout's spans/groups as a conservative window-expansion guide.
        if !prev.slurs.isEmpty {
            for s in prev.slurs {
                if s.startIndex <= lastChanged && s.endIndex >= firstChanged {
                    firstChanged = min(firstChanged, s.startIndex)
                    lastChanged = max(lastChanged, s.endIndex)
                }
            }
        }
        if !prev.hairpins.isEmpty {
            for h in prev.hairpins {
                if h.startIndex <= lastChanged && h.endIndex >= firstChanged {
                    firstChanged = min(firstChanged, h.startIndex)
                    lastChanged = max(lastChanged, h.endIndex)
                }
            }
        }
        if !prev.beamGroups.isEmpty {
            for g in prev.beamGroups {
                if g.isEmpty { continue }
                // Quick overlap test using range of group
                let gMin = g.first!
                let gMax = g.last!
                if gMin <= lastChanged && gMax >= firstChanged {
                    firstChanged = min(firstChanged, gMin)
                    lastChanged = max(lastChanged, gMax)
                }
            }
        }

        func findMeasureStart(from index: Int) -> Int {
            if index <= 0 { return 0 }
            var i = index - 1
            while i >= 0 {
                if abs(prev.beatPos[i]) < 1e-9 { return i + 1 }
                i -= 1
            }
            return 0
        }
        func findMeasureEndInclusive(from index: Int) -> Int {
            var i = index
            while i < prev.beatPos.count {
                if abs(prev.beatPos[i]) < 1e-9 { return i }
                i += 1
            }
            return events.count - 1
        }

        let reflowStart = findMeasureStart(from: firstChanged)
        let reflowEnd = findMeasureEndInclusive(from: lastChanged)

        // Build prefix (unchanged section before reflowStart)
        var newElements: [LayoutElement] = []
        if reflowStart > 0 { newElements.append(contentsOf: prev.elements[0..<reflowStart]) }

        // Prepare caches & state
        let origin = CGPoint(x: options.padding.width, y: options.padding.height)
        let staffHeight = options.staffSpacing * 4
        var yCache: [Pitch: CGFloat] = [:]
        // Start cursor at previous X of the first element in the reflow start
        var cursorX = prev.elements[reflowStart].frame.midXVal
        let prevStartX = cursorX

        // Beat tracking resets at measure start
        var localBeatPos: [Double] = []
        var localBarX: [CGFloat] = []
        var beatsInBar = 0

        // Recompute elements for [reflowStart ... reflowEnd]
        for i in reflowStart...reflowEnd {
            let e = events[i]
            let y: CGFloat
            let frame: CGRect
            switch e.base {
            case let .note(p, d):
                if let cached = yCache[p] { y = cached }
                else { let yy = yOffset(for: p, clef: options.clef, staffSpacing: options.staffSpacing, originY: origin.y); yCache[p] = yy; y = yy }
                frame = CGRect(x: cursorX - 5, y: y - 5, width: 10, height: 10)
                newElements.append(LayoutElement(index: i, kind: .note(p, d), frame: frame))
            case .rest(_):
                y = origin.y + staffHeight/2 - 3
                frame = CGRect(x: cursorX - 4, y: y - 4, width: 8, height: 8)
                newElements.append(LayoutElement(index: i, kind: .rest, frame: frame))
            }
            // advance and compute local beat pos/barX for the changed window
            cursorX += advance(for: e)
            let frac = beatFraction(for: e, beatUnit: beatUnit)
            let lastPos = (localBeatPos.last ?? 0)
            let newPos = (lastPos + frac).truncatingRemainder(dividingBy: Double(beatsPerBar))
            localBeatPos.append(newPos)
            let eb = beats(for: e, beatUnit: beatUnit)
            beatsInBar += eb
            while beatsInBar >= beatsPerBar {
                localBarX.append(cursorX)
                beatsInBar -= beatsPerBar
            }
        }
        let newEndNextX = cursorX // X at end of last reflowed event (start of following element)

        // Compute previous end-next-X for delta calculation
        let prevEndNextX: CGFloat = {
            if reflowEnd + 1 < prev.elements.count { return prev.elements[reflowEnd + 1].frame.midXVal }
            // else derive by advancing last element once
            let lastEl = prev.elements[reflowEnd]
            switch events[reflowEnd].base {
            case .note(_, let d):
                let adv = advance(for: .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: d)))
                return lastEl.frame.midXVal + adv
            case .rest(let d):
                let adv = advance(for: .init(base: .rest(duration: d)))
                return lastEl.frame.midXVal + adv
            }
        }()

        let deltaX = newEndNextX - prevEndNextX

        // Append shifted suffix
        if reflowEnd + 1 < prev.elements.count {
            for el in prev.elements[(reflowEnd+1)..<prev.elements.count] {
                let f = el.frame
                let shifted = CGRect(x: f.origin.x + deltaX, y: f.origin.y, width: f.size.width, height: f.size.height)
                newElements.append(LayoutElement(index: el.index, kind: el.kind, frame: shifted))
            }
        }

        // Rebuild beatPos array: prefix (unchanged until reflowStart-1), local (changed window), suffix (unchanged after reflowEnd)
        var newBeatPos: [Double] = []
        if reflowStart > 0 { newBeatPos.append(contentsOf: prev.beatPos[0..<reflowStart]) }
        newBeatPos.append(contentsOf: localBeatPos)
        if reflowEnd + 1 < prev.beatPos.count { newBeatPos.append(contentsOf: prev.beatPos[(reflowEnd+1)..<prev.beatPos.count]) }

        // Rebuild barX: prefix (<= start bar), local (bars in changed range), suffix (shifted by delta)
        var newBarX: [CGFloat] = []
        // include bars up to and including the barline at the start of reflow (if present)
        let eps: CGFloat = 1e-6
        newBarX.append(contentsOf: prev.barX.filter { $0 <= (prevStartX + eps) })
        // include local bars computed with the new cursor
        newBarX.append(contentsOf: localBarX)
        // shift subsequent bars strictly after previous end-next-X
        let suffixBars = prev.barX.filter { $0 > (prevEndNextX + eps) }.map { $0 + deltaX }
        newBarX.append(contentsOf: suffixBars)

        // Slurs/hairpins/ties: recompute globally (cheap) for correctness across boundaries
        var slurs: [LayoutSlur] = []
        var hairpins: [LayoutHairpin] = []
        var ties: [LayoutTie] = []
        for i in 0..<events.count {
            if events[i].slurStart, let end = events[(i+1)...].firstIndex(where: { $0.slurEnd }) { slurs.append(LayoutSlur(startIndex: i, endIndex: end)) }
            if let hp = events[i].hairpinStart, let end = events[(i+1)...].firstIndex(where: { $0.hairpinEnd }) { hairpins.append(LayoutHairpin(startIndex: i, endIndex: end, crescendo: hp == .crescendo)) }
            if events[i].tieStart, case let .note(p, _) = events[i].base {
                if let end = events[(i+1)...].firstIndex(where: { ev in
                    guard ev.tieEnd else { return false }
                    if case let .note(p2, _) = ev.base { return p2.step == p.step && p2.alter == p.alter && p2.octave == p.octave }
                    return false
                }) { ties.append(LayoutTie(startIndex: i, endIndex: end)) }
            }
        }

        // Compute size width by tracking final next-X
        let prevLastIdx = events.count - 1
        let prevLastNextX: CGFloat = {
            if prevLastIdx + 1 < prev.elements.count { return prev.elements[prevLastIdx + 1].frame.midXVal }
            // else derive from last element in prev
            let lastEl = prev.elements[prevLastIdx]
            switch events[prevLastIdx].base {
            case .note(_, let d):
                return lastEl.frame.midXVal + advance(for: .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: d)))
            case .rest(let d):
                return lastEl.frame.midXVal + advance(for: .init(base: .rest(duration: d)))
            }
        }()
        let newLastNextX: CGFloat = (reflowEnd < prevLastIdx) ? (prevLastNextX + deltaX) : newEndNextX
        let newWidth = max(rect.width, newLastNextX + options.padding.width)
        let newHeight = max(rect.height, prev.size.height)

        // Beam groups/levels recomputed globally (fast enough N)
        let (beamGroups, beamLevels) = computeBeams(elements: newElements, beatPos: newBeatPos, beatsPerBar: beatsPerBar, beatUnit: beatUnit)
        var artMap: [Int: [Articulation]] = [:]
        var dynMap: [Int: DynamicLevel] = [:]
        var marks: [Int: LayoutTree.LayoutMarks] = [:]
        for idx in 0..<events.count {
            if !events[idx].articulations.isEmpty { artMap[idx] = events[idx].articulations }
            if let dyn = events[idx].dynamic { dynMap[idx] = dyn }
            if events[idx].clefChange != nil || events[idx].keyChangeFifths != nil || events[idx].timeChange != nil {
                let clef = events[idx].clefChange
                let keyF = events[idx].keyChangeFifths
                let t = events[idx].timeChange.map { ($0.beatsPerBar, $0.beatUnit) }
                marks[idx] = LayoutTree.LayoutMarks(clef: clef, keyFifths: keyF, time: t)
            }
        }
        return LayoutTree(size: CGSize(width: newWidth, height: newHeight), elements: newElements, slurs: slurs, hairpins: hairpins, ties: ties, articulations: artMap, dynamics: dynMap, marks: marks, barX: newBarX, beatPos: newBeatPos, beamGroups: beamGroups, beamLevels: beamLevels)
    }

    // MARK: - Helpers
    // Very rough treble clef mapping: E4 on bottom line; middle C (C4) one ledger below.
    private func yOffset(for p: Pitch, clef: LayoutOptions.Clef, staffSpacing: CGFloat, originY: CGFloat) -> CGFloat {
        let stepIndex: Int
        switch p.step { case .C: stepIndex = 0; case .D: stepIndex = 1; case .E: stepIndex = 2; case .F: stepIndex = 3; case .G: stepIndex = 4; case .A: stepIndex = 5; case .B: stepIndex = 6 }
        let diatonic = (p.octave - 4) * 7 + stepIndex // relative to C4
        let c4Y: CGFloat
        switch clef {
        case .treble:
            // Approx: C4 one space below bottom line + a bit
            c4Y = originY + staffSpacing * 5
        case .bass:
            // Approx: C4 one ledger above top line
            c4Y = originY - staffSpacing
        }
        let offset = -CGFloat(diatonic) * (staffSpacing / 2)
        return c4Y + offset
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

    private func durationDen(for el: LayoutElement) -> Int {
        if case let .note(_, d) = el.kind { return d.den }
        return 4
    }

    private func beats(for e: NotatedEvent, beatUnit: Int) -> Int {
        switch e.base {
        case .note(_, let d): return beats(den: d.den, beatUnit: beatUnit)
        case .rest(let d): return beats(den: d.den, beatUnit: beatUnit)
        }
    }
    private func beats(den: Int, beatUnit: Int) -> Int {
        // beats = (1/den) / (1/beatUnit) = beatUnit/den (integer approximation)
        return max(1, beatUnit / max(1, den))
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

    private func computeBeams(elements: [LayoutElement], beatPos: [Double], beatsPerBar: Int, beatUnit: Int) -> ([[Int]], [Int]) {
        // Heuristic beaming fallback: group consecutive beamable notes within a primary beat boundary.
        // Beamable = duration <= 1/8 (den >= 8). Break at rests, non-beamable notes, and beat boundaries.
        var groups: [[Int]] = []
        var levels: [Int] = Array(repeating: 0, count: elements.count)
        guard !elements.isEmpty else { return (groups, levels) }

        // Determine primary beat partitioning
        // Simple: unit = 1.0 (based on beatUnit)
        // Compound (6/8, 9/8, 12/8): unit = 3 eighths ⇒ in our beatPos units, this is 3.0 when beatUnit == 8
        let isCompound = (beatUnit == 8) && (beatsPerBar % 3 == 0)
        let unit: Double = isCompound ? 3.0 : 1.0

        func groupIndex(for startPos: Double) -> Int {
            // startPos denotes the position at the start of an event (in beat units).
            // Exact boundaries should start a new group, so use floor without shifting.
            return Int(floor(startPos / unit))
        }

        var current: [Int] = []
        var currentGroupIdx: Int = -1

        for i in 0..<elements.count {
            let el = elements[i]
            let beamLevel: Int = {
                switch el.kind { case .note(_, let d): return (d.den >= 8 ? (d.den == 8 ? 1 : (d.den == 16 ? 2 : (d.den >= 32 ? 3 : 0))) : 0); case .rest: return 0 }
            }()
            let beamable = beamLevel > 0
            if !beamable {
                if current.count >= 2 { groups.append(current) }
                current.removeAll(keepingCapacity: true)
                currentGroupIdx = -1
                continue
            }
            let startPos: Double = (i == 0) ? 0.0 : beatPos[i - 1]
            let gi = groupIndex(for: startPos)
            if current.isEmpty {
                current.append(i)
                currentGroupIdx = gi
                levels[i] = beamLevel
            } else {
                // Break group on primary beat boundary change
                if gi != currentGroupIdx {
                    if current.count >= 2 { groups.append(current) }
                    current = [i]
                    currentGroupIdx = gi
                } else {
                    current.append(i)
                }
                levels[i] = beamLevel
            }
        }
        if current.count >= 2 { groups.append(current) }
        return (groups, levels)
    }

    private func beamLevelFor(_ el: LayoutElement) -> Int {
        switch el.kind {
        case .note(_, let d):
            switch d.den { case 8: return 1; case 16: return 2; case 32: return 3; default: return 0 }
        case .rest:
            return 0
        }
    }

    private func intBeatIndex(_ pos: Double) -> Int {
        // Treat exact integer positions as belonging to the previous beat
        let rounded = round(pos)
        if abs(pos - rounded) < 1e-9 { return Int(max(0, rounded - 1)) }
        return Int(floor(pos))
    }
}

extension CGRect {
    var midXVal: CGFloat { origin.x + size.width/2 }
    var midYVal: CGFloat { origin.y + size.height/2 }
}

// MARK: - SMuFL glyph helpers (clefs/accidentals)
extension SimpleRenderer {
    fileprivate func noteheadHalfWidth(staffSpacing: CGFloat) -> CGFloat { staffSpacing * 0.8 }
    private var smuflFontCandidates: [String] { SMuFL.fontCandidates }

    private func smuflFont(ofSize size: CGFloat) -> CTFont {
        return SMuFL.font(ofSize: size)
    }

    private func drawSMuFLText(_ ctx: CGContext, canvasHeight: CGFloat, text: String, at p: CGPoint, font: CTFont, alignCenter: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(gray: 0.0, alpha: 1.0)
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attr)
        ctx.saveGState()
        ctx.textMatrix = .identity
        // Flip to y-up for CoreText relative to our y-down canvas
        ctx.translateBy(x: 0, y: canvasHeight)
        ctx.scaleBy(x: 1, y: -1)
        // Position: convert y-down p.y to y-up coordinates, with optional center alignment using glyph path bounds
        var pos = CGPoint(x: p.x, y: canvasHeight - p.y)
        if alignCenter {
            let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            // Shift so that glyph center aligns to (p.x, p.y)
            pos.x -= bounds.midX
            pos.y -= bounds.midY
        }
        ctx.textPosition = pos
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private func drawTrebleClefSMuFL(in ctx: CGContext, canvasHeight: CGFloat, origin: CGPoint, staffSpacing: CGFloat) {
        let font = smuflFont(ofSize: staffSpacing * 4.6)
        let clefPoint = CGPoint(x: origin.x - staffSpacing * 0.8, y: origin.y + staffSpacing * 4.0)
        drawSMuFLText(ctx, canvasHeight: canvasHeight, text: SMuFL.trebleClef, at: clefPoint, font: font)
    }

    private func drawBassClefSMuFL(in ctx: CGContext, canvasHeight: CGFloat, origin: CGPoint, staffSpacing: CGFloat) {
        let font = smuflFont(ofSize: staffSpacing * 3.6)
        let clefPoint = CGPoint(x: origin.x - staffSpacing * 0.6, y: origin.y + staffSpacing * 2.0)
        drawSMuFLText(ctx, canvasHeight: canvasHeight, text: SMuFL.bassClef, at: clefPoint, font: font)
    }

    private func drawKeySignatureSMuFL(in ctx: CGContext, canvasHeight: CGFloat, origin: CGPoint, staffSpacing: CGFloat, clef: LayoutOptions.Clef, fifths: Int) {
        guard fifths != 0 else { return }
        let count = min(7, abs(fifths))
        let isSharp = fifths > 0
        let font = smuflFont(ofSize: staffSpacing * 1.3)
        let glyph = SMuFL.accidentalGlyph(for: isSharp ? 1 : -1)
        let steps = SMuFL.keySignatureSteps(clef: clef, isSharp: isSharp)
        let startX = origin.x + staffSpacing * 1.6
        let xStep = staffSpacing * 0.9
        for i in 0..<count {
            let step = steps[i]
            let y = origin.y + CGFloat(step) * (staffSpacing/2)
            let x = startX + CGFloat(i) * xStep
            drawSMuFLText(ctx, canvasHeight: canvasHeight, text: glyph, at: CGPoint(x: x, y: y), font: font)
        }
    }

    private func timeSigGlyph(for digit: Int) -> String {
        return SMuFL.timeSigGlyph(digit: digit)
    }

    private func drawTimeSignatureSMuFL(in ctx: CGContext, canvasHeight: CGFloat, origin: CGPoint, staffSpacing: CGFloat, time: (beatsPerBar: Int, beatUnit: Int)) {
        let font = smuflFont(ofSize: staffSpacing * 2.2)
        let x = origin.x + staffSpacing * 6.4
        // Numerator on top, denominator below, roughly centered in staff
        let numStr = String(time.beatsPerBar).compactMap { Int(String($0)) }
        let denStr = String(time.beatUnit).compactMap { Int(String($0)) }
        // Vertical anchors: center of staff
        let centerY = origin.y + staffSpacing * 2
        let numY = centerY - staffSpacing * 0.9
        let denY = centerY + staffSpacing * 1.0
        var advanceX: CGFloat = 0
        for d in numStr {
            let glyph = timeSigGlyph(for: d)
            drawSMuFLText(ctx, canvasHeight: canvasHeight, text: glyph, at: CGPoint(x: x + advanceX, y: numY), font: font, alignCenter: true)
            advanceX += staffSpacing * 1.2
        }
        advanceX = 0
        for d in denStr {
            let glyph = timeSigGlyph(for: d)
            drawSMuFLText(ctx, canvasHeight: canvasHeight, text: glyph, at: CGPoint(x: x + advanceX, y: denY), font: font, alignCenter: true)
            advanceX += staffSpacing * 1.2
        }
    }

    private func drawRestSMuFL(in ctx: CGContext, canvasHeight: CGFloat, at center: CGPoint, durationDen: Int, staffSpacing: CGFloat) {
        let font = smuflFont(ofSize: staffSpacing * 2.0)
        drawSMuFLText(ctx, canvasHeight: canvasHeight, text: SMuFL.restGlyph(forDen: durationDen), at: center, font: font, alignCenter: true)
    }
    private func drawAccidentalSMuFL(in ctx: CGContext, canvasHeight: CGFloat, at p: CGPoint, alter: Int, staffSpacing: CGFloat) {
        let font = smuflFont(ofSize: staffSpacing * 1.3)
        drawSMuFLText(ctx, canvasHeight: canvasHeight, text: SMuFL.accidentalGlyph(for: alter), at: p, font: font)
    }

    private func drawDynamicsSMuFL(in ctx: CGContext, canvasHeight: CGFloat, at center: CGPoint, level: DynamicLevel, staffSpacing: CGFloat) {
        let font = smuflFont(ofSize: staffSpacing * 1.6)
        let glyphs = SMuFL.dynamicsGlyphs(for: level)
        // Center the entire dynamic string on 'center'
        let advance = staffSpacing * 0.9
        let totalWidth = advance * CGFloat(max(0, glyphs.count - 1))
        var x = center.x - totalWidth / 2
        let y = center.y
        for g in glyphs {
            drawSMuFLText(ctx, canvasHeight: canvasHeight, text: g, at: CGPoint(x: x, y: y), font: font, alignCenter: true)
            x += advance
        }
    }

    private func smuflNoteheadGlyph(forDen den: Int) -> String {
        return SMuFL.noteheadGlyph(forDen: den)
    }

    private func drawNoteheadSMuFL(in ctx: CGContext, canvasHeight: CGFloat, at center: CGPoint, durationDen: Int, staffSpacing: CGFloat) {
        let glyph = smuflNoteheadGlyph(forDen: durationDen)
        let font = smuflFont(ofSize: staffSpacing * 1.6)
        drawSMuFLText(ctx, canvasHeight: canvasHeight, text: glyph, at: center, font: font, alignCenter: true)
    }

    private func noteheadHalfWidth(forDen den: Int, staffSpacing: CGFloat) -> CGFloat {
        let glyph = smuflNoteheadGlyph(forDen: den)
        let font = smuflFont(ofSize: staffSpacing * 1.6)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: glyph, attributes: attrs))
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        let w = max(bounds.width, staffSpacing * 1.2) // ensure sane fallback
        return w / 2
    }

    // MARK: - SMuFL flags
    private func flagGlyph(for flags: Int, stemUp: Bool) -> String? {
        return SMuFL.flagGlyph(flags: flags, stemUp: stemUp)
    }

    private func drawFlagSMuFL(in ctx: CGContext, canvasHeight: CGFloat, atStemX x: CGFloat, stemTipY y: CGFloat, stemUp: Bool, flags: Int, staffSpacing: CGFloat) {
        guard let glyph = flagGlyph(for: flags, stemUp: stemUp) else { return }
        // Position the glyph so its attachment point meets the stem tip, approximate with slight offset
        let font = smuflFont(ofSize: staffSpacing * 2.0)
        let attachment = CGPoint(x: x + (stemUp ? 0.0 : 0.0), y: y + (stemUp ? 0.0 : 0.0))
        drawSMuFLText(ctx, canvasHeight: canvasHeight, text: glyph, at: attachment, font: font, alignCenter: false)
    }
}
