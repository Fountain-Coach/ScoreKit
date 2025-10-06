# ScoreKit Status Audit — 2025-10-05

This document captures the current state of ScoreKit and the gaps to close so that "talking music" with AudioTalk yields immediate, faithful previews without manual editing.

## Summary
- Strong base: single-staff renderer, incremental reflow (per-measure + neighbor-span spans), minimal AI preview flow, playback stub, SMuFL rendering, demo assets, CI benches.
- Strategy shift: Engraving package becomes the engraving authority. LilyPond is deprecated (interop only, disabled by default).
- Priority gaps: compound meter beaming/slanted beams via Engraving, ties rendering polish, CoreMIDI timestamped scheduling, multi-voice/staff, semantics→playback depth, live AI streaming endpoint, visual tests.

## Current Capabilities (anchors)
- Renderer
  - Layout + draw: `Sources/ScoreKitUI/Rendering/SimpleRenderer.swift:47`
  - Incremental reflow API: `Sources/ScoreKitUI/Rendering/SimpleRenderer.swift:284`
  - Beaming (within beat): `Sources/ScoreKitUI/Rendering/SimpleRenderer.swift:113`, draw at `:224`
  - Hit-test: `Sources/ScoreKitUI/Rendering/SimpleRenderer.swift:271`
- UI / Preview
  - ScoreView (caching + updateLayout): `Sources/ScoreKitUI/Views/ScoreView.swift:160`
  - Highlights + controller: `Sources/ScoreKitUI/Interaction/TeatroBridge.swift:12`
  - AudioTalkPreviewSession (apply ops → changed indices): `Sources/ScoreKitUI/Interaction/AudioTalkPreview.swift:7`
  - Demo action (“Run AI Preview”): `Sources/ScoreKitDemo/AppMain.swift:115`
- Playback
  - Schedule to abstract sink: `Sources/ScoreKit/Playback/PlaybackEngine.swift:11`
  - CoreMIDI sender (immediate): `Sources/ScoreKit/Playback/CoreMIDIPort.swift:30`
- Engraving / SMuFL
  - Central SMuFL catalog + glyph usage in renderers: `Sources/ScoreKitUI/Rendering/SMuFLCatalog.swift:1`, `SimpleRenderer.swift:…`, `MultiRenderer.swift:…`
- LilyPond (deprecated; interop only)
  - Parser (subset, gated by `ENABLE_LILYPOND`): `Sources/ScoreKit/ImportExport/LilyParser.swift:1`
  - Emitter (gated by `ENABLE_LILYPOND`): `Sources/ScoreKit/Engraving/LilyEmitter.swift:1`
- Bench + CI
  - CI workflow + soft perf checks: `.github/workflows/ci.yml:1`
  - Bench: `swift run ScoreKitBench`
- Demo assets
  - GIF/MP4 Tonleiter (calm, y-down, title): `Docs/scorekit-demo.gif`, `Docs/scorekit-demo.mp4`

## Gaps vs. Promise
- Engraving rules
  - Compound meters (6/8, 12/8) grouping; rests/ties splitting; slanted beams.
  - Ties rendering (model flags exist; no tie curves drawn).
  - Spacing anchors per beat; collisions; ledger lines; clefs/keys glyphing.
- Multi-voice/multi-staff
  - Single voice/staff only; no cross-voice collisions/joins.
- Playback scheduling
  - CoreMIDI send is immediate; no JR timestamps/host time mapping.
- Lily coverage
  - Tempo marks, key/time changes, directions, multi-voice constructs limited; ties across barlines/voices.
- Semantics→Playback
  - Basic velocities from hairpins; articulations not mapped to timing/length/attack comprehensively; no MIDI 2.0 per-note attributes.
- AI integration (live)
  - No WebSocket/IPC endpoint to stream ops; no per-apply snapshots for reviews.
- Testing
  - Property tests for Lily round-trip; renderer snapshot tests for beaming/compound; per-scenario perf thresholds; memory profiling.

## Consequences / Decisions
- Focus on AI-driven preview as the core; manual editing is secondary.
- P0 targets emphasize correctness/feel in preview: ties, beaming/compound meters, real-time scheduling.
- Keep ScoreView incremental; avoid heavy editor UI.

## P0 Backlog (next)
1) Engraving integration: beaming + spacing API
   - Replace local `computeBeams` with Engraving API; unify beam levels and groups across renderers.
   - Accept: renderer snapshot tests for 6/8, 9/8, 12/8; rests and tie-aware splits.
2) Ties rendering (single voice)
   - Add tie curves distinct from slurs; support ties across barlines; refine placement.
   - Accept: UI tests for ties over barlines.
3) CoreMIDI JR timestamps
   - Map `ScheduledUMP.time` → host time; send via `MIDISendEventList` with JR timestamps.
   - Files: `Sources/ScoreKit/Playback/CoreMIDIPort.swift:30`, `Sources/ScoreKit/Playback/PlaybackEngine.swift:21`
   - Accept: jitter ≤ 1–2 ms in simple cases; no bursts.

## P1 Backlog (then)
- Multi-voice on one staff (stems up/down per voice, collisions minimal).
- Lily import: tempo/key/time changes; more articulations; slur/tie over rests; multi-voice basics.
- Semantics→Playback: articulation timing/length profiles; optional MIDI 2.0 attributes.
- Live AI endpoint (WebSocket) + per-apply PNG/SVG snapshots for review.

## Hook-In Plan (tomorrow)
- Branching: `feat/p0-<work>`, `fix/<bug>`, `test/<area>`.
- Start with Engraving API adoption; then tests for each P0 item; iterate implement → test → bench.
- Commands
  - Run tests: `swift test`
  - Bench: `swift run ScoreKitBench`
  - Demo: `swift run ScoreKitDemo`
  - GIF/MP4: `swift run ScoreKitGif && swift run ScoreKitVid`
- CI
  - Review CI “ScoreKitBench Results” summary and `bench.txt` artifact.

## Links
- CI: https://github.com/Fountain-Coach/ScoreKit/actions/workflows/ci.yml
- Demo assets: `Docs/scorekit-demo.gif`, `Docs/scorekit-demo.mp4`
