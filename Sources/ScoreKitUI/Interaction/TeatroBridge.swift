import Foundation

@MainActor
public protocol TeatroBridge: AnyObject {
    func flash(indices: Set<Int>, duration: TimeInterval)
    func flash(range: ClosedRange<Int>, duration: TimeInterval)
    func pulse(indices: Set<Int>, cycles: Int, period: TimeInterval)
    func focus(index: Int?)
}

@MainActor
public final class ScoreController: ObservableObject, TeatroBridge {
    public let highlighter: ScoreHighlighter
    @Published public var selected: Int? = nil

    public init(highlighter: ScoreHighlighter) {
        self.highlighter = highlighter
    }

    public func flash(indices: Set<Int>, duration: TimeInterval = 0.8) {
        highlighter.flash(indices: indices, duration: duration)
    }

    public func flash(range: ClosedRange<Int>, duration: TimeInterval = 0.8) {
        highlighter.flash(range: range, duration: duration)
    }

    public func pulse(indices: Set<Int>, cycles: Int = 2, period: TimeInterval = 0.6) {
        highlighter.pulse(indices: indices, cycles: cycles, period: period)
    }

    public func focus(index: Int?) {
        selected = index
        if let i = index { flash(indices: [i], duration: 0.6) }
    }
}
