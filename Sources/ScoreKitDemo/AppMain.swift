import SwiftUI
import ScoreKit
import ScoreKitUI
import Foundation

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
    @StateObject private var controller = ScoreController(highlighter: ScoreHighlighter())
    @State private var selected: Int? = nil
    @StateObject private var player = StoryboardPlayer()
    @State private var cues: [Cue] = []
    @StateObject private var playhead = Playhead()
    @State private var bpm: Double = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ScoreKit Demo").font(.title2).padding(.top, 4)
            ScoreView(events: events, barIndices: bars, highlighter: controller.highlighter, selection: $controller.selected) { sel in
                selected = sel
            }
            HStack {
                // Playback controls
                Button(playhead.isPlaying ? "Stop Playhead" : "Start Playhead") {
                    if playhead.isPlaying { playhead.stop() }
                    else {
                        let t = Tempo(bpm: bpm)
                        playhead.start(events: events, tempo: t) { idx in
                            controller.focus(index: idx)
                        }
                    }
                }
                Stepper("BPM: \(Int(bpm))", value: $bpm, in: 40...220, step: 5)
                Divider()
                Button("Flash bars 1–2") {
                    let idx: Set<Int> = [0,1,2]
                    controller.flash(indices: idx, duration: 0.8)
                }
                Button("Random flash") {
                    let idx = Int.random(in: 0..<events.count)
                    controller.flash(indices: [idx], duration: 0.6)
                }
                Button("Pulse melody") { controller.pulse(indices: [0,1,2], cycles: 3, period: 0.5) }
                Button("Add staccato to sel") {
                    if let i = selected {
                        let v = Voice(events: events)
                        let (nv, _) = Transform.addArticulation(to: v, index: i, articulation: .staccato)
                        events = nv.events
                    }
                }
                Button("Focus #2") { controller.focus(index: 2) }
                Button(player.isPlaying ? "Stop Storyboard" : "Play Storyboard") {
                    if player.isPlaying { player.stop() }
                    else { buildStoryboard(); player.play(cues: cues, controller: controller) }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(minWidth: 640, minHeight: 360)
        .onAppear { buildStoryboard() }
    }

    private func buildStoryboard() {
        // Simple scripted sequence demonstrating cues
        var seq: [Cue] = []
        seq.append(.init(at: 0.0, action: .focus(0)))
        seq.append(.init(at: 0.2, action: .flashIndices([0,1,2], 0.9)))
        seq.append(.init(at: 1.2, action: .pulse([0,1,2], 2, 0.45)))
        seq.append(.init(at: 2.0, action: .focus(2)))
        seq.append(.init(at: 2.2, action: .flashRange(0...3, 0.8)))
        seq.append(.init(at: 3.0, action: .focus(nil)))
        // random last highlight
        let r = Int.random(in: 0..<events.count)
        seq.append(.init(at: 3.4, action: .flashIndices([r], 0.6)))
        cues = seq
    }
}
