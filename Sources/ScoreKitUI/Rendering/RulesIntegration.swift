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
    func kerningOffset(dynamicRect: CGRect, hairpinRect: CGRect?) -> CGPoint {
        // Try typed OpenAPI client first (if endpoint set), with a short synchronous wait.
        if let endpoint {
            // Convert to staff-space BBoxes using a best-effort scale of 1.0 (caller may pass in staff-space already).
            // If canvas units are in points, rules expect StaffSpace. We assume inputs were pre-scaled for now.
            let dyn = Components.Schemas.BBox(x: dynamicRect.minX, y: dynamicRect.minY, w: dynamicRect.width, h: dynamicRect.height)
            let hair: Components.Schemas.BBox? = hairpinRect.map { r in .init(x: r.minX, y: r.minY, w: r.width, h: r.height) }
            let payload = Components.Schemas.DynamicKerningInput(dynamicBBox: dyn, hairpinBBox: hair, lyricBBox: nil)
            let input = Operations.RULE_period_DynamicAlign_period_kerning_with_hairpins.Input(body: .json(payload))
            let transport = URLSessionTransport()
            let client = RulesKit.Client(serverURL: endpoint, transport: transport)
            var resultPoint: CGPoint = .zero
            let sema = DispatchSemaphore(value: 0)
            Task {
                defer { sema.signal() }
                do {
                    let out = try await client.RULE_period_DynamicAlign_period_kerning_with_hairpins(input)
                    if case let .ok(ok) = out, case let .json(obj) = ok.body {
                        resultPoint = CGPoint(x: obj.dynamicPosition.x, y: obj.dynamicPosition.y)
                    }
                } catch {
                    // ignore; fall back
                }
            }
            _ = sema.wait(timeout: .now() + 0.050) // 50 ms budget
            if resultPoint != .zero { return resultPoint }
        }
        // Heuristic fallback: small rightward nudge, keep baseline
        return CGPoint(x: max(0, dynamicRect.width * 0.05), y: 0)
    }
}
