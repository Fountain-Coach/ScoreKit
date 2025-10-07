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
let lilyDir: URL = baseDir.appendingPathComponent("lily", isDirectory: true)
if ProcessInfo.processInfo.environment["SCOREKIT_SNAP_CLEAN"] == "1" {
    if FileManager.default.fileExists(atPath: outDir.path) {
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: outDir.path) {
            for name in contents { try? FileManager.default.removeItem(at: outDir.appendingPathComponent(name)) }
        }
    }
    if FileManager.default.fileExists(atPath: lilyDir.path) {
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: lilyDir.path) {
            for name in contents { try? FileManager.default.removeItem(at: lilyDir.appendingPathComponent(name)) }
        }
    }
}
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: lilyDir, withIntermediateDirectories: true)

func resolveTag() -> String {
    let env = ProcessInfo.processInfo.environment
    if let t = env["SCOREKIT_SNAP_TAG"], !t.isEmpty { return t }
    // Find git root by walking up to a .git directory
    var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let fm = FileManager.default
    var maxUp = 10
    var gitRoot: URL? = nil
    while maxUp > 0 {
        if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { gitRoot = dir; break }
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path { break }
        dir = parent; maxUp -= 1
    }
    let root = gitRoot ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let git = Process()
    git.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    git.currentDirectoryURL = root
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

func renderLilyOrFail(name: String, events: [NotatedEvent]) {
    #if ENABLE_LILYPOND
    // Prefer fixture .ly if available for gold standard; fall back to emitter
    let fixtures = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Fixtures/Lily", isDirectory: true)
    let fixtureURL = fixtures.appendingPathComponent("\(name).ly")
    let ly: String
    if FileManager.default.fileExists(atPath: fixtureURL.path), let s = try? String(contentsOf: fixtureURL) { ly = s } else {
        ly = LilyEmitter.emit(notated: events, title: name)
    }
    do {
        let artifacts = try LilySession().render(lySource: ly, execute: true, formats: [.pdf])
        if let pdf = artifacts.pdfURL {
            let dest = lilyDir.appendingPathComponent("\(name).lily.\(SNAP_TAG).pdf")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: pdf, to: dest)
        } else {
            fputs("LilyPond did not produce PDF for \(name)\n", stderr)
            exit(2)
        }
    } catch {
        fputs("LilyPond render failed for \(name): \(error)\n", stderr)
        exit(2)
    }
    #else
    fputs("LilyPond support disabled at build time. Enable ENABLE_LILYPOND.\n", stderr)
    exit(2)
    #endif
}

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
        renderLilyOrFail(name: "baseline_quarters", events: events)
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
        renderLilyOrFail(name: "beaming_eighths_4_4", events: seq)
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
        renderLilyOrFail(name: "dynamics_mf_hairpin", events: events)
    }
    if let url = envEndpoint() { snapDynamics(suffix: "offline", endpoint: nil); snapDynamics(suffix: "rules", endpoint: url) }
    else { snapDynamics(suffix: "offline", endpoint: nil) }
}

// Snapshot 4: Ode to Joy (excerpt) — C major, 4/4
do {
    func snapOdeToJoy(suffix: String, endpoint: URL?) {
        // Melody (one phrase), quarter grid with a couple of slurs
        let seq: [(Pitch, Int)] = [
            (Pitch(step: .E, alter: 0, octave: 4), 4), (Pitch(step: .E, alter: 0, octave: 4), 4),
            (Pitch(step: .F, alter: 0, octave: 4), 4), (Pitch(step: .G, alter: 0, octave: 4), 4),
            (Pitch(step: .G, alter: 0, octave: 4), 4), (Pitch(step: .F, alter: 0, octave: 4), 4),
            (Pitch(step: .E, alter: 0, octave: 4), 4), (Pitch(step: .D, alter: 0, octave: 4), 4),
            (Pitch(step: .C, alter: 0, octave: 4), 4), (Pitch(step: .C, alter: 0, octave: 4), 4),
            (Pitch(step: .D, alter: 0, octave: 4), 4), (Pitch(step: .E, alter: 0, octave: 4), 4),
            (Pitch(step: .E, alter: 0, octave: 4), 2), (Pitch(step: .D, alter: 0, octave: 4), 2)
        ]
        var events: [NotatedEvent] = []
        for (i, it) in seq.enumerated() {
            let dur = Duration(1, it.1)
            var e = NotatedEvent(base: .note(pitch: it.0, duration: dur))
            // simple slurs over {E F G} and later {C D E}
            if i == 0 { e.slurStart = true }
            if i == 3 { e.slurEnd = true }
            if i == 8 { e.slurStart = true }
            if i == 11 { e.slurEnd = true }
            events.append(e)
        }
        // add a light dynamic start
        events[0].dynamic = .mp

        let size = CGSize(width: 800, height: 220)
        let ctx = makeContext(size: size)
        let renderer = SimpleRenderer(endpoint: endpoint)
        var opts = LayoutOptions(); opts.clef = .treble; opts.keySignatureFifths = 0; opts.timeSignature = (4,4)
        let tree = renderer.layout(events: events, in: CGRect(origin: .zero, size: size), options: opts)
        renderer.draw(tree, in: ctx, options: opts)
        let role = suffix.isEmpty ? "offline" : suffix
        let name = "ode_to_joy_excerpt.\(role).\(SNAP_TAG).png"
        if let img = ctx.makeImage() { writePNG(img, to: outDir.appendingPathComponent(name)) }
        renderLilyOrFail(name: "ode_to_joy_excerpt", events: events)
    }
    if let url = envEndpoint() { snapOdeToJoy(suffix: "offline", endpoint: nil); snapOdeToJoy(suffix: "rules", endpoint: url) }
    else { snapOdeToJoy(suffix: "offline", endpoint: nil) }
}

// Snapshot 5: Etude in 6/8 — dotted-beat grouping, rest split
do {
    func snapEtudeSixEight(suffix: String, endpoint: URL?) {
        // Two bars: [e e e | e e e], then [rest e e | e e e]
        var seq: [NotatedEvent] = []
        let notes1: [Pitch] = [.C,.D,.E,.F,.G,.A].map { Pitch(step: $0, alter: 0, octave: 4) }
        for p in notes1 { seq.append(.init(base: .note(pitch: p, duration: Duration(1,8)))) }
        seq.append(.init(base: .rest(duration: Duration(1,8))))
        seq.append(.init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,8))))
        seq.append(.init(base: .note(pitch: Pitch(step: .F, alter: 0, octave: 4), duration: Duration(1,8))))
        seq.append(.init(base: .note(pitch: Pitch(step: .G, alter: 0, octave: 4), duration: Duration(1,8))))
        seq.append(.init(base: .note(pitch: Pitch(step: .A, alter: 0, octave: 4), duration: Duration(1,8))))
        seq.append(.init(base: .note(pitch: Pitch(step: .B, alter: 0, octave: 4), duration: Duration(1,8))))
        let size = CGSize(width: 800, height: 220)
        let ctx = makeContext(size: size)
        let renderer = SimpleRenderer(endpoint: endpoint)
        var opts = LayoutOptions(); opts.clef = .treble; opts.keySignatureFifths = 0; opts.timeSignature = (6,8)
        let tree = renderer.layout(events: seq, in: CGRect(origin: .zero, size: size), options: opts)
        renderer.draw(tree, in: ctx, options: opts)
        let role = suffix.isEmpty ? "offline" : suffix
        let name = "etude_6_8.\(role).\(SNAP_TAG).png"
        if let img = ctx.makeImage() { writePNG(img, to: outDir.appendingPathComponent(name)) }
        renderLilyOrFail(name: "etude_6_8", events: seq)
    }
    if let url = envEndpoint() { snapEtudeSixEight(suffix: "offline", endpoint: nil); snapEtudeSixEight(suffix: "rules", endpoint: url) }
    else { snapEtudeSixEight(suffix: "offline", endpoint: nil) }
}

// Glyph Sampler — clefs/keys/time changes visible mid‑score
do {
    func snapSamplerMarks(suffix: String, endpoint: URL?) {
        var events: [NotatedEvent] = []
        // Start in treble, C major, 4/4
        events.append(.init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,4))))
        // Key change to 2 sharps
        var e1 = NotatedEvent(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1,4)))
        e1.keyChangeFifths = 2; events.append(e1)
        // Time change to 3/4
        var e2 = NotatedEvent(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,4)))
        e2.timeChange = TimeSig(3, 4); events.append(e2)
        // Clef change to bass
        var e3 = NotatedEvent(base: .note(pitch: Pitch(step: .F, alter: 0, octave: 3), duration: Duration(1,4)))
        e3.clefChange = .bass; events.append(e3)
        let size = CGSize(width: 800, height: 220)
        let ctx = makeContext(size: size)
        let renderer = SimpleRenderer(endpoint: endpoint)
        var opts = LayoutOptions(); opts.clef = .treble; opts.keySignatureFifths = 0; opts.timeSignature = (4,4)
        let tree = renderer.layout(events: events, in: CGRect(origin: .zero, size: size), options: opts)
        renderer.draw(tree, in: ctx, options: opts)
        let role = suffix.isEmpty ? "offline" : suffix
        let name = "sampler_marks.\(role).\(SNAP_TAG).png"
        if let img = ctx.makeImage() { writePNG(img, to: outDir.appendingPathComponent(name)) }
        renderLilyOrFail(name: "sampler_marks", events: events)
    }
    if let url = envEndpoint() { snapSamplerMarks(suffix: "offline", endpoint: nil); snapSamplerMarks(suffix: "rules", endpoint: url) }
    else { snapSamplerMarks(suffix: "offline", endpoint: nil) }
}

// Glyph Sampler — durations and rests with ledger lines
do {
    func snapSamplerDurations(suffix: String, endpoint: URL?) {
        var events: [NotatedEvent] = []
        events.append(.init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 5), duration: Duration(1,1))))
        events.append(.init(base: .note(pitch: Pitch(step: .A, alter: 0, octave: 4), duration: Duration(1,2))))
        events.append(.init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,4))))
        events.append(.init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,8))))
        events.append(.init(base: .note(pitch: Pitch(step: .B, alter: 0, octave: 3), duration: Duration(1,16))))
        events.append(.init(base: .rest(duration: Duration(1,4))))
        let size = CGSize(width: 800, height: 220)
        let ctx = makeContext(size: size)
        let renderer = SimpleRenderer(endpoint: endpoint)
        var opts = LayoutOptions(); opts.clef = .treble; opts.keySignatureFifths = 0; opts.timeSignature = (4,4)
        let tree = renderer.layout(events: events, in: CGRect(origin: .zero, size: size), options: opts)
        renderer.draw(tree, in: ctx, options: opts)
        let role = suffix.isEmpty ? "offline" : suffix
        let name = "sampler_durations.\(role).\(SNAP_TAG).png"
        if let img = ctx.makeImage() { writePNG(img, to: outDir.appendingPathComponent(name)) }
        renderLilyOrFail(name: "sampler_durations", events: events)
    }
    if let url = envEndpoint() { snapSamplerDurations(suffix: "offline", endpoint: nil); snapSamplerDurations(suffix: "rules", endpoint: url) }
    else { snapSamplerDurations(suffix: "offline", endpoint: nil) }
}

// Glyph Sampler — accidentals across an octave
do {
    func snapSamplerAccidentals(suffix: String, endpoint: URL?) {
        let pitches: [Pitch] = [
            Pitch(step: .C, alter: 1, octave: 4),  // C#
            Pitch(step: .D, alter: -1, octave: 4), // Db
            Pitch(step: .E, alter: -1, octave: 4), // Eb
            Pitch(step: .F, alter: 1, octave: 4),  // F#
            Pitch(step: .G, alter: -1, octave: 4), // Gb
            Pitch(step: .A, alter: 1, octave: 4),  // A#
            Pitch(step: .B, alter: -1, octave: 4)  // Bb
        ]
        let events: [NotatedEvent] = pitches.map { p in .init(base: .note(pitch: p, duration: Duration(1,4))) }
        let size = CGSize(width: 800, height: 220)
        let ctx = makeContext(size: size)
        let renderer = SimpleRenderer(endpoint: endpoint)
        var opts = LayoutOptions(); opts.clef = .treble; opts.keySignatureFifths = 0; opts.timeSignature = (4,4)
        let tree = renderer.layout(events: events, in: CGRect(origin: .zero, size: size), options: opts)
        renderer.draw(tree, in: ctx, options: opts)
        let role = suffix.isEmpty ? "offline" : suffix
        let name = "sampler_accidentals.\(role).\(SNAP_TAG).png"
        if let img = ctx.makeImage() { writePNG(img, to: outDir.appendingPathComponent(name)) }
        renderLilyOrFail(name: "sampler_accidentals", events: events)
    }
    if let url = envEndpoint() { snapSamplerAccidentals(suffix: "offline", endpoint: nil); snapSamplerAccidentals(suffix: "rules", endpoint: url) }
    else { snapSamplerAccidentals(suffix: "offline", endpoint: nil) }
}

print("Wrote snapshots to", outDir.path)
