import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import UniformTypeIdentifiers
import ScoreKit
import ScoreKitUI

// Reuse the same Tonleiter and drawing helpers as GIF generator (simplified inline)

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
    ctx.saveGState()
    ctx.translateBy(x: 0, y: rect.height)
    ctx.scaleBy(x: 1, y: -1)
    let yp = rect.height - p.y
    var penX = p.x
    if align == .center {
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        penX -= width / 2
    }
    ctx.textPosition = CGPoint(x: penX, y: yp)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

enum DemoKind { case base, annotated }
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
    var evs: [NotatedEvent] = pitches.map { p in .init(base: .note(pitch: p, duration: Duration(1,4))) }
    if kind == .annotated {
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

let baseEvents = makeEvents(kind: .base)
let baseTree = renderer.layout(events: baseEvents, in: rect, options: opts)
let annotatedEvents = makeEvents(kind: .annotated)
let afterTree = renderer.updateLayout(previous: baseTree, events: annotatedEvents, in: rect, options: opts, changed: Set(0..<annotatedEvents.count))

let preHold = 12
let transition = 10
let postHold = 16
let totalFrames = preHold + transition + postHold
let fps: Int32 = 10

// Prepare AVAssetWriter
let docsDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Docs", isDirectory: true)
try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
let outURL = docsDir.appendingPathComponent("scorekit-demo.mp4")
try? FileManager.default.removeItem(at: outURL)
let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: size.width,
    AVVideoHeightKey: size.height
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let attrs: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
    kCVPixelBufferWidthKey as String: size.width,
    kCVPixelBufferHeightKey as String: size.height,
]
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
precondition(writer.canAdd(input)); writer.add(input)
writer.startWriting(); writer.startSession(atSourceTime: .zero)

let frameDuration = CMTime(value: 1, timescale: fps)
var frameCount: Int64 = 0

func frameImage(index: Int) -> CGImage? {
    let ctx = makeContext(size: size)
    // Flip to y-down for renderer consistency
    ctx.translateBy(x: 0, y: size.height)
    ctx.scaleBy(x: 1, y: -1)
    // background
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(rect)
    if index < preHold {
        renderer.draw(baseTree, in: ctx, options: opts)
        if let firstBar = baseTree.barX.first {
            drawText(ctx, rect: rect, text: "1", at: CGPoint(x: max(8, opts.padding.width - 20), y: opts.padding.height - 8), fontSize: 12, color: CGColor(gray: 0.35, alpha: 0.8), align: .left)
            drawText(ctx, rect: rect, text: "2", at: CGPoint(x: firstBar + 8, y: opts.padding.height - 8), fontSize: 12, color: CGColor(gray: 0.35, alpha: 0.8), align: .left)
        }
        drawText(ctx, rect: rect, text: "C‑Dur Tonleiter", at: CGPoint(x: rect.midX, y: opts.padding.height - 16), fontSize: 16, color: CGColor(gray: 0.1, alpha: 1.0), align: .center)
    } else if index < preHold + transition {
        let t = Double(index - preHold) / Double(max(1, transition - 1))
        ctx.saveGState(); ctx.setAlpha(CGFloat(1.0 - t)); renderer.draw(baseTree, in: ctx, options: opts); ctx.restoreGState()
        ctx.saveGState(); ctx.setAlpha(CGFloat(t)); renderer.draw(afterTree, in: ctx, options: opts); ctx.restoreGState()
        if let firstBar = baseTree.barX.first {
            drawText(ctx, rect: rect, text: "1", at: CGPoint(x: max(8, opts.padding.width - 20), y: opts.padding.height - 8), fontSize: 12, color: CGColor(gray: 0.35, alpha: 0.8), align: .left)
            drawText(ctx, rect: rect, text: "2", at: CGPoint(x: firstBar + 8, y: opts.padding.height - 8), fontSize: 12, color: CGColor(gray: 0.35, alpha: 0.8), align: .left)
        }
        if let firstEl = afterTree.elements.first, let lastEl = afterTree.elements.last {
            let baseline = max(firstEl.frame.maxY, lastEl.frame.maxY) + 36
            let alpha = CGFloat(t)
            drawText(ctx, rect: rect, text: "p", at: CGPoint(x: firstEl.frame.midX, y: baseline), fontSize: 14, color: CGColor(gray: 0.1, alpha: alpha), align: .center)
            drawText(ctx, rect: rect, text: "ff", at: CGPoint(x: lastEl.frame.midX, y: baseline), fontSize: 14, color: CGColor(gray: 0.1, alpha: alpha), align: .center)
        }
        drawText(ctx, rect: rect, text: "C‑Dur Tonleiter", at: CGPoint(x: rect.midX, y: opts.padding.height - 16), fontSize: 16, color: CGColor(gray: 0.1, alpha: 1.0), align: .center)
    } else {
        renderer.draw(afterTree, in: ctx, options: opts)
        if let firstBar = afterTree.barX.first {
            drawText(ctx, rect: rect, text: "1", at: CGPoint(x: max(8, opts.padding.width - 20), y: opts.padding.height - 8), fontSize: 12, color: CGColor(gray: 0.35, alpha: 0.8), align: .left)
            drawText(ctx, rect: rect, text: "2", at: CGPoint(x: firstBar + 8, y: opts.padding.height - 8), fontSize: 12, color: CGColor(gray: 0.35, alpha: 0.8), align: .left)
        }
        if let firstEl = afterTree.elements.first, let lastEl = afterTree.elements.last {
            let baseline = max(firstEl.frame.maxY, lastEl.frame.maxY) + 36
            drawText(ctx, rect: rect, text: "p", at: CGPoint(x: firstEl.frame.midX, y: baseline), fontSize: 14, color: CGColor(gray: 0.1, alpha: 1.0), align: .center)
            drawText(ctx, rect: rect, text: "ff", at: CGPoint(x: lastEl.frame.midX, y: baseline), fontSize: 14, color: CGColor(gray: 0.1, alpha: 1.0), align: .center)
        }
        drawText(ctx, rect: rect, text: "C‑Dur Tonleiter", at: CGPoint(x: rect.midX, y: opts.padding.height - 16), fontSize: 16, color: CGColor(gray: 0.1, alpha: 1.0), align: .center)
    }
    return ctx.makeImage()
}

let queue = DispatchQueue(label: "vid-writer")
input.requestMediaDataWhenReady(on: queue) {
    while input.isReadyForMoreMediaData {
        if frameCount >= Int64(totalFrames) {
            input.markAsFinished()
            writer.finishWriting {
                print("Wrote \(outURL.path)")
                exit(0)
            }
            break
        }
        guard let pbPool = adaptor.pixelBufferPool else { continue }
        var pbOut: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pbPool, &pbOut)
        guard let pb = pbOut else { continue }
        CVPixelBufferLockBaseAddress(pb, [])
        if let base = CVPixelBufferGetBaseAddress(pb) {
            let bpr = CVPixelBufferGetBytesPerRow(pb)
            let cs = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(data: base, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: bpr, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
            // Draw pre-rendered CGImage for the frame into pixel buffer
            if let img = frameImage(index: Int(frameCount)) {
                ctx.draw(img, in: CGRect(origin: .zero, size: size))
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        let time = CMTimeMultiply(frameDuration, multiplier: Int32(frameCount))
        adaptor.append(pb, withPresentationTime: time)
        frameCount += 1
    }
}

dispatchMain()

