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
    return ctx
}

func writePNG(_ img: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Snapshots", isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// Snapshot 1: SimpleRenderer with clef/key/time, accidentals, mixed durations
do {
    func renderSimple(suffix: String, endpoint: URL?) {
        var events: [NotatedEvent] = []
        events.append(.init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,1))))
        events.append(.init(base: .note(pitch: Pitch(step: .F, alter: 1, octave: 4), duration: Duration(1,2))))
        events.append(.init(base: .note(pitch: Pitch(step: .B, alter: -1, octave: 4), duration: Duration(1,4)), articulations: [.staccato, .accent]))
        events.append(.init(base: .rest(duration: Duration(1,4))))
        events.append(.init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 5), duration: Duration(1,8)), articulations: [.tenuto]))
        let size = CGSize(width: 640, height: 200)
        let ctx = makeContext(size: size)
        let renderer = SimpleRenderer(endpoint: endpoint)
        var opts = LayoutOptions(); opts.clef = .treble; opts.keySignatureFifths = 1; opts.timeSignature = (6,8)
        let tree = renderer.layout(events: events, in: CGRect(origin: .zero, size: size), options: opts)
        renderer.draw(tree, in: ctx, options: opts)
        let name = suffix.isEmpty ? "simple_treble.png" : "simple_treble.\(suffix).png"
        if let img = ctx.makeImage() { writePNG(img, to: outDir.appendingPathComponent(name)) }
    }
    if let url = envEndpoint() {
        renderSimple(suffix: "offline", endpoint: nil)
        renderSimple(suffix: "rules", endpoint: url)
    } else {
        renderSimple(suffix: "", endpoint: nil)
    }
}

// Snapshot 2: MultiRenderer with two voices unisons/seconds
do {
    let v0: [NotatedEvent] = [
        .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,4))),
        .init(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1,4))),
        .init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,4))),
        .init(base: .note(pitch: Pitch(step: .F, alter: 0, octave: 4), duration: Duration(1,4)))
    ]
    let v1: [NotatedEvent] = [
        .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,4))), // unison
        .init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,4))), // second
        .init(base: .note(pitch: Pitch(step: .G, alter: 0, octave: 4), duration: Duration(1,4))),
        .init(base: .note(pitch: Pitch(step: .A, alter: 0, octave: 4), duration: Duration(1,4)))
    ]
    let size = CGSize(width: 640, height: 200)
    let ctx = makeContext(size: size)
    let renderer = MultiRenderer()
    let t = renderer.layout(voices: [v0, v1], in: CGRect(origin: .zero, size: size), options: LayoutOptions())
    renderer.draw(t, in: ctx, options: LayoutOptions())
    if let img = ctx.makeImage() { writePNG(img, to: outDir.appendingPathComponent("multi_two_voices.png")) }
}

// Snapshot 3: Dynamics kerning (offline + rules if available)
do {
    func renderDynamics(suffix: String, endpoint: URL?) {
        var events: [NotatedEvent] = []
        events.append(.init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,4)), dynamic: .mf))
        events.append(.init(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1,8)), hairpinStart: .crescendo))
        events.append(.init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,8))))
        events.append(.init(base: .note(pitch: Pitch(step: .F, alter: 0, octave: 4), duration: Duration(1,4)), hairpinEnd: true, dynamic: .ff))
        let size = CGSize(width: 480, height: 200)
        let ctx = makeContext(size: size)
        let renderer = SimpleRenderer(endpoint: endpoint)
        var opts = LayoutOptions(); opts.clef = .treble; opts.keySignatureFifths = 0; opts.timeSignature = (4,4)
        let tree = renderer.layout(events: events, in: CGRect(origin: .zero, size: size), options: opts)
        renderer.draw(tree, in: ctx, options: opts)
        let name = suffix.isEmpty ? "dynamics_kerning.png" : "dynamics_kerning.\(suffix).png"
        if let img = ctx.makeImage() { writePNG(img, to: outDir.appendingPathComponent(name)) }
    }
    if let url = envEndpoint() {
        renderDynamics(suffix: "offline", endpoint: nil)
        renderDynamics(suffix: "rules", endpoint: url)
    } else {
        renderDynamics(suffix: "", endpoint: nil)
    }
}

print("Wrote snapshots to", outDir.path)
