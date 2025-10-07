import Foundation
import CoreGraphics
import RulesKit
import OpenAPIURLSession

// Lightweight rules service usable from SimpleRenderer.
// If RULES_ENDPOINT is set (e.g., http://127.0.0.1:8080/), calls the Rules API.
// Otherwise, falls back to simple heuristics so rendering remains deterministic offline.
struct RulesService {
    private let endpoint: URL?

    init() {
        if let s = ProcessInfo.processInfo.environment["RULES_ENDPOINT"], let url = URL(string: s) {
            self.endpoint = url
        } else {
            self.endpoint = nil
        }
    }

    // Dynamic kerning with optional hairpin/lyrics context.
    func kerningOffset(dynamicRect: CGRect, hairpinRect: CGRect?, staffSpacing: CGFloat) -> CGPoint {
        // Try typed OpenAPI client first (if endpoint set), with a short synchronous wait.
        if let endpoint {
            // Convert point units to StaffSpace by dividing by staffSpacing.
            let toSP: (CGRect) -> Components.Schemas.BBox = { r in
                .init(x: Double(r.minX / staffSpacing),
                      y: Double(r.minY / staffSpacing),
                      w: Double(r.width / staffSpacing),
                      h: Double(r.height / staffSpacing))
            }
            let dyn = toSP(dynamicRect)
            let hair: Components.Schemas.BBox? = hairpinRect.map { r in toSP(r) }
            let payload = Components.Schemas.DynamicKerningInput(dynamicBBox: dyn, hairpinBBox: hair, lyricBBox: nil)
            let input = Operations.RULE_period_DynamicAlign_period_kerning_with_hairpins.Input(body: .json(payload))
            let transport = URLSessionTransport()
            let client = RulesKit.Client(serverURL: endpoint, transport: transport)
            var resultPoint: CGPoint = .zero
            var got = false
            let sema = DispatchSemaphore(value: 0)
            Task {
                defer { sema.signal() }
                do {
                    let out = try await client.RULE_period_DynamicAlign_period_kerning_with_hairpins(input)
                    if case let .ok(ok) = out, case let .json(obj) = ok.body {
                        // Convert back to point units
                        resultPoint = CGPoint(x: CGFloat(obj.dynamicPosition.x) * staffSpacing,
                                              y: CGFloat(obj.dynamicPosition.y) * staffSpacing)
                        got = true
                    }
                } catch {
                    // ignore; fall back
                }
            }
            _ = sema.wait(timeout: .now() + 0.050) // 50 ms budget
            if got { return resultPoint }
        }
        // Heuristic fallback: small rightward nudge, keep baseline
        return CGPoint(x: max(0, dynamicRect.width * 0.05), y: 0)
    }

    // Remote beaming suggestion with fast fallback.
    // Returns optional groups of indices to beam together, otherwise nil.
    func beamGroups(beatPos: [Double], beatsPerBar: Int, beatUnit: Int, isNote: [Bool], denoms: [Int]) -> [[Int]]? {
        guard let endpoint, isNote.count == denoms.count else { return nil }
        let transport = URLSessionTransport()
        let client = RulesKit.Client(serverURL: endpoint, transport: transport)
        // Build noteValues as simple strings like "1/8" for notes; "rest" for rests.
        let noteValues: [String] = zip(isNote, denoms).map { pair in
            let (n, d) = pair
            return n ? "1/\(max(1, d))" : "rest"
        }
        let ts = Components.Schemas.BeamingSubdivisionInput.timeSignaturePayload(beatsPerBar: beatsPerBar, beatUnit: beatUnit)
        let payload = Components.Schemas.BeamingSubdivisionInput(timeSignature: ts, noteValues: noteValues)
        let input = Operations.RULE_period_Beaming_period_subdivision_preference.Input(body: .json(payload))

        var result: [[Int]]? = nil
        let sema = DispatchSemaphore(value: 0)
        Task {
            defer { sema.signal() }
            do {
                let out = try await client.RULE_period_Beaming_period_subdivision_preference(input)
                if case let .ok(ok) = out, case let .json(obj) = ok.body {
                    let breaks = Set(obj.beamBreaks)
                    // Compose groups from break indices over beamable notes
                    var current: [Int] = []
                    var groups: [[Int]] = []
                    for i in 0..<isNote.count {
                        let beamable = isNote[i] && denoms[i] >= 8
                        if !beamable {
                            if current.count >= 2 { groups.append(current) }
                            current.removeAll(keepingCapacity: true)
                            continue
                        }
                        current.append(i)
                        if breaks.contains(i) {
                            if current.count >= 2 { groups.append(current) }
                            current.removeAll(keepingCapacity: true)
                        }
                    }
                    if current.count >= 2 { groups.append(current) }
                    result = groups
                }
            } catch {
                // fall back
            }
        }
        _ = sema.wait(timeout: .now() + 0.050)
        return result
    }
}
