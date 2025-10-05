import SwiftUI
import ScoreKit

public struct ScoreView: View {
    private let events: [NotatedEvent]
    private let renderer = SimpleRenderer()
    private let options = LayoutOptions()

    public init(events: [NotatedEvent]) {
        self.events = events
    }

    public var body: some View {
        GeometryReader { proxy in
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                let tree = renderer.layout(events: events, in: rect, options: options)
                ctx.withCGContext { cg in
                    renderer.draw(tree, in: cg, options: options)
                }
            }
        }
        .frame(minHeight: 160)
        .background(Color(NSColor.textBackgroundColor))
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
        return ScoreView(events: base)
    }
}
#endif
