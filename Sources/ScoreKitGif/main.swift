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
enum DemoKind { case base, widened }
func makeEvents(kind: DemoKind) -> [NotatedEvent] {
    var evs: [NotatedEvent] = [
        .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,8)), hairpinStart: .crescendo),
        .init(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1,8)), slurStart: true, articulations: [.staccato]),
        .init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,8)), slurEnd: true, hairpinEnd: true, dynamic: .mf),
        .init(base: .rest(duration: Duration(1,4))),
        .init(base: .note(pitch: Pitch(step: .F, alter: 0, octave: 4), duration: Duration(1,8))),
        .init(base: .note(pitch: Pitch(step: .G, alter: 0, octave: 4), duration: kind == .base ? Duration(1,8) : Duration(1,2))),
        .init(base: .note(pitch: Pitch(step: .A, alter: 0, octave: 4), duration: Duration(1,8))),
        .init(base: .note(pitch: Pitch(step: .B, alter: 0, octave: 4), duration: Duration(1,8)))
    ]
    return evs
}

let renderer = SimpleRenderer()
var opts = LayoutOptions(); opts.timeSignature = (4,4); opts.padding = CGSize(width: 40, height: 28)
let size = CGSize(width: 1024, height: 260)
let rect = CGRect(origin: .zero, size: size)

// Output path
let docsDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Docs", isDirectory: true)
try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
let outURL = docsDir.appendingPathComponent("scorekit-demo.gif")

let preHold = 8
let transition = 6
let postHold = 10
let totalFrames = preHold + transition + postHold
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.gif.identifier as CFString, totalFrames, nil) else {
    fatalError("Could not create GIF destination")
}
let gifProps: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
CGImageDestinationSetProperties(dest, gifProps as CFDictionary)

// Precompute trees to avoid per-frame relayout flicker
let baseEvents = makeEvents(kind: .base)
let baseTree = renderer.layout(events: baseEvents, in: rect, options: opts)
var widenedEvents = baseEvents
let changedIndex = 5
widenedEvents[changedIndex] = .init(base: .note(pitch: Pitch(step: .G, alter: 0, octave: 4), duration: Duration(1,2)))
let afterTree = renderer.updateLayout(previous: baseTree, events: widenedEvents, in: rect, options: opts, changed: [changedIndex])

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
        // After state hold, with very subtle pulse around the changed note
        renderer.draw(afterTree, in: ctx, options: opts)
        if changedIndex < afterTree.elements.count {
            let f = afterTree.elements[changedIndex].frame.insetBy(dx: -10, dy: -10)
            let tt = Double(frame - (preHold + transition)) / Double(max(1, postHold))
            let alpha = 0.08 + 0.06 * 0.5 * (1.0 + sin(2 * Double.pi * tt))
            ctx.setFillColor(CGColor(red: 0.2, green: 0.55, blue: 1.0, alpha: alpha))
            ctx.fill(f)
            ctx.setStrokeColor(CGColor(red: 0.2, green: 0.55, blue: 1.0, alpha: min(0.6, alpha + 0.15)))
            ctx.setLineWidth(2)
            ctx.stroke(f)
        }
    }
    if let img = ctx.makeImage() { addFrame(img, to: dest, delay: 0.28) }
}

if !CGImageDestinationFinalize(dest) {
    fatalError("Failed to write GIF to \(outURL.path)")
}
print("Wrote \(outURL.path)")
