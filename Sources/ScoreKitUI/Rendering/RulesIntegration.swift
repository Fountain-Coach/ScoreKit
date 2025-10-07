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
    init(endpoint: URL?) { self.endpoint = endpoint }

    // Dynamic kerning with optional hairpin/lyrics context.
    func kerningOffset(dynamicRect: CGRect, hairpinRect: CGRect?, staffSpacing: CGFloat, budgetMS: Int) -> CGPoint {
        final class KerningBox { var value: CGPoint? = nil }
        let box = KerningBox()
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
            let sema = DispatchSemaphore(value: 0)
            Task {
                defer { sema.signal() }
                do {
                    let out = try await client.RULE_period_DynamicAlign_period_kerning_with_hairpins(input)
                    if case let .ok(ok) = out, case let .json(obj) = ok.body {
                        let p = CGPoint(x: CGFloat(obj.dynamicPosition.x) * staffSpacing,
                                         y: CGFloat(obj.dynamicPosition.y) * staffSpacing)
                        box.value = p
                    }
                } catch {
                    // ignore; fall back
                }
            }
            _ = sema.wait(timeout: .now() + .milliseconds(max(1, budgetMS)))
            if let p = box.value { return p }
        }
        // Heuristic fallback: small rightward nudge, keep baseline
        return CGPoint(x: max(0, dynamicRect.width * 0.05), y: 0)
    }

    // Remote beaming suggestion with fast fallback.
    // Returns optional groups of indices to beam together, otherwise nil.
    func beamGroups(beatPos: [Double], beatsPerBar: Int, beatUnit: Int, isNote: [Bool], denoms: [Int], budgetMS: Int) -> [[Int]]? {
        guard let endpoint, isNote.count == denoms.count else { return nil }
        let transport = URLSessionTransport()
        let client = RulesKit.Client(serverURL: endpoint, transport: transport)

        // Prepare inputs
        let noteValues: [String] = zip(isNote, denoms).map { (n, d) in n ? "1/\(max(1, d))" : "rest" }
        let tsSub = Components.Schemas.BeamingSubdivisionInput.timeSignaturePayload(beatsPerBar: beatsPerBar, beatUnit: beatUnit)
        let payloadSub = Components.Schemas.BeamingSubdivisionInput(timeSignature: tsSub, noteValues: noteValues)
        let inputSub = Operations.RULE_period_Beaming_period_subdivision_preference.Input(body: .json(payloadSub))

        let seq: [Components.Schemas.RestSplitInput.sequencePayloadPayload] = isNote.map { $0 ? .note : .rest }
        let payloadRest = Components.Schemas.RestSplitInput(sequence: seq)
        let inputRest = Operations.RULE_period_Beaming_period_rests_split_groups.Input(body: .json(payloadRest))

        final class BeamBox { var breaks: Set<Int>? = nil; var rest: [[Int]]? = nil }
        let box = BeamBox()

        let sema = DispatchSemaphore(value: 0)
        Task {
            async let br: Set<Int>? = {
                do {
                    let out = try await client.RULE_period_Beaming_period_subdivision_preference(inputSub)
                    if case let .ok(ok) = out, case let .json(obj) = ok.body { return Set(obj.beamBreaks) }
                } catch {}
                return nil
            }()
            async let rg: [[Int]]? = {
                do {
                    let out = try await client.RULE_period_Beaming_period_rests_split_groups(inputRest)
                    if case let .ok(ok) = out, case let .json(obj) = ok.body { return obj.groups }
                } catch {}
                return nil
            }()
            let (b, r) = await (br, rg)
            box.breaks = b
            box.rest = r
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + .milliseconds(max(1, budgetMS)))

        let br = box.breaks
        let rg = box.rest
        // Prefer combination if both available
        if let rg = rg, let br = br {
            var groups: [[Int]] = []
            for g in rg {
                var current: [Int] = []
                for i in g {
                    let beamable = isNote[i] && denoms[i] >= 8
                    if !beamable { if current.count >= 2 { groups.append(current) }; current.removeAll(); continue }
                    current.append(i)
                    if br.contains(i) { if current.count >= 2 { groups.append(current) }; current.removeAll() }
                }
                if current.count >= 2 { groups.append(current) }
            }
            if !groups.isEmpty { return groups }
        }
        // Else choose whichever arrived
        if let br = br {
            var groups: [[Int]] = []
            var current: [Int] = []
            for i in 0..<isNote.count {
                let beamable = isNote[i] && denoms[i] >= 8
                if !beamable { if current.count >= 2 { groups.append(current) }; current.removeAll(); continue }
                current.append(i)
                if br.contains(i) { if current.count >= 2 { groups.append(current) }; current.removeAll() }
            }
            if current.count >= 2 { groups.append(current) }
            if !groups.isEmpty { return groups }
        }
        if let rg = rg {
            // Filter only beamable indices and drop tiny groups
            let filtered = rg.map { $0.filter { isNote[$0] && denoms[$0] >= 8 } }.filter { $0.count >= 2 }
            if !filtered.isEmpty { return filtered }
        }
        return nil
    }
}
