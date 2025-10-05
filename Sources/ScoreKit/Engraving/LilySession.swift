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

    /// Renders LilyPond source. By default, only writes `.ly` to disk.
    /// Set `execute` to true to attempt running `lilypond` to produce a PDF.
    public func render(lySource: String, workdir: URL? = nil, timeout: TimeInterval = 20, execute: Bool = false) throws -> LilyArtifacts {
        let wd = workdir ?? FileManager.default.temporaryDirectory.appendingPathComponent("ScoreKit.LilySession", isDirectory: true)
        try FileManager.default.createDirectory(at: wd, withIntermediateDirectories: true)
        let lyURL = wd.appendingPathComponent("score.ly")
        try lySource.write(to: lyURL, atomically: true, encoding: .utf8)

        guard execute else {
            return LilyArtifacts(lyURL: lyURL, pdfURL: nil, svgURLs: [])
        }

        guard let lily = LilySession.findLilypond() else {
            throw LilySessionError.lilypondNotFound
        }

        let outPrefix = wd.appendingPathComponent("score").path
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: lily)
        proc.arguments = [
            "-dno-point-and-click",
            "--silent",
            "-o", outPrefix,
            lyURL.path
        ]
        let stderrPipe = Pipe()
        proc.standardError = stderrPipe
        proc.standardOutput = Pipe()

        try proc.run()

        // Basic timeout handling
        let finished = wait(process: proc, timeout: timeout)
        if !finished {
            proc.terminate()
        }

        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let errStr = String(data: errData, encoding: .utf8) ?? ""

        if proc.terminationStatus != 0 {
            throw LilySessionError.processFailed(code: proc.terminationStatus, stderr: errStr)
        }

        let pdfURL = wd.appendingPathComponent("score.pdf")
        let pdf = FileManager.default.fileExists(atPath: pdfURL.path) ? pdfURL : nil
        // SVG generation not enabled by default in this MVP
        return LilyArtifacts(lyURL: lyURL, pdfURL: pdf, svgURLs: [])
    }

    private static func findLilypond() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let explicit = env["SCOREKIT_LILYPOND"], !explicit.isEmpty, FileManager.default.isExecutableFile(atPath: explicit) {
            return explicit
        }
        let candidates = [
            "/opt/homebrew/bin/lilypond",
            "/usr/local/bin/lilypond",
            "/usr/bin/lilypond"
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        // try `which` as last resort
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["lilypond"]
        let pipe = Pipe(); which.standardOutput = pipe
        try? which.run(); which.waitUntilExit()
        if which.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                if FileManager.default.isExecutableFile(atPath: path) { return path }
            }
        }
        return nil
    }

    private func wait(process: Process, timeout: TimeInterval) -> Bool {
        let start = Date()
        while process.isRunning {
            Thread.sleep(forTimeInterval: 0.05)
            if Date().timeIntervalSince(start) > timeout { return false }
        }
        return true
    }
}
