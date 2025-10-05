# AGENTS.md — ScoreKit Engineering Guide (Fountain‑Coach / AudioTalk)

This document guides contributors and agents building ScoreKit — the notation and real‑time rendering layer described in “ScoreKit: Unifying Notation and Real‑Time Rendering in Fountain‑Coach”. It operationalizes the vision from AudioTalk into concrete architecture, conventions, and milestones for this repository.

## Scope
- Applies to the entire repository, with emphasis on:
  - `Sources/ScoreKit/**`
  - `Sources/ScoreKitUI/**`
  - `Examples/ScoreKit*/**`
  - `Tests/ScoreKit*/**`

## Mission
- Unify professional engraving (LilyPond as source of truth) with Swift‑native, real‑time score rendering for interactive coaching, editing, and playback.
- Expose a stable Swift API and data model that AI (FountainAI), storage (Fountain‑Store), and audio (MIDI 2.0 / engines) can consume.

## Non‑Goals (for v0)
- Full DAW replacement, full MEI/MusicXML round‑trip fidelity, complex page layout features (parts, cues, ossia) beyond interactive coaching needs.

---

## Architecture Overview
- Core Data Model: immutable-ish score graph with persistent IDs (document, part, staff, measure, voice, event). Semantic annotations are first‑class.
- Engraving Pipeline: LilyPond wrapper for publication‑quality output (PDF/SVG). LilyPond remains the canonical serialization.
- Real‑Time Renderer: Swift renderer (CoreGraphics/SwiftUI) inspired by Verovio for immediate, incremental redraws and highlight/animation.
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

## Engraving (LilyPond)
- `LilySession` manages temp workdirs, `.ly` generation, process exec, stderr capture, and artifact collection (PDF/SVG/PNG).
- macOS/Linux: runtime LilyPond usage if binary present. iOS: disable and fallback to native rendering.
- CLI: non‑interactive flags, temp outputs, bounded runtime; capture diagnostics with measure/beat context.
- Mapping: Model → Lily (idempotent, stable); Semantics → Lily as `%!AudioTalk:` comments; Lily → Model subset with passthrough for unknown blocks.
- Snapshots: fixtures for `.ly` and tiny PDFs/SVGs under `Tests/Fixtures` with size limits.

---

## Real‑Time Renderer (SwiftUI/CoreGraphics)
- Goals: 60 fps interactions, <16 ms incremental updates, crisp vector output.
- Layout: per‑measure/system incremental engraving; glyph metric caches.
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
- Export: LilyPond (canonical), SVG/PNG snapshots, JSON (model+semantics) for Fountain‑Store.
- Import: Lily subset; MusicXML/MEI optional via feature flag.

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

---

## Testing Strategy
- Unit: model transforms, diff/apply, identity, rational arithmetic.
- Property: Lily subset round‑trip; idempotent emit/parse.
- Snapshot: Lily strings, SVG/PNG (small views), layout trees (JSON form).
- Integration: LilyPond exec on macOS/Linux CI with timeouts and artifact checks.

---

## Tooling & Environment
- Swift 5.9+ / SwiftPM.
- LilyPond (runtime optional), detected via PATH; not bundled on iOS.
- PDFKit (display); CoreGraphics (drawing).
- Optional Verovio interop via feature flag.

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

## Milestones
- M0 Bootstrap: Package scaffolding, core types, fixtures, CI.
- M1 LilyPond Wrapper: `.ly` emit + CLI exec + error capture + tests.
- M2 Model Transforms: edits (slur, hairpin, articulation), diff/apply, semantics API.
- M3 Renderer MVP: single‑staff layout + notes/rests + ties/slurs + basic dynamics; hit‑testing.
- M4 Semantics→Playback: tags → UMP profiles; follow playhead.
- M5 Import: Lily subset parser, round‑trip tests.
- M6 UI: `ScoreView` SwiftUI with selection/highlighting; Teatro hooks.
- M7 Performance: caches, incremental layout, benchmarks.
- M8 Docs & Examples: playground app; end‑to‑end AudioTalk demo.

Definition of Done (per feature)
- API documented; tests written; snapshots updated; no perf regressions; actionable diagnostics.

---

## References
- AudioTalk VISION.md (semantic layer)
- LilyPond documentation; MIDI 2.0 UMP specifications; Verovio design notes

