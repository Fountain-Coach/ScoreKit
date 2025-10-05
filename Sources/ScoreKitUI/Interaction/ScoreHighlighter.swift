import Foundation
import Combine

@MainActor
public final class ScoreHighlighter: ObservableObject {
    @Published public private(set) var indices: Set<Int> = []
    @Published public private(set) var opacity: Double = 0.0
    private var timer: Timer?

    public init() {}

    public func clear() {
        timer?.invalidate(); timer = nil
        indices = []
        opacity = 0.0
    }

    public func flash(indices: Set<Int>, duration: TimeInterval = 0.8) {
        guard !indices.isEmpty else { return }
        self.indices = indices
        self.opacity = 1.0
        timer?.invalidate()
        let steps = 20
        let interval = duration / Double(steps)
        var remaining = steps
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            remaining -= 1
            let progress = 1.0 - (Double(remaining) / Double(steps))
            Task { @MainActor in
                self.opacity = max(0.0, 1.0 - progress)
                if remaining <= 0 {
                    t.invalidate()
                    self.opacity = 0.0
                    self.indices = []
                }
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
}
