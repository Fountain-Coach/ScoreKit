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

func rasterizePDFFirstPage(_ pdfURL: URL, to pngURL: URL, scale: CGFloat) {
    guard let doc = CGPDFDocument(pdfURL as CFURL), let page = doc.page(at: 1) else { return }
    let box = page.getBoxRect(.mediaBox)
    let width = Int(box.width * scale)
    let height = Int(box.height * scale)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    // White background
    ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
    ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    // Draw PDF in y-up without flipping; just scale to target pixels
    ctx.saveGState()
    ctx.scaleBy(x: scale, y: scale)
    ctx.drawPDFPage(page)
    ctx.restoreGState()
    if let img = ctx.makeImage() { writePNG(img, to: pngURL) }
}

func makeLilyPNG(name: String) {
    let pdf = lilyDir.appendingPathComponent("\(name).lily.\(SNAP_TAG).pdf")
    guard FileManager.default.fileExists(atPath: pdf.path) else { return }
    let scaleEnv = ProcessInfo.processInfo.environment["SCOREKIT_LILY_PNG_SCALE"].flatMap { Double($0) }
    let scale = CGFloat(scaleEnv ?? 2.0)
    let png = lilyDir.appendingPathComponent("\(name).lily.\(SNAP_TAG).png")
    rasterizePDFFirstPage(pdf, to: png, scale: scale)
}

// Compare two PNG files and emit a diff heatmap and RMSE.
func comparePNGs(gold: URL, test: URL, outBase: String) {
    guard let goldSrc = CGImageSourceCreateWithURL(gold as CFURL, nil),
          let testSrc = CGImageSourceCreateWithURL(test as CFURL, nil),
          let gImg = CGImageSourceCreateImageAtIndex(goldSrc, 0, nil),
          let tImg = CGImageSourceCreateImageAtIndex(testSrc, 0, nil) else { return }
    let w = min(gImg.width, tImg.width)
    let h = min(gImg.height, tImg.height)
    let cs = CGColorSpaceCreateDeviceGray()
    func gray(_ img: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return ctx.makeImage()
    }
    guard let gGray = gray(gImg), let tGray = gray(tImg) else { return }
    guard let gData = gGray.dataProvider?.data, let tData = tGray.dataProvider?.data else { return }
    let gp = CFDataGetBytePtr(gData)!
    let tp = CFDataGetBytePtr(tData)!
    var sse: Double = 0
    guard let outCtx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
    for y in 0..<h {
        for x in 0..<w {
            let i = y*w + x
            let d = Int(gp[i]) - Int(tp[i])
            sse += Double(d*d)
            outCtx.data?.storeBytes(of: UInt8(min(255, abs(d))), toByteOffset: i, as: UInt8.self)
        }
    }
    if let diff = outCtx.makeImage() {
        let out = diffDir.appendingPathComponent("\(outBase).diff.\(SNAP_TAG).png")
        writePNG(diff, to: out)
    }
    let rmse = sqrt(sse / Double(w*h))
    fputs("diff \(outBase): rmse=\(String(format: "%.2f", rmse))\n", stderr)
}

// Read PNG dimensions
func pngSize(_ url: URL) -> CGSize? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return CGSize(width: img.width, height: img.height)
}

// Detect top staff line Y and inter-line spacing from Lily PNG by row projection
func detectStaffTopAndSpacing(_ png: URL) -> (CGFloat, CGFloat)? {
    guard let src = CGImageSourceCreateWithURL(png as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let w = img.width, h = img.height
    let cs = CGColorSpaceCreateDeviceGray()
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
    guard let g = ctx.makeImage(), let dp = g.dataProvider?.data else { return nil }
    let p = CFDataGetBytePtr(dp)!
    var rowSum = Array(repeating: 0, count: h)
    let stride = max(1, w/256)
    for y in 0..<h {
        var s = 0
        var x = 0
        while x < w { s += 255 - Int(p[y*w + x]); x += stride }
        rowSum[y] = s
    }
    // Local maxima
    var peaks: [Int] = []
    for y in 1..<(h-1) { if rowSum[y] > rowSum[y-1] && rowSum[y] > rowSum[y+1] { peaks.append(y) } }
    peaks.sort { rowSum[$0] > rowSum[$1] }
    // Take first 7 candidates then choose 5 consecutive with closest spacing
    let cand = Array(peaks.prefix(12)).sorted()
    guard cand.count >= 5 else { return nil }
    var best: [Int] = Array(cand.prefix(5))
    var bestVar: Double = .infinity
    for i in 0..<(cand.count - 4) {
        let slice = Array(cand[i..<(i+5)])
        var diffs: [Double] = []
        for j in 1..<slice.count { diffs.append(Double(slice[j] - slice[j-1])) }
        let mean = diffs.reduce(0,+)/Double(diffs.count)
        let v = diffs.map { ($0-mean)*($0-mean) }.reduce(0,+)/Double(diffs.count)
        if v < bestVar { bestVar = v; best = slice }
    }
    let spacing = CGFloat((best[4]-best[0]))/4.0
    return (CGFloat(best[0]), spacing)
}

let baseDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Snapshots", isDirectory: true)
let subdir = ProcessInfo.processInfo.environment["SCOREKIT_SNAP_SUBDIR"].flatMap { s in s.isEmpty ? nil : s }
let outDir: URL = {
    if let sub = subdir { return baseDir.appendingPathComponent(sub, isDirectory: true) }
    return baseDir
}()
let lilyDir: URL = baseDir.appendingPathComponent("lily", isDirectory: true)
let diffDir: URL = baseDir.appendingPathComponent("diff", isDirectory: true)
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
    if FileManager.default.fileExists(atPath: diffDir.path) {
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: diffDir.path) {
            for name in contents { try? FileManager.default.removeItem(at: diffDir.appendingPathComponent(name)) }
        }
    }
}
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: lilyDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: diffDir, withIntermediateDirectories: true)

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

func eventsFromFixtureOr(_ name: String, fallback: () -> [NotatedEvent]) -> [NotatedEvent] {
    let fixtures = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Fixtures/Lily", isDirectory: true)
    let url = fixtures.appendingPathComponent("\(name).ly")
    #if ENABLE_LILYPOND
    if let src = try? String(contentsOf: url) {
        return LilyParser.parse(source: src)
    }
    #endif
    return fallback()
}
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
        // First generate Lily gold and PNG to calibrate coordinates
        let goldName = "baseline_quarters"
        let events: [NotatedEvent] = eventsFromFixtureOr(goldName) {
            [
                .init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,4))),
                .init(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1,4))),
                .init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,4))),
                .init(base: .note(pitch: Pitch(step: .F, alter: 0, octave: 4), duration: Duration(1,4)))
            ]
        }
        renderLilyOrFail(name: goldName, events: events)
        makeLilyPNG(name: goldName)
        // Calibrate canvas to Lily PNG size and staff metrics
        let goldPNG = lilyDir.appendingPathComponent("\(goldName).lily.\(SNAP_TAG).png")
        let size = pngSize(goldPNG) ?? CGSize(width: 640, height: 200)
        let ctx = makeContext(size: size)
        let renderer = SimpleRenderer(endpoint: endpoint)
        var opts = LayoutOptions(); opts.clef = .treble; opts.keySignatureFifths = 0; opts.timeSignature = (4,4)
        if let (_, spacing) = detectStaffTopAndSpacing(goldPNG) {
            // Use Lily staff spacing but keep our own top padding so staff sits at the top of our canvas.
            opts.staffSpacing = spacing
        }
        let tree = renderer.layout(events: events, in: CGRect(origin: .zero, size: size), options: opts)
        renderer.draw(tree, in: ctx, options: opts)
        let role = suffix.isEmpty ? "offline" : suffix
        let name = "baseline_quarters.\(role).\(SNAP_TAG).png"
        if let img = ctx.makeImage() { writePNG(img, to: outDir.appendingPathComponent(name)) }
        let gold = goldPNG
        let test = outDir.appendingPathComponent(name)
        comparePNGs(gold: gold, test: test, outBase: "baseline_quarters")
    }
    if let url = envEndpoint() { snapBaselineQuarters(suffix: "offline", endpoint: nil); snapBaselineQuarters(suffix: "rules", endpoint: url) }
    else { snapBaselineQuarters(suffix: "offline", endpoint: nil) }
}

// Snapshot 2: Beaming eighths in 4/4 (two groups)
do {
    func snapBeamingEighths(suffix: String, endpoint: URL?) {
        let seq: [NotatedEvent] = eventsFromFixtureOr("beaming_eighths_4_4") {
            (0..<8).map { i in
                .init(base: .note(pitch: Pitch(step: [.C,.D,.E,.F,.G,.A,.B,.C][i%8], alter: 0, octave: 4 + (i==7 ? 1 : 0)), duration: Duration(1,8)))
            }
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
        makeLilyPNG(name: "beaming_eighths_4_4")
        comparePNGs(gold: lilyDir.appendingPathComponent("beaming_eighths_4_4.lily.\(SNAP_TAG).png"), test: outDir.appendingPathComponent(name), outBase: "beaming_eighths_4_4")
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
        var events: [NotatedEvent] = eventsFromFixtureOr("dynamics_mf_hairpin") {
            var tmp: [NotatedEvent] = []
            tmp.append(.init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,4)), hairpinStart: .crescendo, dynamic: .mf))
            tmp.append(.init(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1,4))))
            tmp.append(.init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,4)), hairpinEnd: true))
            return tmp
        }
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
        makeLilyPNG(name: "dynamics_mf_hairpin")
        comparePNGs(gold: lilyDir.appendingPathComponent("dynamics_mf_hairpin.lily.\(SNAP_TAG).png"), test: outDir.appendingPathComponent(name), outBase: "dynamics_mf_hairpin")
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
        var events: [NotatedEvent] = eventsFromFixtureOr("ode_to_joy_excerpt") {
            var tmp: [NotatedEvent] = []
            for (i, it) in seq.enumerated() {
                let dur = Duration(1, it.1)
                var e = NotatedEvent(base: .note(pitch: it.0, duration: dur))
                if i == 0 { e.slurStart = true }
                if i == 3 { e.slurEnd = true }
                if i == 8 { e.slurStart = true }
                if i == 11 { e.slurEnd = true }
                tmp.append(e)
            }
            tmp[0].dynamic = .mp
            return tmp
        }

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
        makeLilyPNG(name: "ode_to_joy_excerpt")
        comparePNGs(gold: lilyDir.appendingPathComponent("ode_to_joy_excerpt.lily.\(SNAP_TAG).png"), test: outDir.appendingPathComponent(name), outBase: "ode_to_joy_excerpt")
    }
    if let url = envEndpoint() { snapOdeToJoy(suffix: "offline", endpoint: nil); snapOdeToJoy(suffix: "rules", endpoint: url) }
    else { snapOdeToJoy(suffix: "offline", endpoint: nil) }
}

// Snapshot 5: Etude in 6/8 — dotted-beat grouping, rest split
do {
    func snapEtudeSixEight(suffix: String, endpoint: URL?) {
        // Two bars: [e e e | e e e], then [rest e e | e e e]
        let seq: [NotatedEvent] = eventsFromFixtureOr("etude_6_8") {
            var tmp: [NotatedEvent] = []
            let notes1: [Pitch] = [.C,.D,.E,.F,.G,.A].map { Pitch(step: $0, alter: 0, octave: 4) }
            for p in notes1 { tmp.append(.init(base: .note(pitch: p, duration: Duration(1,8)))) }
            tmp.append(.init(base: .rest(duration: Duration(1,8))))
            tmp.append(.init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,8))))
            tmp.append(.init(base: .note(pitch: Pitch(step: .F, alter: 0, octave: 4), duration: Duration(1,8))))
            tmp.append(.init(base: .note(pitch: Pitch(step: .G, alter: 0, octave: 4), duration: Duration(1,8))))
            tmp.append(.init(base: .note(pitch: Pitch(step: .A, alter: 0, octave: 4), duration: Duration(1,8))))
            tmp.append(.init(base: .note(pitch: Pitch(step: .B, alter: 0, octave: 4), duration: Duration(1,8))))
            return tmp
        }
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
        makeLilyPNG(name: "etude_6_8")
        comparePNGs(gold: lilyDir.appendingPathComponent("etude_6_8.lily.\(SNAP_TAG).png"), test: outDir.appendingPathComponent(name), outBase: "etude_6_8")
    }
    if let url = envEndpoint() { snapEtudeSixEight(suffix: "offline", endpoint: nil); snapEtudeSixEight(suffix: "rules", endpoint: url) }
    else { snapEtudeSixEight(suffix: "offline", endpoint: nil) }
}

// Glyph Sampler — clefs/keys/time changes visible mid‑score
do {
    func snapSamplerMarks(suffix: String, endpoint: URL?) {
        var events: [NotatedEvent] = eventsFromFixtureOr("sampler_marks") {
            var tmp: [NotatedEvent] = []
        // Start in treble, C major, 4/4
        tmp.append(.init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,4))))
        // Key change to 2 sharps
        var e1 = NotatedEvent(base: .note(pitch: Pitch(step: .D, alter: 0, octave: 4), duration: Duration(1,4)))
        e1.keyChangeFifths = 2; tmp.append(e1)
        // Time change to 3/4
        var e2 = NotatedEvent(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,4)))
        e2.timeChange = TimeSig(3, 4); tmp.append(e2)
        // Clef change to bass
        var e3 = NotatedEvent(base: .note(pitch: Pitch(step: .F, alter: 0, octave: 3), duration: Duration(1,4)))
        e3.clefChange = .bass; tmp.append(e3)
        return tmp
        }
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
        makeLilyPNG(name: "sampler_marks")
        comparePNGs(gold: lilyDir.appendingPathComponent("sampler_marks.lily.\(SNAP_TAG).png"), test: outDir.appendingPathComponent(name), outBase: "sampler_marks")
    }
    if let url = envEndpoint() { snapSamplerMarks(suffix: "offline", endpoint: nil); snapSamplerMarks(suffix: "rules", endpoint: url) }
    else { snapSamplerMarks(suffix: "offline", endpoint: nil) }
}

// Glyph Sampler — durations and rests with ledger lines
do {
    func snapSamplerDurations(suffix: String, endpoint: URL?) {
        var events: [NotatedEvent] = eventsFromFixtureOr("sampler_durations") {
            var tmp: [NotatedEvent] = []
            tmp.append(.init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 5), duration: Duration(1,1))))
            tmp.append(.init(base: .note(pitch: Pitch(step: .A, alter: 0, octave: 4), duration: Duration(1,2))))
            tmp.append(.init(base: .note(pitch: Pitch(step: .E, alter: 0, octave: 4), duration: Duration(1,4))))
            tmp.append(.init(base: .note(pitch: Pitch(step: .C, alter: 0, octave: 4), duration: Duration(1,8))))
            tmp.append(.init(base: .note(pitch: Pitch(step: .B, alter: 0, octave: 3), duration: Duration(1,16))))
            tmp.append(.init(base: .rest(duration: Duration(1,4))))
            return tmp
        }
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
        makeLilyPNG(name: "sampler_durations")
        comparePNGs(gold: lilyDir.appendingPathComponent("sampler_durations.lily.\(SNAP_TAG).png"), test: outDir.appendingPathComponent(name), outBase: "sampler_durations")
    }
    if let url = envEndpoint() { snapSamplerDurations(suffix: "offline", endpoint: nil); snapSamplerDurations(suffix: "rules", endpoint: url) }
    else { snapSamplerDurations(suffix: "offline", endpoint: nil) }
}

// Glyph Sampler — accidentals across an octave
do {
    func snapSamplerAccidentals(suffix: String, endpoint: URL?) {
        let events: [NotatedEvent] = eventsFromFixtureOr("sampler_accidentals") {
            let pitches: [Pitch] = [
                Pitch(step: .C, alter: 1, octave: 4),  // C#
                Pitch(step: .D, alter: -1, octave: 4), // Db
                Pitch(step: .E, alter: -1, octave: 4), // Eb
                Pitch(step: .F, alter: 1, octave: 4),  // F#
                Pitch(step: .G, alter: -1, octave: 4), // Gb
                Pitch(step: .A, alter: 1, octave: 4),  // A#
                Pitch(step: .B, alter: -1, octave: 4)  // Bb
            ]
            return pitches.map { p in .init(base: .note(pitch: p, duration: Duration(1,4))) }
        }
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
        makeLilyPNG(name: "sampler_accidentals")
        comparePNGs(gold: lilyDir.appendingPathComponent("sampler_accidentals.lily.\(SNAP_TAG).png"), test: outDir.appendingPathComponent(name), outBase: "sampler_accidentals")
    }
    if let url = envEndpoint() { snapSamplerAccidentals(suffix: "offline", endpoint: nil); snapSamplerAccidentals(suffix: "rules", endpoint: url) }
    else { snapSamplerAccidentals(suffix: "offline", endpoint: nil) }
}

print("Wrote snapshots to", outDir.path)
