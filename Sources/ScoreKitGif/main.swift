import Foundation
import CoreGraphics
import ImageIO
import CoreText
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

func drawText(_ ctx: CGContext, rect: CGRect, text: String, at p: CGPoint, fontSize: CGFloat, color: CGColor, align: CTTextAlignment = .center) {
    let font = CTFontCreateWithName("HelveticaNeue" as CFString, fontSize, nil)
    let paragraph = withUnsafeBytes(of: {
        var alignment = align
        return alignment
    }()) { raw -> CTParagraphStyle in
        let settings = [CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: raw.baseAddress!)]
        return CTParagraphStyleCreate(settings, settings.count)
    }
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        kCTParagraphStyleAttributeName as NSAttributedString.Key: paragraph
    ]
    let attr = NSAttributedString(string: text, attributes: attrs)
    let line = CTLineCreateWithAttributedString(attr)
    // Flip just for text drawing
    ctx.saveGState()
    ctx.translateBy(x: 0, y: rect.height)
    ctx.scaleBy(x: 1, y: -1)
    let yp = rect.height - p.y
    // Adjust for alignment: we only handle center/left minimally using typographic bounds
    var penX = p.x
    if align == .center {
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        penX -= width / 2
    }
    ctx.textPosition = CGPoint(x: penX, y: yp)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
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
    // Flip to y-down to match renderer's coordinate assumptions
    ctx.translateBy(x: 0, y: size.height)
    ctx.scaleBy(x: 1, y: -1)
    // white background
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(rect)
    if frame < preHold {
        // Base state hold
        renderer.draw(baseTree, in: ctx, options: opts)
        // Subtle measure numbers
        if let firstBar = baseTree.barX.first {
            drawText(ctx, rect: rect, text: "1", at: CGPoint(x: max(8, opts.padding.width - 20), y: opts.padding.height - 8), fontSize: 12, color: CGColor(gray: 0.35, alpha: 0.8), align: .left)
            drawText(ctx, rect: rect, text: "2", at: CGPoint(x: firstBar + 8, y: opts.padding.height - 8), fontSize: 12, color: CGColor(gray: 0.35, alpha: 0.8), align: .left)
        }
    } else if frame < preHold + transition {
        // Crossfade between base and after
        let t = Double(frame - preHold) / Double(max(1, transition - 1))
        ctx.saveGState(); ctx.setAlpha(CGFloat(1.0 - t)); renderer.draw(baseTree, in: ctx, options: opts); ctx.restoreGState()
        ctx.saveGState(); ctx.setAlpha(CGFloat(t)); renderer.draw(afterTree, in: ctx, options: opts); ctx.restoreGState()
        // Measure numbers (constant)
        if let firstBar = baseTree.barX.first {
            drawText(ctx, rect: rect, text: "1", at: CGPoint(x: max(8, opts.padding.width - 20), y: opts.padding.height - 8), fontSize: 12, color: CGColor(gray: 0.35, alpha: 0.8), align: .left)
            drawText(ctx, rect: rect, text: "2", at: CGPoint(x: firstBar + 8, y: opts.padding.height - 8), fontSize: 12, color: CGColor(gray: 0.35, alpha: 0.8), align: .left)
        }
        // Fade-in dynamic labels near hairpin baseline
        if let firstEl = afterTree.elements.first, let lastEl = afterTree.elements.last {
            let baseline = max(firstEl.frame.maxY, lastEl.frame.maxY) + 36
            let alpha = CGFloat(t)
            drawText(ctx, rect: rect, text: "p", at: CGPoint(x: firstEl.frame.midX, y: baseline), fontSize: 14, color: CGColor(gray: 0.1, alpha: alpha), align: .center)
            drawText(ctx, rect: rect, text: "ff", at: CGPoint(x: lastEl.frame.midX, y: baseline), fontSize: 14, color: CGColor(gray: 0.1, alpha: alpha), align: .center)
        }
    } else {
        // After state hold
        renderer.draw(afterTree, in: ctx, options: opts)
        // Measure numbers (constant)
        if let firstBar = afterTree.barX.first {
            drawText(ctx, rect: rect, text: "1", at: CGPoint(x: max(8, opts.padding.width - 20), y: opts.padding.height - 8), fontSize: 12, color: CGColor(gray: 0.35, alpha: 0.8), align: .left)
            drawText(ctx, rect: rect, text: "2", at: CGPoint(x: firstBar + 8, y: opts.padding.height - 8), fontSize: 12, color: CGColor(gray: 0.35, alpha: 0.8), align: .left)
        }
        // p → ff labels near hairpin
        if let firstEl = afterTree.elements.first, let lastEl = afterTree.elements.last {
            let baseline = max(firstEl.frame.maxY, lastEl.frame.maxY) + 36
            drawText(ctx, rect: rect, text: "p", at: CGPoint(x: firstEl.frame.midX, y: baseline), fontSize: 14, color: CGColor(gray: 0.1, alpha: 1.0), align: .center)
            drawText(ctx, rect: rect, text: "ff", at: CGPoint(x: lastEl.frame.midX, y: baseline), fontSize: 14, color: CGColor(gray: 0.1, alpha: 1.0), align: .center)
        }
    }
    if let img = ctx.makeImage() { addFrame(img, to: dest, delay: 0.36) }
}

if !CGImageDestinationFinalize(dest) {
    fatalError("Failed to write GIF to \(outURL.path)")
}
print("Wrote \(outURL.path)")
