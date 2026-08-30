# UX Guidelines

This file is the canonical player-UX contract.

## Principles

- World first: normal play is dominated by the physical world, not panels.
- Contextual UI: show Inspector, warnings, placement reasons, and onboarding only when relevant.
- Minimal persistent HUD: mode/world identity, material balances, core navigation, compact Quickbar.
- One authored visual language: no stock/debug-looking controls in player surfaces.
- Same Build language across Factory, Character, and Creative.
- No information leaks in Character: unknown terrain, hidden geology, provenance, feature anchors, and remote live state remain hidden.
- Fast cancellation and recovery: placement cancel precedes modal close; modal close precedes pause. Undo changes construction, never physics time.
- Important state is never color-only; shape, icon, pattern, text, or motion must reinforce it.
- QoL is not Research-gated. Research unlocks capabilities, not basic UI comfort.
- Physicality before recipe abstraction: UI explains visible interaction and failure; it does not disguise black-box conversion.

## Surfaces

- HUD: compact top bar; transient notification/onboarding panel; contextual Character status.
- Quickbar: one page of ten slots, explicit previous/next page, shared tool glyphs.
- Build Catalog: searchable modal; blocks world input; closes through the unified ESC stack.
- Research: dedicated modal over the same progression ledger.
- Inspector/Info Mode: one context at a time; nearby-state hints; no persistent diagnostic wall.
- Map: Character shows live, discovered/stale, and unknown; Factory/Creative show macro overview. It is never a remote live camera.
- Statistics and overlays: optional, explicit, closeable; forbidden Character information stays unavailable.
- New Game: player-facing Factory/Character/Creative cards, seed Randomize/Copy/Paste, safe WorldGen V2 preview, no developer enum labels.
- Onboarding: contextual per preset, one-shot hints, skip/reset, serialized state.

## Input and focus

All important gameplay commands use `InputMap`; `InputGlyphs` resolves displayed bindings. Mouse wheel over UI never zooms the world. Pointer-over-UI and modal state block world tools. ESC order is placement, top modal/map/research, then pause. Pipette and local Character construction enforce visibility and range.

## Accessibility and layout

Supported UI scales: `100%`, `125%`, `150%`. Hover supports toggle and hold. Reduced motion removes camera smoothing/effects; screen shake is independently disableable. Live/stale/unknown and valid/invalid/warning states use text/icons/patterns in addition to color.

The current layout is smoke-tested at `1920x1080`, `2560x1440`, and `1600x900`. Containers and anchors own layout; fixed positions are reserved for bounded overlays whose offsets are defined relative to their anchors.

Phase 12 keeps organic UX contextual: Character HUD names the active Dig/Cut/Igniter tool; Factory exposes one area-clear tool; Creative Catalog groups organic paint materials; Info/Diagnostics shows material, temperature, moisture, oxidizer and reaction progress only when inspected. Aggregated Tree/fuel/byproduct/Food counts live in Statistics. Flames are batched and honor reduced-motion visual settings; ordinary controlled fire does not emit alert spam.

## Phase 13 session UX

Launch opens Main Menu with Continue, saved-world selection/Load, Delete confirmation and New World mode/seed/name. Pause exposes Resume, Save/Save As, autosave interval, UI scale, reduced motion, screen shake, window mode, audio and control hooks, Save + Menu and Save + Exit. Tutorials describe physical concepts and encourage editing example Blueprints; they never promise recipe outputs.

## Phase 13.8 motion and modal policy

- Important surfaces enter in `120–180 ms` with quadratic ease-out and leave in `80 ms` with quadratic ease-in.
- Reduced Motion makes these transitions immediate; it also continues to suppress camera/effect motion where supported.
- `Esc` closes Pause, Codex, Experiments, Blueprints, placement, Map, Research and HUD modals in player-visible priority order.
- Close buttons must release the same modal lock as keyboard closing; a hidden panel may never continue blocking world input.
- UI scale is reapplied across themed HUD descendants when settings are accepted or restored from a save.
- World Map, Codex, Blueprint Library and Experiments expose explicit close actions and keyboard hints.

## Audio presentation policy

- Procedural output is signed 16-bit PCM at `32 kHz`; looping sources are periodic and seam-safe.
- Raw white-noise beds are forbidden for loops. Filtered noise is restricted to short transient events.
- Player category sliders operate below fixed safety headroom; `100%` does not mean `0 dB` on a category bus.
- Automated Godot processes use `Dummy` audio. Subjective mix checks are manual, single-instance and begin at low system volume.
