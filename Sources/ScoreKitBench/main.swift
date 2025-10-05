import Foundation
import ScoreKit
import ScoreKitUI

func time(_ label: String, _ block: () -> Void) {
    let start = CFAbsoluteTimeGetCurrent()
    block()
    let dt = (CFAbsoluteTimeGetCurrent() - start) * 1000
    print("\(label): \(String(format: "%.2f", dt)) ms")
}

func makeEvents(count: Int, den: Int) -> [NotatedEvent] {
    var evs: [NotatedEvent] = []
    let steps: [Step] = [.C,.D,.E,.F,.G,.A,.B]
    for i in 0..<count {
        let st = steps[i % steps.count]
        evs.append(.init(base: .note(pitch: Pitch(step: st, alter: 0, octave: 4 + (i/steps.count)%2), duration: Duration(1, den))))
    }
    return evs
}

let renderer = SimpleRenderer()
var opts = LayoutOptions(); opts.timeSignature = (4,4)
let rect = CGRect(x: 0, y: 0, width: 1200, height: 300)

let configs: [(String, [NotatedEvent])] = [
    ("16 eighths", makeEvents(count: 16, den: 8)),
    ("32 sixteenths", makeEvents(count: 32, den: 16)),
    ("64 sixteenths", makeEvents(count: 64, den: 16)),
]

for (label, evs) in configs {
    time("layout (\(label))") {
        _ = renderer.layout(events: evs, in: rect, options: opts)
    }
}

// Microbench for incremental update
do {
    var evs = makeEvents(count: 32, den: 16)
    let base = renderer.layout(events: evs, in: rect, options: opts)
    // Single note duration change inside a measure
    evs[16] = .init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1, 8)))
    time("updateLayout (1 change @ idx16)") {
        _ = renderer.updateLayout(previous: base, events: evs, in: rect, options: opts, changed: [16])
    }
    // Span with slur across many notes (neighbor-span expansion)
    var evs2 = evs
    evs2[8].slurStart = true; evs2[20].slurEnd = true
    time("updateLayout (slur span 8..20)") {
        _ = renderer.updateLayout(previous: base, events: evs2, in: rect, options: opts, changed: Set(8...20))
    }
}
