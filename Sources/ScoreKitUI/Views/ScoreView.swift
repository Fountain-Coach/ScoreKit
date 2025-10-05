import SwiftUI
import ScoreKit

@MainActor
public struct ScoreView: View {
    private let events: [NotatedEvent]
    private let barIndices: [Int]
    private let renderer = SimpleRenderer()
    private let onSelect: ((Int?) -> Void)?
    private let onSelectRange: ((Set<Int>) -> Void)?
    private let selectedBinding: Binding<Int?>?
    @ObservedObject private var highlighter: ScoreHighlighter
    @State private var selected: Int? = nil
    @State private var dragRect: CGRect? = nil
    @State private var selectedRange: Set<Int> = []
    @State private var isHovering: Bool = false
    @State private var resizeMode: Int? = nil // -1 left, +1 right

    public init(events: [NotatedEvent], barIndices: [Int] = [], highlighter: ScoreHighlighter? = nil, selection: Binding<Int?>? = nil, onSelect: ((Int?) -> Void)? = nil, onSelectRange: ((Set<Int>) -> Void)? = nil) {
        self.events = events
        self.barIndices = barIndices
        self.onSelect = onSelect
        self.onSelectRange = onSelectRange
        self.selectedBinding = selection
        self._highlighter = ObservedObject(initialValue: highlighter ?? ScoreHighlighter())
    }

    public var body: some View {
        GeometryReader { proxy in
            Canvas { ctx, size in
                var opts = LayoutOptions()
                opts.barIndices = barIndices
                let rect = CGRect(origin: .zero, size: size)
                let tree = renderer.layout(events: events, in: rect, options: opts)
                ctx.withCGContext { cg in
                    renderer.draw(tree, in: cg, options: opts)
                    // Selection highlight
                    let selIndex = selectedBinding?.wrappedValue ?? selected
                    if let sel = selIndex, sel >= 0, sel < tree.elements.count {
                        let frame = tree.elements[sel].frame.insetBy(dx: -4, dy: -4)
                        cg.setStrokeColor(CGColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0))
                        cg.setLineWidth(2)
                        cg.stroke(frame)
                    }
                    // Flash highlights
                    if highlighter.opacity > 0.0, !highlighter.indices.isEmpty {
                        cg.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 1.0, alpha: highlighter.opacity * 0.35))
                        for idx in highlighter.indices {
                            if idx >= 0, idx < tree.elements.count {
                                let f = tree.elements[idx].frame.insetBy(dx: -10, dy: -10)
                                cg.fill(f)
                            }
                        }
                    }
                    // Range handles
                    if selectedRange.count >= 2 {
                        let sorted = selectedRange.sorted()
                        if let a = sorted.first, let b = sorted.last, a >= 0, b < tree.elements.count {
                            let left = tree.elements[a].frame
                            let right = tree.elements[b].frame
                            let handleL = CGRect(x: left.minX - 6, y: left.minY - 8, width: 8, height: 16)
                            let handleR = CGRect(x: right.maxX - 2, y: right.minY - 8, width: 8, height: 16)
                            cg.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 1.0, alpha: 1.0))
                            cg.fill(handleL); cg.fill(handleR)
                        }
                    }
                    #if os(macOS)
                    // Tooltip near selection when hovering
                    if isHovering, let i = (selected ?? selectedBinding?.wrappedValue), i >= 0, i < tree.elements.count {
                        let f = tree.elements[i].frame
                        let info = tooltipInfo(for: events[i])
                        ctx.draw(Text(info).font(.caption2), at: CGPoint(x: f.midXVal + 12, y: max(12, f.minY - 18)))
                    }
                    #endif
                    // Drag selection overlay
                    if let drag = dragRect {
                        cg.setStrokeColor(CGColor(red: 0.0, green: 0.6, blue: 1.0, alpha: 0.8))
                        cg.setLineWidth(1)
                        cg.stroke(drag)
                        cg.setFillColor(CGColor(red: 0.0, green: 0.6, blue: 1.0, alpha: 0.15))
                        cg.fill(drag)
                    }
                }
            }
            .contentShape(Rectangle())
            #if os(macOS)
            .onHover { h in isHovering = h }
            #endif
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        var opts = LayoutOptions(); opts.barIndices = barIndices
                        let rect = CGRect(origin: .zero, size: proxy.size)
                        let tree = renderer.layout(events: events, in: rect, options: opts)
                        if resizeMode == nil, selectedRange.count >= 2 {
                            let sorted = selectedRange.sorted(); let a = sorted.first!; let b = sorted.last!
                            let left = tree.elements[a].frame
                            let right = tree.elements[b].frame
                            let handleL = CGRect(x: left.minX - 6, y: left.minY - 8, width: 8, height: 16)
                            let handleR = CGRect(x: right.maxX - 2, y: right.minY - 8, width: 8, height: 16)
                            if handleL.insetBy(dx: -6, dy: -6).contains(value.startLocation) { resizeMode = -1 }
                            else if handleR.insetBy(dx: -6, dy: -6).contains(value.startLocation) { resizeMode = 1 }
                        }
                        if let mode = resizeMode {
                            // Snap to nearest element index
                            if let ni = nearestIndex(atX: value.location.x, in: tree) {
                                let sorted = selectedRange.sorted(); guard let a = sorted.first, let b = sorted.last else { return }
                                if mode < 0 { let minI = min(ni, b); let maxI = max(ni, b); selectedRange = Set(minI...maxI) }
                                else { let minI = min(a, ni); let maxI = max(a, ni); selectedRange = Set(minI...maxI) }
                            }
                        } else {
                            let s = value.startLocation; let e = value.location
                            dragRect = CGRect(x: min(s.x, e.x), y: min(s.y, e.y), width: abs(e.x - s.x), height: abs(e.y - s.y))
                        }
                    }
                    .onEnded { value in
                        var opts = LayoutOptions(); opts.barIndices = barIndices
                        let rect = CGRect(origin: .zero, size: proxy.size)
                        let tree = renderer.layout(events: events, in: rect, options: opts)
                        if let _ = resizeMode {
                            onSelectRange?(selectedRange)
                        } else if let drag = dragRect, drag.width > 3 && drag.height > 3 {
                            let set = Set(tree.elements.filter { $0.frame.intersects(drag) }.map { $0.index })
                            onSelectRange?(set)
                            selectedRange = set
                            if !set.isEmpty { highlighter.flash(indices: set) }
                        } else {
                            let hit = renderer.hitTest(tree, at: value.location)
                            let newSel = hit?.index
                            selected = newSel
                            selectedBinding?.wrappedValue = newSel
                            onSelect?(newSel)
                            if let idx = newSel { highlighter.flash(indices: [idx]) }
                        }
                        dragRect = nil; resizeMode = nil
                    }
            )
        }
        .frame(minHeight: 160)
        .background(Color(nsColor: .textBackgroundColor))
        .padding()
    }

    private func nearestIndex(atX x: CGFloat, in tree: LayoutTree) -> Int? {
        var best: (Int, CGFloat)?
        best = nil
        for el in tree.elements {
            let dx = abs(el.frame.midXVal - x)
            if best == nil || dx < best!.1 { best = (el.index, dx) }
        }
        return best?.0
    }

    private func tooltipInfo(for e: NotatedEvent) -> String {
        var parts: [String] = []
        switch e.base {
        case .note(let p, let d):
            parts.append("Note \(p.step.rawValue)\(p.alter == 1 ? "#" : (p.alter == -1 ? "b" : ""))\(p.octave)")
            parts.append("1/\(d.den)")
        case .rest(let d):
            parts.append("Rest 1/\(d.den)")
        }
        if !e.articulations.isEmpty { parts.append(e.articulations.map { String(describing: $0) }.joined(separator: ",")) }
        if let dyn = e.dynamic { parts.append(dyn.rawValue) }
        if e.slurStart || e.slurEnd { parts.append("slur") }
        if e.tieStart || e.tieEnd { parts.append("tie") }
        if let hp = e.hairpinStart { parts.append(hp == .crescendo ? "<" : ">") }
        if e.hairpinEnd { parts.append("!") }
        return parts.joined(separator: "  •  ")
    }
}

#if DEBUG
struct ScoreView_Previews: PreviewProvider {
    static var previews: some View {
        let base: [NotatedEvent] = [
            .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,4)), hairpinStart: .crescendo),
            .init(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1,4)), slurStart: true),
            .init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,4)), slurEnd: true, hairpinEnd: true),
            .init(base: .rest(duration: Duration(1,4)))
        ]
        return ScoreView(events: base, barIndices: [2])
    }
}
#endif
