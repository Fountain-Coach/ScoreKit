import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ScoreKit
import ScoreKitUI

func makeContext(size: CGSize) -> CGContext {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerRow = Int(size.width) * 4
    let ctx = CGContext(data: nil,
                        width: Int(size.width),
                        height: Int(size.height),
                        bitsPerComponent: 8,
                        bytesPerRow: bytesPerRow,
                        space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}

func addFrame(_ image: CGImage, to dest: CGImageDestination, delay: Double) {
    let props: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: delay
        ]
    ]
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
}

// Prepare simple events
enum DemoKind { case base, annotated }
// German C‑Dur Tonleiter (C D E F G A H C') — all Viertel (quarters) for clarity
func makeEvents(kind: DemoKind) -> [NotatedEvent] {
    let pitches: [Pitch] = [
        .init(step: .C, alter: 0, octave: 4),
        .init(step: .D, alter: 0, octave: 4),
        .init(step: .E, alter: 0, octave: 4),
        .init(step: .F, alter: 0, octave: 4),
        .init(step: .G, alter: 0, octave: 4),
        .init(step: .A, alter: 0, octave: 4),
        .init(step: .B, alter: 0, octave: 4), // German H
        .init(step: .C, alter: 0, octave: 5)
    ]
    var evs: [NotatedEvent] = pitches.enumerated().map { (i, p) in
        .init(base: .note(pitch: p, duration: Duration(1,4)))
    }
    if kind == .annotated {
        // Significant, but clean: a single crescendo hairpin across the scale and a closing slur on the last 4 notes
        evs[0].hairpinStart = .crescendo
        evs[7].hairpinEnd = true
        evs[4].slurStart = true
        evs[7].slurEnd = true
    }
    return evs
}

let renderer = SimpleRenderer()
var opts = LayoutOptions(); opts.timeSignature = (4,4); opts.padding = CGSize(width: 60, height: 36)
let size = CGSize(width: 1024, height: 280)
let rect = CGRect(origin: .zero, size: size)

// Output path
let docsDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Docs", isDirectory: true)
try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
let outURL = docsDir.appendingPathComponent("scorekit-demo.gif")

let preHold = 12
let transition = 8
let postHold = 14
let totalFrames = preHold + transition + postHold
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.gif.identifier as CFString, totalFrames, nil) else {
    fatalError("Could not create GIF destination")
}
let gifProps: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
CGImageDestinationSetProperties(dest, gifProps as CFDictionary)

// Precompute trees to avoid per-frame relayout flicker
let baseEvents = makeEvents(kind: .base)
let baseTree = renderer.layout(events: baseEvents, in: rect, options: opts)
let annotatedEvents = makeEvents(kind: .annotated)
// Hairpin/slur do not alter spacing; still use updateLayout for consistency
let afterTree = renderer.updateLayout(previous: baseTree, events: annotatedEvents, in: rect, options: opts, changed: Set(0..<annotatedEvents.count))

for frame in 0..<totalFrames {
    let ctx = makeContext(size: size)
    // white background
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(rect)
    if frame < preHold {
        // Base state hold
        renderer.draw(baseTree, in: ctx, options: opts)
    } else if frame < preHold + transition {
        // Crossfade between base and after
        let t = Double(frame - preHold) / Double(max(1, transition - 1))
        ctx.saveGState(); ctx.setAlpha(CGFloat(1.0 - t)); renderer.draw(baseTree, in: ctx, options: opts); ctx.restoreGState()
        ctx.saveGState(); ctx.setAlpha(CGFloat(t)); renderer.draw(afterTree, in: ctx, options: opts); ctx.restoreGState()
    } else {
        // After state hold
        renderer.draw(afterTree, in: ctx, options: opts)
    }
    if let img = ctx.makeImage() { addFrame(img, to: dest, delay: 0.36) }
}

if !CGImageDestinationFinalize(dest) {
    fatalError("Failed to write GIF to \(outURL.path)")
}
print("Wrote \(outURL.path)")
