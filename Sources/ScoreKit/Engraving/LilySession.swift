import Foundation

public enum LilySessionError: Error, Sendable {
    case lilypondNotFound
    case processFailed(code: Int32, stderr: String)
}

public struct LilyArtifacts: Sendable {
    public let lyURL: URL
    public let pdfURL: URL?
    public let svgURLs: [URL]
}

public struct LilySession {
    public init() {}

    public func render(lySource: String, workdir: URL? = nil, timeout: TimeInterval = 20) throws -> LilyArtifacts {
        // Stub implementation; will be completed in Milestone M1.
        // For now, write the .ly to temp and return its URL without invoking LilyPond.
        let wd = workdir ?? FileManager.default.temporaryDirectory.appendingPathComponent("ScoreKit.LilySession", isDirectory: true)
        try? FileManager.default.createDirectory(at: wd, withIntermediateDirectories: true)
        let lyURL = wd.appendingPathComponent("score.ly")
        try lySource.write(to: lyURL, atomically: true, encoding: .utf8)
        return LilyArtifacts(lyURL: lyURL, pdfURL: nil, svgURLs: [])
    }
}

