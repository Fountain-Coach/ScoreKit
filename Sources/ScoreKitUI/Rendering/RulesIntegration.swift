import Foundation
import CoreGraphics
import RulesKit

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
        // Remote call if endpoint configured
        if let endpoint {
            var req = URLRequest(url: endpoint.appendingPathComponent("apply/dynamicstext/DynamicAlign-kerning_with_hairpins"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "dynamicBBox": ["x": dynamicRect.minX, "y": dynamicRect.minY, "w": dynamicRect.width, "h": dynamicRect.height],
                // hairpinBBox optional
                "hairpinBBox": hairpinRect.map { ["x": $0.minX, "y": $0.minY, "w": $0.width, "h": $0.height] } as Any
            ]
            do {
                req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                let sema = DispatchSemaphore(value: 0)
                var out: CGPoint = .zero
                let task = URLSession.shared.dataTask(with: req) { data, resp, _ in
                    defer { sema.signal() }
                    guard let data, let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
                    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let pos = obj["dynamicPosition"] as? [String: Any],
                       let x = pos["x"] as? Double, let y = pos["y"] as? Double {
                        out = CGPoint(x: x, y: y)
                    }
                }
                task.resume()
                _ = sema.wait(timeout: .now() + 0.050) // 50 ms budget to keep UI snappy
                if out != .zero { return out }
            } catch {
                // fall through to heuristic
            }
        }
        // Heuristic fallback: small rightward nudge, keep baseline
        return CGPoint(x: max(0, dynamicRect.width * 0.05), y: 0)
    }
}

