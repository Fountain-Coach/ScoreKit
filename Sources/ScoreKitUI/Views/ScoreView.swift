import SwiftUI
import ScoreKit

@MainActor
public struct ScoreView: View {
    private let events: [NotatedEvent]
    private let barIndices: [Int]
    private let renderer = SimpleRenderer()
    private let onSelect: ((Int?) -> Void)?
    private let selectedBinding: Binding<Int?>?
    @ObservedObject private var highlighter: ScoreHighlighter
    @State private var selected: Int? = nil

    public init(events: [NotatedEvent], barIndices: [Int] = [], highlighter: ScoreHighlighter? = nil, selection: Binding<Int?>? = nil, onSelect: ((Int?) -> Void)? = nil) {
        self.events = events
        self.barIndices = barIndices
        self.onSelect = onSelect
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
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                var opts = LayoutOptions()
                opts.barIndices = barIndices
                let rect = CGRect(origin: .zero, size: proxy.size)
                let tree = renderer.layout(events: events, in: rect, options: opts)
                let hit = renderer.hitTest(tree, at: value.location)
                let newSel = hit?.index
                selected = newSel
                selectedBinding?.wrappedValue = newSel
                onSelect?(newSel)
                if let idx = newSel { highlighter.flash(indices: [idx]) }
            })
        }
        .frame(minHeight: 160)
        .background(Color(nsColor: .textBackgroundColor))
        .padding()
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
