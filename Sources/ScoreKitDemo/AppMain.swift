import SwiftUI
import ScoreKit
import ScoreKitUI
import Foundation
import Combine

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
    @State private var lastRange: Set<Int> = []
    @State private var selectedDest: Int = 0
    @State private var selectedEvent: NotatedEvent? = nil
    @State private var inspectorCancellable: AnyCancellable?
    @State private var previewSession: AudioTalkPreviewSession? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ScoreKit Demo").font(.title2).padding(.top, 4)
            ScoreView(events: events, barIndices: bars, highlighter: controller.highlighter, selection: $controller.selected, onSelect: { sel in
                selected = sel
            }, onSelectRange: { set in
                lastRange = set
            })
            SemanticsInspectorView(index: selected, event: selectedEvent, selectedRange: lastRange, onUpdateEvent: { idx, newEvent in
                guard idx >= 0 && idx < events.count else { return }
                var copy = events
                copy[idx] = newEvent
                events = copy
            }, onApplyRangeHairpin: { range, type in
                guard !events.isEmpty else { return }
                var copy = events
                let a = max(0, range.lowerBound); let b = min(copy.count - 1, range.upperBound)
                if a < b {
                    copy[a].hairpinStart = type
                    copy[b].hairpinEnd = true
                    events = copy
                }
            }, onSetRangeDynamic: { range, level in
                var copy = events
                for i in range { if i >= 0 && i < copy.count { copy[i].dynamic = level } }
                events = copy
            })
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
                Divider()
                Button("UMP → Console") {
                    let engine = PlaybackEngine()
                    let sink = CollectingSink()
                    try? engine.schedule(events: events, channel: 0, tempo: Tempo(bpm: bpm), startTime: 0, sink: sink)
                    // Encode and dump
                    var all: [UInt32] = []
                    for item in sink.scheduled {
                        switch item.message {
                        case .noteOn, .noteOff:
                            all.append(contentsOf: UMPEncoder.encode(item.message, group: 0, mode: .midi2_64bit))
                        default: continue
                        }
                    }
                    print("UMP64:", UMPDump.hexWords(all))
                }
                Button("Run AI Preview") {
                    // Simulate AI ops: crescendo across scale + slur last 4 + set mp on first
                    if previewSession == nil { previewSession = AudioTalkPreviewSession(events: events) }
                    let ops: [PatchOp] = [
                        .hairpin(start: 0, end: max(0, events.count - 1), type: .crescendo),
                        .slur(start: max(0, events.count - 4), end: max(0, events.count - 1)),
                        .dynamic(index: 0, level: .mp)
                    ]
                    if let session = previewSession {
                        let (ev, changed) = session.apply(ops: ops)
                        events = ev
                        controller.flash(indices: changed, duration: 0.9)
                    }
                }
#if canImport(CoreMIDI)
                // Destination picker
                if let sender = CoreMIDISender() {
                    let count = sender.destinationCount()
                    if count > 0 {
                        Picker("Dest", selection: $selectedDest) {
                            ForEach(0..<count, id: \.self) { idx in
                                Text(sender.destinationName(at: idx) ?? "Dest #\(idx)").tag(idx)
                            }
                        }.frame(width: 240)
                    } else {
                        Text("No CoreMIDI destinations").foregroundColor(.secondary)
                    }
                } else {
                    Text("CoreMIDI unavailable").foregroundColor(.secondary)
                }
                Button("UMP → CoreMIDI (dest 0)") {
                    let engine = PlaybackEngine()
                    let sink = CollectingSink()
                    try? engine.schedule(events: events, channel: 0, tempo: Tempo(bpm: bpm), startTime: 0, sink: sink)
                    let sender = CoreMIDISender()
                    var scheduled: [(TimeInterval, [UInt32])] = []
                    for it in sink.scheduled {
                        let words = UMPEncoder.encode(it.message, group: 0, mode: .midi2_64bit)
                        scheduled.append((it.time, words))
                    }
                    // Best-effort: send immediately ignoring schedule
                    for (_, words) in scheduled { sender?.sendUMP(words: words, to: selectedDest) }
                }
#endif
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(minWidth: 640, minHeight: 360)
        .onAppear { buildStoryboard() }
        .onReceive(Just(selected)) { newSel in
            if let i = newSel, i >= 0 && i < events.count { selectedEvent = events[i] } else { selectedEvent = nil }
        }
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
