import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ScoreKit
import ScoreKitUI

func envEndpoint() -> URL? {
    if let s = ProcessInfo.processInfo.environment["RULES_ENDPOINT"], let u = URL(string: s), !s.isEmpty { return u }
    return nil
}

func makeContext(size: CGSize) -> CGContext {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerRow = Int(size.width) * 4
    let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    // Fill a white background so our black strokes are visible in PNGs
    ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
    ctx.fill(CGRect(origin: .zero, size: size))
    return ctx
}

func writePNG(_ img: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

let baseDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Snapshots", isDirectory: true)
let subdir = ProcessInfo.processInfo.environment["SCOREKIT_SNAP_SUBDIR"].flatMap { s in s.isEmpty ? nil : s }
let outDir: URL = {
    if let sub = subdir { return baseDir.appendingPathComponent(sub, isDirectory: true) }
    return baseDir
}()
if ProcessInfo.processInfo.environment["SCOREKIT_SNAP_CLEAN"] == "1" {
    if FileManager.default.fileExists(atPath: outDir.path) {
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: outDir.path) {
            for name in contents { try? FileManager.default.removeItem(at: outDir.appendingPathComponent(name)) }
        }
    }
}
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func resolveTag() -> String {
    let env = ProcessInfo.processInfo.environment
    if let t = env["SCOREKIT_SNAP_TAG"], !t.isEmpty { return t }
    // Try git short hash
    let git = Process()
    git.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    git.arguments = ["git", "rev-parse", "--short", "HEAD"]
    let pipe = Pipe(); git.standardOutput = pipe
    try? git.run(); git.waitUntilExit()
    if git.terminationStatus == 0 {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
    }
    // Fallback timestamp
    let fmt = DateFormatter(); fmt.dateFormat = "yyyyMMdd-HHmmss"
    return fmt.string(from: Date())
}
let SNAP_TAG = resolveTag()

// Snapshot 1: Baseline quarters (C D E F), treble clef, 4/4
do {
    func snapBaselineQuarters(suffix: String, endpoint: URL?) {
        let events: [NotatedEvent] = [
            .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,4))),
            .init(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1,4))),
            .init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,4))),
            .init(base: .note(pitch: Pitch(step: .F, alter: 0, octave: 4), duration: Duration(1,4)))
        ]
        let size = CGSize(width: 640, height: 200)
        let ctx = makeContext(size: size)
        let renderer = SimpleRenderer(endpoint: endpoint)
        var opts = LayoutOptions(); opts.clef = .treble; opts.keySignatureFifths = 0; opts.timeSignature = (4,4)
        let tree = renderer.layout(events: events, in: CGRect(origin: .zero, size: size), options: opts)
        renderer.draw(tree, in: ctx, options: opts)
        let role = suffix.isEmpty ? "offline" : suffix
        let name = "baseline_quarters.\(role).\(SNAP_TAG).png"
        if let img = ctx.makeImage() { writePNG(img, to: outDir.appendingPathComponent(name)) }
    }
    if let url = envEndpoint() { snapBaselineQuarters(suffix: "offline", endpoint: nil); snapBaselineQuarters(suffix: "rules", endpoint: url) }
    else { snapBaselineQuarters(suffix: "offline", endpoint: nil) }
}

// Snapshot 2: Beaming eighths in 4/4 (two groups)
do {
    func snapBeamingEighths(suffix: String, endpoint: URL?) {
        let seq: [NotatedEvent] = (0..<8).map { i in
            .init(base: .note(pitch: Pitch(step: [.C,.D,.E,.F,.G,.A,.B,.C][i%8], alter: 0, octave: 4 + (i==7 ? 1 : 0)), duration: Duration(1,8)))
        }
        let size = CGSize(width: 640, height: 200)
        let ctx = makeContext(size: size)
        let renderer = SimpleRenderer(endpoint: endpoint)
        var opts = LayoutOptions(); opts.clef = .treble; opts.keySignatureFifths = 0; opts.timeSignature = (4,4)
        let tree = renderer.layout(events: seq, in: CGRect(origin: .zero, size: size), options: opts)
        renderer.draw(tree, in: ctx, options: opts)
        let role = suffix.isEmpty ? "offline" : suffix
        let name = "beaming_eighths_4_4.\(role).\(SNAP_TAG).png"
        if let img = ctx.makeImage() { writePNG(img, to: outDir.appendingPathComponent(name)) }
    }
    if let url = envEndpoint() { snapBeamingEighths(suffix: "offline", endpoint: nil); snapBeamingEighths(suffix: "rules", endpoint: url) }
    else { snapBeamingEighths(suffix: "offline", endpoint: nil) }
}

// Snapshot 2b: Beam geometry (offline + rules if available)
do {
    func renderBeams(suffix: String, endpoint: URL?) {
        // Eighths and sixteenths with varying pitches to tilt beams
        let seq: [NotatedEvent] = [
            .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,8))),
            .init(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1,8))),
            .init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,16))),
            .init(base: .note(pitch: Pitch(step: .F, alter: 0, octave: 4), duration: Duration(1,16))),
            .init(base: .rest(duration: Duration(1,8))),
            .init(base: .note(pitch: Pitch(step: .G, alter: 0, octave: 4), duration: Duration(1,8))),
            .init(base: .note(pitch: Pitch(step: .A, alter: 0, octave: 4), duration: Duration(1,8))),
            .init(base: .note(pitch: Pitch(step: .B, alter: 0, octave: 4), duration: Duration(1,16))),
            .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 5), duration: Duration(1,16)))
        ]
        let size = CGSize(width: 640, height: 200)
        let ctx = makeContext(size: size)
        let renderer = SimpleRenderer(endpoint: endpoint)
        var opts = LayoutOptions(); opts.clef = .treble; opts.keySignatureFifths = 0; opts.timeSignature = (4,4)
        let tree = renderer.layout(events: seq, in: CGRect(origin: .zero, size: size), options: opts)
        renderer.draw(tree, in: ctx, options: opts)
        let role = suffix.isEmpty ? "offline" : suffix
        let name = "beams_geometry.\(role).\(SNAP_TAG).png"
        if let img = ctx.makeImage() { writePNG(img, to: outDir.appendingPathComponent(name)) }
    }
    if let url = envEndpoint() { renderBeams(suffix: "offline", endpoint: nil); renderBeams(suffix: "rules", endpoint: url) }
    else { renderBeams(suffix: "offline", endpoint: nil) }
}

// Snapshot 3: Dynamics (mf) with short crescendo
do {
    func snapDynamics(suffix: String, endpoint: URL?) {
        var events: [NotatedEvent] = []
        events.append(.init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,4)), hairpinStart: .crescendo, dynamic: .mf))
        events.append(.init(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1,4))))
        events.append(.init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,4)), hairpinEnd: true))
        let size = CGSize(width: 640, height: 200)
        let ctx = makeContext(size: size)
        let renderer = SimpleRenderer(endpoint: endpoint)
        var opts = LayoutOptions(); opts.clef = .treble; opts.keySignatureFifths = 0; opts.timeSignature = (4,4)
        let tree = renderer.layout(events: events, in: CGRect(origin: .zero, size: size), options: opts)
        renderer.draw(tree, in: ctx, options: opts)
        let role = suffix.isEmpty ? "offline" : suffix
        let name = "dynamics_mf_hairpin.\(role).\(SNAP_TAG).png"
        if let img = ctx.makeImage() { writePNG(img, to: outDir.appendingPathComponent(name)) }
    }
    if let url = envEndpoint() { snapDynamics(suffix: "offline", endpoint: nil); snapDynamics(suffix: "rules", endpoint: url) }
    else { snapDynamics(suffix: "offline", endpoint: nil) }
}

print("Wrote snapshots to", outDir.path)
