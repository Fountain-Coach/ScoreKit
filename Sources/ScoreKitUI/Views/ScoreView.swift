import SwiftUI
import ScoreKit

public struct ScoreView: View {
    private let events: [NotatedEvent]
    private let barIndices: [Int]
    private let renderer = SimpleRenderer()
    private let onSelect: ((Int?) -> Void)?
    @State private var selected: Int? = nil

    public init(events: [NotatedEvent], barIndices: [Int] = [], onSelect: ((Int?) -> Void)? = nil) {
        self.events = events
        self.barIndices = barIndices
        self.onSelect = onSelect
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
                    if let sel = selected, sel >= 0, sel < tree.elements.count {
                        let frame = tree.elements[sel].frame.insetBy(dx: -4, dy: -4)
                        cg.setStrokeColor(CGColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0))
                        cg.setLineWidth(2)
                        cg.stroke(frame)
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
                selected = hit?.index
                onSelect?(selected)
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
