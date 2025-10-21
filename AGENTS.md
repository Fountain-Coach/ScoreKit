# AGENTS.md — ScoreKit Engineering Guide (Fountain‑Coach / AudioTalk)

This document guides contributors and agents building ScoreKit — the notation and real‑time rendering layer. For historical narrative and the Drift–Pattern–Reflection vision, see the Legacy Docs repository:

- https://github.com/Fountain-Coach/AudioTalk-LegacyDocs

This file focuses on current, code‑level guidance and integration with the Engraving authority.

## Scope
- Applies to the entire repository, with emphasis on:
  - `Sources/ScoreKit/**`
  - `Sources/ScoreKitUI/**`
  - `Examples/ScoreKit*/**`
  - `Tests/ScoreKit*/**`

## Mission
- Unify professional engraving (Engraving engine as source of truth) with Swift‑native, real‑time score rendering for interactive coaching, editing, and playback.
- Expose a stable Swift API and data model that AI (FountainAI), storage (Fountain‑Store), and audio (MIDI 2.0 / engines) can consume.

## Non‑Goals (for v0)
- Full DAW replacement, full MEI/MusicXML round‑trip fidelity, complex page layout features (parts, cues, ossia) beyond interactive coaching needs.

---

## Architecture Overview
- Core Data Model: immutable-ish score graph with persistent IDs (document, part, staff, measure, voice, event). Semantic annotations are first‑class.
- Engraving Engine: external `Fountain-Coach/Engraving` provides SMuFL glyph data/metrics, engraving rules (beaming, spacing, ties/slurs), and optional interop. Engraving becomes the canonical serialization/layout authority.
- Real‑Time Renderer: Swift renderer (CoreGraphics/SwiftUI) inspired by Verovio for immediate, incremental redraws and highlight/animation; consumes Engraving primitives.
- Semantics Layer: AudioTalk tags (`%!AudioTalk: ...`) and structured metadata enabling “speak music, hear it happen”.
- I/O Gateways: Import (LilyPond subset, MusicXML/MEI if available), Export (LilyPond authoritative, SVG/PNG snapshots).
- Integration: FountainAI (intents → ops), Fountain‑Store (versioned persistence/search), MIDI 2.0 engines (UMP per‑note playback), Teatro (UI/storyboards).

SwiftPM packages in this repo:
- `ScoreKit` (model + engraving + import/export)
- `ScoreKitUI` (views, renderer, highlights, cursor, selection)

Target platforms:
- macOS primary. iOS supported with LilyPond disabled at runtime (see License section). Linux for server‑side batch rendering (optional).

---

## Data Model (Core)
- Identity: Every node has a stable `id` (UUID/ULID). Child IDs encode parent linkage.
- Time: `Position` in measures + beats (rational), duration as rational. Don’t assume 4/4.
- Pitch: spelling‑aware (step, alter, octave) plus convenience MIDI number.
- Collections: `Score → Part → Staff → Measure → Voice → Event`
- Event types: Note, Rest, Chord, Tie, Slur (spanning), Articulation, Dynamics, Hairpin, Tempo, Marker, Annotation.
- Semantics: `SemanticTag(key: String, value: Scalar|Enum|Range)` on any node; reserved namespace `AudioTalk.*`.
- Diff/Apply: Pure transforms produce new model instances; patch ops are serializable and composable.

Constraints:
- Deterministic ordering for diff/snapshots.
- No hidden global state; pure transforms preferred.

---

## Engraving Engine (External)
- Source of truth for glyphs, metrics, engraving rules; exposed as a SwiftPM package dependency.
- ScoreKit’s UI uses Engraving APIs for beaming groups/levels, key/clef/time layout, accidentals placement, and symbol glyphs.
- LilyPond is deprecated for runtime/preview. It remains optional for import/export interop only and is disabled by default behind `ENABLE_LILYPOND`.
- If Lily interop is needed, enable `ENABLE_LILYPOND` in `Package.swift` swiftSettings and run on macOS/Linux only.

---

## Real‑Time Renderer (SwiftUI/CoreGraphics)
- Goals: 60 fps interactions, <16 ms incremental updates, crisp vector output.
- Layout: per‑measure/system incremental engraving; glyph metric caches.
- Incremental reflow: `SimpleRenderer.updateLayout` reflows only impacted measures and shifts suffix; expands window to include any intersecting slurs, hairpins, and beam groups for visual correctness.
- Drawing: CoreGraphics primitives; SwiftUI wrappers; optional SVG export.
- Interaction: hit‑testing, selection, caret, region highlight, follow‑playhead.
- Animation: lightweight highlighter for “coaching” changes; integrates with Teatro storyboard concepts.

---

## Semantics (AudioTalk)
- Namespace: `AudioTalk.*` (e.g., `AudioTalk.timbre.brightness`, `AudioTalk.articulation.legato`).
- Attach tags at any node; scope via ranges.
- Translation tables map semantics → UMP/engine params (versioned).
- Surface tags in Lily (comments) and UI (tooltips/inspector).

---

## Playback / MIDI 2.0
- Output UMP with per‑note expression; JR Timestamps for sync.
- Map semantics to midi2sampler/Csound/SDLKit via profiles.

---

## Import / Export
- Export: JSON (model+semantics) for Fountain‑Store; SVG/PNG snapshots via renderer; optional LilyPond (interop).
- Import: optional Lily subset (interop); MusicXML/MEI optional via feature flag.

---

## Integration Points
- FountainAI: high‑level ops (`addSlur`, `applyCrescendo(bars:)`, `annotate(tag:at:)`) with deterministic diffs.
- Fountain‑Store: persist model JSON + LilyPond + assets with searchable metadata.
- Teatro/UI: `ScoreView` SwiftUI; highlight/animate changes; programmatic selection.

---

## Performance Targets
- P50 edit→update ≤ 16 ms; P95 ≤ 33 ms.
- Full page (A4) ≤ 150 ms on M‑series.
- Cache bounded; LRU glyph/layout caches.
- Bench: `ScoreKitBench` runs in CI (release); results uploaded as `bench.txt`. Soft perf checks add warnings for samples > 50 ms without failing builds.

## Benchmarks
- Local: `cd ScoreKit && swift run -c release ScoreKitBench` (prefer release for stable timings).
- CI: GitHub Actions runs `ScoreKitBench` in release and uploads `bench.txt` as an artifact; results are also included in the job summary.
- Thresholds (soft, non-failing warnings):
  - `layout` samples use `LAYOUT_WARN_MS` (default 30 ms).
  - `updateLayout` samples use `UPDATE_WARN_MS` (default 60 ms).
  - Any other lines fall back to `DEFAULT_WARN_MS` (default 50 ms).
- Tuning thresholds:
  - Trigger the workflow manually via “Run workflow” (Workflow Dispatch) and set inputs:
    - `layout_warn_ms` (e.g., 25…40), `update_warn_ms` (e.g., 40…80), `default_warn_ms`.
  - For permanent adjustments, edit `.github/workflows/ci.yml` env defaults:
    - `LAYOUT_WARN_MS`, `UPDATE_WARN_MS`, `DEFAULT_WARN_MS`.
- Reading results:
  - Warnings annotate lines exceeding thresholds (non-fatal).
  - Compare across runs; large deltas often indicate logic changes or debug builds.
  - Measurements vary by runner hardware; compare relative changes more than absolutes.

---

## Testing Strategy
- Unit: model transforms, diff/apply, identity, rational arithmetic.
- Property: Lily subset round‑trip; idempotent emit/parse.
- Snapshot: Lily strings, SVG/PNG (small views), layout trees (JSON form).
- Integration: LilyPond exec on macOS/Linux CI with timeouts and artifact checks.
 - Incremental layout: targeted tests asserting untouched measures retain positions and suffix shifts uniformly; see `PartialReflowTests`.

---

## Tooling & Environment
- Swift 5.9+ / SwiftPM.
- LilyPond (runtime optional), detected via PATH; not bundled on iOS.
- PDFKit (display); CoreGraphics (drawing).
- Optional Verovio interop via feature flag.
 - CI: GitHub Actions runs tests + `ScoreKitBench` and publishes artifacts.

---

## Licensing & Compliance
- LilyPond (GPL) must not be bundled in iOS apps. Use runtime binary (macOS/Linux) or remote service.
- Keep third‑party code isolated with compatible licenses and feature flags.

---

## Conventions
- Semantic commits: `feat:`, `fix:`, `perf:`, `refactor:`, `docs:`, `test:`, `chore:`.
- Public APIs documented; examples provided.
- Errors: typed; no `fatalError`.
- Logging: structured, category‑based; quiet in release.

---

- M0 Bootstrap: Package scaffolding, core types, fixtures, CI.
- M1 Engraving Integration: wire Engraving dependency; SMuFL catalog + metrics; basic beaming/spacing APIs consumed by renderer.
- M2 Model Transforms: edits (slur, hairpin, articulation), diff/apply, semantics API.
- M3 Renderer MVP: single‑staff layout + notes/rests + ties/slurs + basic dynamics; hit‑testing.
- M4 Semantics→Playback: tags → UMP profiles; follow playhead.
- M5 Import (Interop): optional Lily subset parser & round‑trip tests (behind `ENABLE_LILYPOND`).
- M6 UI: `ScoreView` SwiftUI with selection/highlighting; Teatro hooks.
- M7 Performance: caches, incremental layout, benchmarks.
- M8 Docs & Examples: playground app; end‑to‑end AudioTalk demo.

Definition of Done (per feature)
- API documented; tests written; snapshots updated; no perf regressions; actionable diagnostics.

---

## References
- AudioTalk VISION.md (semantic layer)
- LilyPond documentation; MIDI 2.0 UMP specifications; Verovio design notes
