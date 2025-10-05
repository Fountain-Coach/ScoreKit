import SwiftUI
import ScoreKit

public struct SemanticsInspectorView: View {
    public let index: Int?
    public let event: NotatedEvent?
    public let selectedRange: Set<Int>

    public let onUpdateEvent: (Int, NotatedEvent) -> Void
    public let onApplyRangeHairpin: (ClosedRange<Int>, Hairpin) -> Void
    public let onSetRangeDynamic: (ClosedRange<Int>, DynamicLevel) -> Void

    public init(index: Int?, event: NotatedEvent?, selectedRange: Set<Int>, onUpdateEvent: @escaping (Int, NotatedEvent) -> Void, onApplyRangeHairpin: @escaping (ClosedRange<Int>, Hairpin) -> Void, onSetRangeDynamic: @escaping (ClosedRange<Int>, DynamicLevel) -> Void) {
        self.index = index
        self.event = event
        self.selectedRange = selectedRange
        self.onUpdateEvent = onUpdateEvent
        self.onApplyRangeHairpin = onApplyRangeHairpin
        self.onSetRangeDynamic = onSetRangeDynamic
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Inspector").font(.headline)
                Spacer()
            }
            if let idx = index, let e = event {
                EventSection(index: idx, event: e)
            } else {
                Text("No selection").foregroundColor(.secondary)
            }
            Divider()
            RangeSection(selectedRange: selectedRange, onApplyRangeHairpin: onApplyRangeHairpin, onSetRangeDynamic: onSetRangeDynamic)
        }
        .padding(8)
    }

    @ViewBuilder private func EventSection(index: Int, event: NotatedEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Selected: #\(index)").font(.subheadline)
            // Dynamics
            HStack {
                Text("Dynamic:")
                Picker("Dynamic", selection: Binding(get: { event.dynamic ?? .mf }, set: { newVal in
                    var copy = event; copy.dynamic = newVal; onUpdateEvent(index, copy)
                })) {
                    ForEach([DynamicLevel.pp, .p, .mp, .mf, .f, .ff], id: \.self) { lvl in
                        Text(lvl.rawValue).tag(lvl)
                    }
                }.pickerStyle(.segmented)
            }
            // Articulations
            HStack {
                Toggle("Staccato", isOn: Binding(get: { event.articulations.contains(.staccato) }, set: { v in
                    var copy = event
                    toggle(&copy.articulations, .staccato, v); onUpdateEvent(index, copy)
                }))
                Toggle("Accent", isOn: Binding(get: { event.articulations.contains(.accent) }, set: { v in
                    var copy = event
                    toggle(&copy.articulations, .accent, v); onUpdateEvent(index, copy)
                }))
            }
            HStack {
                Toggle("Marcato", isOn: Binding(get: { event.articulations.contains(.marcato) }, set: { v in
                    var copy = event
                    toggle(&copy.articulations, .marcato, v); onUpdateEvent(index, copy)
                }))
                Toggle("Tenuto", isOn: Binding(get: { event.articulations.contains(.tenuto) }, set: { v in
                    var copy = event
                    toggle(&copy.articulations, .tenuto, v); onUpdateEvent(index, copy)
                }))
            }
        }
    }

    @ViewBuilder private func RangeSection(selectedRange: Set<Int>, onApplyRangeHairpin: @escaping (ClosedRange<Int>, Hairpin) -> Void, onSetRangeDynamic: @escaping (ClosedRange<Int>, DynamicLevel) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Range: \(selectedRange.isEmpty ? "none" : "\(selectedRange.min()!)–\(selectedRange.max()!)")").font(.subheadline)
            HStack {
                Button("Cresc ⟨⟩") {
                    if let a = selectedRange.min(), let b = selectedRange.max(), a < b { onApplyRangeHairpin(a...b, .crescendo) }
                }
                Button("Dim ⟩⟨") {
                    if let a = selectedRange.min(), let b = selectedRange.max(), a < b { onApplyRangeHairpin(a...b, .decrescendo) }
                }
            }
            HStack {
                ForEach([DynamicLevel.pp, .p, .mp, .mf, .f, .ff], id: \.self) { lvl in
                    Button(lvl.rawValue.uppercased()) {
                        if let a = selectedRange.min(), let b = selectedRange.max() { onSetRangeDynamic(a...b, lvl) }
                    }
                }
            }
        }
    }

    private func toggle(_ arr: inout [Articulation], _ t: Articulation, _ on: Bool) {
        if on { if !arr.contains(t) { arr.append(t) } }
        else { arr.removeAll { $0 == t } }
    }
}

