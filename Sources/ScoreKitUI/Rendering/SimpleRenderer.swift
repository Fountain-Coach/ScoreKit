import Foundation
import CoreGraphics
import SwiftUI
import ScoreKit

public struct LayoutOptions: Sendable {
    public var staffSpacing: CGFloat = 10 // distance between staff lines
    public var noteSpacing: CGFloat = 24  // nominal horizontal advance per event
    public var padding: CGSize = .init(width: 20, height: 20)
    public var barIndices: [Int] = []
    public var timeSignature: (beatsPerBar: Int, beatUnit: Int) = (4,4)
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

public struct LayoutTree: Sendable {
    public let size: CGSize
    public let elements: [LayoutElement]
    public let slurs: [LayoutSlur]
    public let hairpins: [LayoutHairpin]
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
    public init() {}

    public func layout(events: [NotatedEvent], in rect: CGRect, options: LayoutOptions) -> LayoutTree {
        let staffHeight = options.staffSpacing * 4 // 5 lines = 4 gaps
        var width = options.padding.width * 2
        let height = options.padding.height * 2 + staffHeight + 40 // extra for hairpins/ledger
        var elements: [LayoutElement] = []
        var slurs: [LayoutSlur] = []
        var hairpins: [LayoutHairpin] = []
        var barX: [CGFloat] = []
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
                    let yy = trebleYOffset(for: p, staffSpacing: options.staffSpacing, originY: origin.y)
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
        let (beamGroups, beamLevels) = computeBeams(elements: elements, beatPos: beatPos)
        return LayoutTree(size: CGSize(width: max(rect.width, width), height: max(rect.height, height)), elements: elements, slurs: slurs, hairpins: hairpins, barX: barX, beatPos: beatPos, beamGroups: beamGroups, beamLevels: beamLevels)
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

        // Draw notes/rests
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

        // Draw stems and basic flags for notes
        for el in tree.elements {
            guard case let .note(_, dur) = el.kind else { continue }
            // Stems up when the notehead is below the middle line (greater Y in screen coords)
            let stemUp = el.frame.midYVal > (options.padding.height + options.staffSpacing * 2)
            let stemLength: CGFloat = 30
            let x = stemUp ? el.frame.maxX : el.frame.minX
            let y1 = el.frame.midYVal
            let y2 = stemUp ? (y1 - stemLength) : (y1 + stemLength)
            ctx.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: x, y: y1))
            ctx.addLine(to: CGPoint(x: x, y: y2))
            ctx.strokePath()
            // flags for eighth and beyond
            let flags = flagCount(for: dur)
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

        // Draw beaming across consecutive eighth-or-shorter notes; break at beat boundaries
        var i = 0
        while i < tree.elements.count {
            guard case .note(_, let d) = tree.elements[i].kind, d.den >= 8 else { i += 1; continue }
            let startBeat = floor(tree.beatPos[i])
            var j = i + 1
            var group: [Int] = [i]
            while j < tree.elements.count, case .note(_, let d2) = tree.elements[j].kind, d2.den >= 8 {
                if floor(tree.beatPos[j]) != startBeat { break }
                group.append(j)
                j += 1
            }
            if group.count >= 2 {
                let yBase = tree.elements[group.first!].frame.midYVal
                let stemUp = yBase > (options.padding.height + options.staffSpacing * 2)
                let y = stemUp ? (tree.elements[group.first!].frame.midYVal - 30) : (tree.elements[group.first!].frame.midYVal + 30)
                ctx.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
                ctx.setLineWidth(3)
                let xStart = tree.elements[group.first!].frame.midXVal
                let xEnd = tree.elements[group.last!].frame.midXVal
                ctx.move(to: CGPoint(x: xStart, y: y))
                ctx.addLine(to: CGPoint(x: xEnd, y: y))
                ctx.strokePath()
                // second/third beams between adjacent notes depending on duration levels
                for k in 0..<(group.count - 1) {
                    let a = group[k]; let b = group[k+1]
                    let level = min(beamLevelFor(tree.elements[a]), beamLevelFor(tree.elements[b]))
                    if level >= 2 {
                        let y2 = stemUp ? y - 4 : y + 4
                        ctx.setLineWidth(2)
                        ctx.move(to: CGPoint(x: tree.elements[a].frame.midXVal, y: y2))
                        ctx.addLine(to: CGPoint(x: tree.elements[b].frame.midXVal, y: y2))
                        ctx.strokePath()
                    }
                    if level >= 3 {
                        let y3 = stemUp ? y - 8 : y + 8
                        ctx.setLineWidth(2)
                        ctx.move(to: CGPoint(x: tree.elements[a].frame.midXVal, y: y3))
                        ctx.addLine(to: CGPoint(x: tree.elements[b].frame.midXVal, y: y3))
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
                else { let yy = trebleYOffset(for: p, staffSpacing: options.staffSpacing, originY: origin.y); yCache[p] = yy; y = yy }
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

        // Slurs/hairpins: recompute globally (cheap) for correctness across boundaries
        var slurs: [LayoutSlur] = []
        var hairpins: [LayoutHairpin] = []
        for i in 0..<events.count {
            if events[i].slurStart, let end = events[(i+1)...].firstIndex(where: { $0.slurEnd }) { slurs.append(LayoutSlur(startIndex: i, endIndex: end)) }
            if let hp = events[i].hairpinStart, let end = events[(i+1)...].firstIndex(where: { $0.hairpinEnd }) { hairpins.append(LayoutHairpin(startIndex: i, endIndex: end, crescendo: hp == .crescendo)) }
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
        let (beamGroups, beamLevels) = computeBeams(elements: newElements, beatPos: newBeatPos)
        return LayoutTree(size: CGSize(width: newWidth, height: newHeight), elements: newElements, slurs: slurs, hairpins: hairpins, barX: newBarX, beatPos: newBeatPos, beamGroups: beamGroups, beamLevels: beamLevels)
    }

    // MARK: - Helpers
    // Very rough treble clef mapping: E4 on bottom line; middle C (C4) one ledger below.
    private func trebleYOffset(for p: Pitch, staffSpacing: CGFloat, originY: CGFloat) -> CGFloat {
        // Map semitone distance from C4 in diatonic steps for staff position approximation.
        let stepIndex: Int
        switch p.step { case .C: stepIndex = 0; case .D: stepIndex = 1; case .E: stepIndex = 2; case .F: stepIndex = 3; case .G: stepIndex = 4; case .A: stepIndex = 5; case .B: stepIndex = 6 }
        let diatonic = (p.octave - 4) * 7 + stepIndex // C4 = 0
        // Each diatonic step = half a staff space (line/space). ledger below grows negative.
        let c4Y = originY + staffSpacing * 5 // place C4 below staff by two spaces
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

    private func computeBeams(elements: [LayoutElement], beatPos: [Double]) -> ([[Int]], [Int]) {
        var groups: [[Int]] = []
        var levels: [Int] = Array(repeating: 0, count: elements.count)
        var i = 0
        while i < elements.count {
            guard i < beatPos.count else { break }
            guard case .note(_, let d) = elements[i].kind, d.den >= 8 else { i += 1; continue }
            levels[i] = beamLevelFor(elements[i])
            let startBeat = intBeatIndex(beatPos[i])
            var j = i + 1
            var group: [Int] = [i]
            while j < elements.count, j < beatPos.count {
                guard case .note(_, let d2) = elements[j].kind, d2.den >= 8 else { break }
                if intBeatIndex(beatPos[j]) != startBeat { break }
                levels[j] = beamLevelFor(elements[j])
                group.append(j)
                j += 1
            }
            if group.count >= 2 { groups.append(group) }
            i = j
        }
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
