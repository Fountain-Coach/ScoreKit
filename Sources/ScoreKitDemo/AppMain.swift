import SwiftUI
import ScoreKit
import ScoreKitUI

@main
struct ScoreKitDemoApp: App {
    var body: some Scene {
        WindowGroup {
            DemoView()
        }
    }
}

struct DemoView: View {
    @State private var events: [NotatedEvent] = [
        .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,8)), hairpinStart: .crescendo),
        .init(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1,8)), slurStart: true, articulations: [.staccato]),
        .init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,8)), slurEnd: true, hairpinEnd: true, dynamic: .mf),
        .init(base: .rest(duration: Duration(1,4)))
    ]
    @State private var bars: [Int] = [3]
    @StateObject private var highlighter = ScoreHighlighter()
    @State private var selected: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ScoreKit Demo").font(.title2).padding(.top, 4)
            ScoreView(events: events, barIndices: bars, highlighter: highlighter) { sel in
                selected = sel
            }
            HStack {
                Button("Flash bars 1–2") {
                    let idx: Set<Int> = [0,1,2]
                    highlighter.flash(indices: idx, duration: 0.8)
                }
                Button("Random flash") {
                    let idx = Int.random(in: 0..<events.count)
                    highlighter.flash(indices: [idx], duration: 0.6)
                }
                Button("Add staccato to sel") {
                    if let i = selected {
                        var v = Voice(events: events)
                        let (nv, _) = Transform.addArticulation(to: v, index: i, articulation: .staccato)
                        events = nv.events
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(minWidth: 640, minHeight: 360)
    }
}

