# UI and UX Foundation

## Normal HUD

The default HUD contains one compact top status rail and a two-row Quickbar. Seed controls, regeneration, geology shortcuts, full keyboard help, and diagnostics are hidden from normal play. `F3` retains the developer diagnostics panel.

The shared theme uses dark industrial slate, amber/brass selection, compact spacing, restrained borders, crisp type, and explicit hover/pressed/locked states. The Research Tree inherits the same theme.

## Quickbar

- Two persistence-ready pages, ten slots each.
- Active page uses `1`–`0`; `PageUp` and `PageDown` select pages.
- Slots reference build structures, automation tools, terrain/creative tools, or Remove—not inventory stacks.
- Catalog entries drag into slots; slot-to-slot drag swaps; right-click clears.
- Locked researched items remain visible but disabled.
- `serialize_quickbars()` and `deserialize_quickbars()` provide a versioned persistence boundary.

## Build Catalog

`B` opens a searchable catalog containing Logistics, Processing, Storage, Automation, Infrastructure, and Terrain / Creative entries. Each entry has an original code-drawn icon, name, category/search text, research lock state, click selection, and drag assignment.

## Interaction and inspection

Normal clicks select/build through `WorldCommandBus`. World tooltips remain concise; detailed automation and machine state stays in contextual inspectors. Wiring Mode and Research are focused overlays rather than permanent HUD columns. Gameplay actions are represented in Godot `InputMap`, retaining rebind and browser-input readiness.

## Layout

All permanent controls use anchors and containers. The layout was designed for 1920×1080 and scales with browser/laptop viewports; no core HUD element is positioned from hardcoded 1080p world coordinates.
# Phase 8 UI

Fluid structures live in the paged Build Catalog and can be assigned to either 10-slot Quickbar. Pipe drag previews remain horizontal/vertical and submit one batch. The Research Tree lays out four fluid nodes without clipped cards. Normal view shows physical Pipe fill/motion, Pump operation, Valve state, Reservoir Water, and Sluice slurry; numeric mass/flow/temperature/pressure/health appears only in contextual diagnostics.

## Phase 8.75 factory UX

- Quickbars: up to ten serialized pages of ten slots; one active row is instantiated.
- InputMap: `copy`, `cut`, `paste`, `undo`, `redo`, `pipette`, `rotate`, `flip_horizontal`, `flip_vertical`, `info_mode`, `statistics`, `overlay_selector`, `blueprint`.
- Pipette selects the hovered catalog tool/configuration without mutating a Quickbar slot.
- `U` anchors/cancels rectangular Blueprint selection; `Ctrl+C`/`Ctrl+X` commit copy/cut, `Esc` cancels, and `Ctrl+V` pastes at the cursor.
- Copy/Cut/Paste and planners use one preview plus one `CommandBatch`; Blueprint ghosts are batched draw data, not UI nodes.
- Info Mode uses batched state badges and close-zoom text only; 3,941 visible machine entities measured `611.5 FPS` with `0.0000 ms` CPU overlay draw.
- Factory Statistics is a temporary Slate/Amber panel showing produced/min, consumed/min and net from native rings.
- Alerts are exceptional, rate-limited and click-to-focus. Normal Conveyor jams do not spam.

## Phase 9 inspection

- Temperature Overlay uses the visible cropped `RG8` page and a bounded legend; it is presentation-only.
- Info Mode exposes material phase/amount/temperature and local Pipe fluid/fill/temperature/pressure/health without adding per-cell nodes.
- Factory Statistics includes physical phase production/consumption and `steam_pipe_throughput` in the existing rolling rings.
- Build Catalog groups Temperature Sensor, Pipe Temperature Sensor, Pipe Pressure Sensor, Thermal Switch and Heat Exchanger under their research gates.
- Pipe overtemperature, overpressure and breach remain local click-to-focus alerts. Normal heat exchange and phase transitions do not spam.

## Phase 10 power UX

- The Build Catalog and Quickbar include Shaft, Turbine, Generator, Power Pole, Power Switch, Accumulator, Flywheel, Resistive Heater and the three Power automation components under native Research gates.
- POWER overlay shows batched pole components, cable edges and rotating shaft members; normal view hides cable clutter.
- Diagnostics expose global and cursor-local grid ID, generation, demand, delivery, satisfaction, storage, shaft ID, energy, inertia and milli-RPM.
- Rate-limited alerts cover brownout, Generator overload, Turbine overspeed and backpressure.
- Power Switch and consumer priority changes use the canonical command boundary and remain construction-undo/Blueprint configuration, not runtime-energy snapshots.

## Phase 11 New Game and Character UX

New Game presents Factory (Recommended), Character, and Creative cards plus seed entry, Randomize, Copy/Paste, stable WorldIdentity, and a safe native macro preview. Character HUD adds movement/Jetpack/Hover state, 18-cell range, Dig feedback, and persistent discovered overview while reusing Quickbars/Catalog/Research. Live, stale, and unknown visibility use opacity plus distinct texture patterns, not color alone. Panels use anchors/containers at 1080p and resizable laptop/1440p viewports. Hover toggle/hold, reduced motion, screen-shake control, and UI scale are serializable accessibility preferences.

## Phase 11.5 release-quality pass

`KoalaSandTheme` supplies authored Panel, Button, OptionButton, MenuButton, LineEdit, and Tooltip styles at 100/125/150% scale. `InputGlyphs` resolves InputMap actions. The persistent HUD is compact; Quickbars show only one ten-slot page; Catalog, Research, Statistics, and Map are modal. One contextual Inspector replaces permanent diagnostics. Pointer-over-UI and modal state block world tools; wheel input over UI cannot zoom the world.

ESC resolves placement, top modal/map/research, then pause. Onboarding is per-preset, contextual, one-shot, skippable, resettable, and serializable. Full principles and focus rules are canonical in `UX_GUIDELINES.md`.

## Phase 13.6 commercial-language pass

`KoalaSandTheme` is now the single player-facing token source for surfaces, semantic state, spacing, radii, icon sizes, type hierarchy and `80/120/180 ms` motion. Main Menu/New Game, HUD, Catalog, Codex, Research, Inspector, Map, Blueprints, Experiments and Pause/Settings share the industrial slate/brass language. Character telemetry no longer exposes cells, solver range or FOV timing; Statistics resolves material names and player-scale totals rather than raw material IDs and native timing internals. The exact token contract is in `DESIGN_SYSTEM.md`.

## Phase 13.9B responsive layout contract

The permanent HUD now has two safe regions: one grouped top rail and one coherent bottom dock. Workspace panels occupy the rectangle between them and replace one another rather than stacking. The bottom dock owns a contextual tool strip, primary Quickbar, subordinate pager and secondary Catalog/Blueprint access; constrained 150% layouts wrap groups inside that single dock.

Build Catalog cards use separate icon, name, category/lock and badge Controls. Columns respond to viewport and UI scale. Tooltips evaluate four orientations, use their real post-theme minimum size, and avoid the target, persistent HUD and open workspace. Guided highlight labels use the same safe-region policy and competing hints queue. The executable contract and supported matrix are documented in `PHASE139B_UI_REBUILD.md`.
