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
var opts = LayoutOptions(); opts.timeSignature = (4,4)
let size = CGSize(width: 640, height: 200)
let rect = CGRect(origin: .zero, size: size)

// Output path
let docsDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Docs", isDirectory: true)
try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
let outURL = docsDir.appendingPathComponent("scorekit-demo.gif")

guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.gif.identifier as CFString, 30, nil) else {
    fatalError("Could not create GIF destination")
}
let gifProps: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
CGImageDestinationSetProperties(dest, gifProps as CFDictionary)

// Build frames: first 10 frames baseline, then switch to widened duration at index 5 and use updateLayout
var prevTree: LayoutTree? = nil
var baseEvents = makeEvents(kind: .base)

for frame in 0..<30 {
    let ctx = makeContext(size: size)
    // white background
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(rect)
    let tree: LayoutTree
    if frame < 10 {
        tree = renderer.layout(events: baseEvents, in: rect, options: opts)
    } else {
        let widened = makeEvents(kind: .widened)
        let changed: Set<Int> = [5]
        tree = renderer.updateLayout(previous: prevTree, events: widened, in: rect, options: opts, changed: changed)
        baseEvents = widened
    }
    ctx.saveGState()
    renderer.draw(tree, in: ctx, options: opts)
    ctx.restoreGState()
    // selection highlight moves across elements
    let sel = frame % max(1, tree.elements.count)
    if sel < tree.elements.count {
        let f = tree.elements[sel].frame.insetBy(dx: -6, dy: -6)
        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.18))
        ctx.fill(f)
        ctx.setStrokeColor(CGColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.8))
        ctx.setLineWidth(2)
        ctx.stroke(f)
    }
    // Make image and append
    if let img = ctx.makeImage() {
        addFrame(img, to: dest, delay: 0.08)
    }
    prevTree = tree
}

if !CGImageDestinationFinalize(dest) {
    fatalError("Failed to write GIF to \(outURL.path)")
}
print("Wrote \(outURL.path)")

