# KoalaSand Phase 13.6 — Overnight Polish Sprint

> **HISTORICAL PHASE REPORT:** Presentation evidence feeding the current Phase 13.7 repository baseline.

Version: `0.1.0-playtest.2`
Engine: Godot `4.7.1.stable.official.a13da4feb` through `scripts/godot.ps1`
Scope: presentation, UX, feedback, performance characterization and packaging only. Phase 14 not started.

## Presentation pass

- Centralized industrial design tokens, component states, type hierarchy and `80–180 ms` motion.
- Original procedural functional icon grammar for Quickbar, Catalog and world Components.
- Distinct structural, metal, ceramic and refractory walls; patterned Mesh, Grate and Riffle; readable Pump, Valve, Heater, Vibration, Magnet, Shaft, Turbine and Generator motifs.
- Compact mode-specific HUD, icon-first Quickbar, searchable categorized Catalog and transient status.
- Reworked Main Menu/New Game, Save Browser, Pause/Settings, Research, Codex, Inspector, Map, Blueprints and Experiments.
- State-driven procedural audio variation and pooled physical feedback; no external audio/art assets.

## Dense factory characterization

`--dense-factory` remains an intentionally pathological viewport: 13 near-full-width active belts, 300 structures, broad moving matter, incidental procedural Water and a very large visible dirty region. It is kept as a transparent stress ceiling.

`--realistic-max-factory` is the intended MVP upper-bound fixture: seven busy routes, 96 physical structures and about 56k active-region cells in one 1080p view. It retains the same authoritative simulation and renderer.

Current measurements and final regression evidence are appended to `PERFORMANCE.md` and stored under `artifacts/phase136`.

## Visual evidence

Required final captures: `artifacts/phase136/final`. Contact sheets: UI, world and gameplay under `artifacts/phase136`. Capture generation is reproducible with `scripts/capture_phase136.ps1`; sheets with `scripts/create_phase136_contact_sheets.ps1`.

## Boundaries

- No new production chain, material, biome, combat, survival, multiplayer, web or story system.
- No commit, push, tag, release or PR.
