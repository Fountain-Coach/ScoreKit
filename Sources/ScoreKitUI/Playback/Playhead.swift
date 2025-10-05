import Foundation
import Combine
import ScoreKit

@MainActor
public final class Playhead: ObservableObject {
    @Published public private(set) var index: Int = 0
    @Published public private(set) var isPlaying: Bool = false
    private var timer: Timer?

    public init() {}

    /// Drive the playhead visually over events using tempo and an optional callback.
    public func start(events: [NotatedEvent], tempo: Tempo, tick: @escaping (Int) -> Void) {
        stop()
        guard !events.isEmpty else { return }
        isPlaying = true; index = 0
        let baseInterval = tempo.secondsPerQuarter
        scheduleTick(events: events, base: baseInterval, tick: tick)
    }

    public func stop() {
        timer?.invalidate(); timer = nil; isPlaying = false
    }

    private func scheduleTick(events: [NotatedEvent], base: TimeInterval, tick: @escaping (Int) -> Void) {
        func durationSeconds(_ d: Duration) -> TimeInterval { (Double(d.num)/Double(d.den)) * 4.0 * base }
        func nextInterval(at i: Int) -> TimeInterval {
            guard i < events.count else { return 0 }
            switch events[i].base {
            case .note(_, let d): return durationSeconds(d)
            case .rest(let d): return durationSeconds(d)
            }
        }
        tick(index)
        let interval = nextInterval(at: index)
        timer = Timer.scheduledTimer(withTimeInterval: max(0.01, interval), repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            Task { @MainActor in
                self.index += 1
                if self.index >= events.count { t.invalidate(); self.isPlaying = false; return }
                tick(self.index)
                t.invalidate()
                self.scheduleTick(events: events, base: base, tick: tick)
            }
        }
        if let tm = timer { RunLoop.main.add(tm, forMode: .common) }
    }
}
