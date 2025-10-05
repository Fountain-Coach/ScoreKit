import Foundation
import ScoreKitUI

public enum CueAction {
    case flashIndices(Set<Int>, TimeInterval)
    case flashRange(ClosedRange<Int>, TimeInterval)
    case pulse(Set<Int>, Int, TimeInterval)
    case focus(Int?)
}

public struct Cue {
    public let at: TimeInterval
    public let action: CueAction
    public init(at: TimeInterval, action: CueAction) { self.at = at; self.action = action }
}

@MainActor
public final class StoryboardPlayer: ObservableObject {
    @Published public private(set) var isPlaying: Bool = false
    private var work: [DispatchWorkItem] = []

    public init() {}

    public func play(cues: [Cue], controller: ScoreController) {
        stop()
        isPlaying = true
        let start = DispatchTime.now()
        for cue in cues {
            let item = DispatchWorkItem { [weak controller] in
                guard let controller = controller else { return }
                switch cue.action {
                case let .flashIndices(idx, dur): controller.flash(indices: idx, duration: dur)
                case let .flashRange(range, dur): controller.flash(range: range, duration: dur)
                case let .pulse(idx, cycles, period): controller.pulse(indices: idx, cycles: cycles, period: period)
                case let .focus(i): controller.focus(index: i)
                }
            }
            work.append(item)
            DispatchQueue.main.asyncAfter(deadline: start + cue.at, execute: item)
        }
        // Mark complete at the last cue time + small epsilon
        if let last = cues.map({ $0.at }).max() {
            let done = DispatchWorkItem { [weak self] in self?.isPlaying = false }
            work.append(done)
            DispatchQueue.main.asyncAfter(deadline: start + last + 0.1, execute: done)
        }
    }

    public func stop() {
        for w in work { w.cancel() }
        work.removeAll()
        isPlaying = false
    }
}

