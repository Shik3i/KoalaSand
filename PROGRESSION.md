# Phase 5 Progression

> **HISTORICAL DESIGN CONTEXT:** Current shared MVP progression and recovery behavior are defined by `MVP_PROGRESSION.md` and `RECOVERY_AUDIT.md`.

## Physical-to-abstract boundary

Research Bank is structure type `8`, footprint `8×6`. Its feed port is local `(3,-1)` and its reject port is local `(8,4)`. It handles at most one cell per authoritative simulation tick. State is bounded to the existing one-cell machine slot; there is no hidden queue.

Accepted material IDs are `10 Glass`, `11 Iron`, and `12 Gold`. Acceptance removes the physical cell and increments the matching global signed 64-bit counter in the same native machine operation. Provenance and mineral signature intentionally cease to exist at that boundary. IDs `2`, `6..9`, and `13..15` are never credited. They retain complete metadata in the bounded reject slot and leave through the physical reject port. A blocked reject keeps the Bank in `REJECT_BLOCKED`; further input remains physical and backs up.

All Banks contribute to one authoritative ledger. Totals are never derived by scanning structures. Idle Banks leave the active-machine set. Exact port watchers wake a Bank on input/reject mutation. Machine states are `NO_INPUT`, `ACCEPTING`, `REJECTING`, and `REJECT_BLOCKED`.

Storage Bin remains geometric physical capacity. Research Bank is an irreversible physical-material sink. Phase 5 has no withdrawal.

## State and modes

`progression_schema_version = 1`; research definition version is `1`. The serializable native state contains mode, Glass/Iron/Gold counters, sorted canonical research IDs, and schema/definition versions. Deserialization validates nonnegative balances, known IDs, Foundation presence, and prerequisite closure before replacing state. Unsupported versions fail without mutation.

Fresh Progression mode has zero reserves and only `foundation.basic_industry` unlocked. Creative is an explicit development override for placement and fixture funding; it does not silently enable technology upgrade effects. Full world persistence remains Phase 7.

## Technology tree and costs

| Stable ID | Prerequisites | Glass | Iron | Gold | Effect |
|---|---|---:|---:|---:|---|
| `foundation.basic_industry` | — | 0 | 0 | 0 | Conveyor, Funnel, Storage Bin, Research Bank, Crude Furnace, Harvest |
| `processing.dry_separation` | Foundation | 2,400 | 40 | 0 | unlock Vibrating Sieve |
| `processing.ferrous_separation` | Dry Separation | 3,000 | 180 | 0 | unlock Magnetic Separator |
| `logistics.belt_drive_1` | Foundation | 1,000 | 25 | 0 | all Basic Conveyors: 1 cell/tick instead of 1/2 ticks |
| `furnace.fuel_economy_1` | Foundation | 1,200 | 30 | 0 | Thermal Efficiency I: radiant attenuation falls from 450 to 325 per cell |
| `furnace.throughput_1` | Thermal Efficiency I | 2,200 | 80 | 0 | Radiant Intensity I: local heater strength rises from 2,500 to 3,000 |
| `processing.precision_screening` | Ferrous Separation | 4,000 | 250 | 1 | existing/future Sieves use deterministic `sieve.precision_1` routing |
| `logistics.high_throughput_handling` | Dry Separation, Belt Drive I | 3,500 | 180 | 0 | existing/future Magnetic Separators: 1 instead of 2 ticks/cell |
| `processing.concentrate_recovery` | Ferrous Separation, Furnace Throughput I, High-Throughput Handling | 6,000 | 400 | 2 | concentrate Furnace inputs use deterministic `furnace.concentrate_recovery_1` |

Purchases validate ID, permanent unlock state, every prerequisite, and every cost before any subtraction. Success subtracts all material and unlocks immediately. Failure changes nothing. There are no Research Points and no timed research bar. Structures remain free after unlock. The native placement layer rejects Sieve and Magnetic Separator until their research is unlocked; UI state is not trusted.

Upgrade flags are compact global state read at the existing belt/machine decision points. Existing structures update without scanning or replacement. Processing-definition changes affect future grains only; already-produced physical cells and bank balances never mutate retroactively.

## Measured tuning

Costs derive from Phase-4 deterministic recovery, then the Phase-5 progression evaluator. Representative normal profile `3564`, up to eight early Furnaces at `120 cells/s` aggregate:

| Milestone / route | Raw Sand | Glass produced | Iron produced | Gold produced | Coal | Estimated time |
|---|---:|---:|---:|---:|---:|---:|
| Dry Separation, primitive Furnace | 3,832 | 2,400 | 69 | 0 | 60 | 31.93 s |
| Ferrous cost, Sieve route | 5,008 | 3,580 | 180 | 0 | 79 | 27.82 s |
| Ferrous cost, primitive comparison | 10,347 | 6,552 | 180 | 0 | 162 | 86.23 s |
| Dry + first Belt upgrade envelope | 5,416 | 3,400 | 101 | 0 | 85 | 45.13 s |

The Sieve cuts the Raw Sand needed for the Iron-limited Ferrous milestone by `51.6%` and its representative production time by `67.7%`. This makes the first rebuild pay for itself without making the primitive Furnace route invalid.

Normal profile `3564` correctly produces no Gold. The later cumulative branch therefore measures a nearby deterministic anomaly profile `28140`, representing exploration after Ferrous Separation: `26,246` Raw Sand, `19,300` Glass, `1,666` Iron, `24` Gold, `274` Coal at a representative specialized `240 cells/s`, or `109.36 s`. Only `2` Gold is spent on Concentrate Recovery; Gold is not an early or dominant currency.

## UI and feedback

`T` and the HUD button open the Research Tree. The overlay draws dependency connections and states for unlocked, available, affordable, unaffordable, and prerequisite-locked nodes. Hover/focus, selection, dependency highlighting, exact cost/effect details, and immediate unlock are supported. Locked toolbar entries remain visible and name their required technology; selecting one opens Research instead of entering invalid placement mode. The compact HUD shows only banked Glass/Iron/Gold.

Research Bank presentation is a separate batched machine style with an industrial intake, amber counter display, and red blocked state. It adds no per-machine Node or animation callback.

## Verification and performance

- Phase 5 correctness: `87` checks across eight suites; Bank conservation, reject blockage, multiple Banks, overflow-safe 64-bit ledger, atomic spending, native placement, existing/future upgrades, no retroactivity, serialization, and pacing pass.
- `10,000` idle Banks: `0` active/visited; `0.000 ms` Bank work; `0.028 ms` complete tick average.
- `400` active mixed-stream Banks over 180 ticks: `54,000` accepted; `17,900` rejected; `0` blocked after physical drain; `0.005 ms` Bank average; `0.686 ms` complete tick average including fixture feed/drain.
- Dense 1080p progression factory, Research closed: `318.0 FPS`; frame `3.144 / 4.167 / 7.823 / 43.532 ms` average/p95/p99/worst; simulation `4.332 ms`; logistics `1.790 ms`; machine `0.156 ms`; Bank `0.007 ms`.
- Same factory, Research open: `289.6 FPS`; frame `3.450 / 3.704 / 3.749 / 16.602 ms`; simulation `4.206 ms`; logistics `1.735 ms`; machine `0.147 ms`; Bank `0.005 ms`; Research UI update `0.0044 ms`.

Deterministic captures are under `artifacts/phase5/`: primitive beginning, research ready, tree, Sieve redesign, Magnetic specialization, and wide layered factory. They are direct Godot `4.7.1` captures; no Computer Use.

Phase 5 explicitly excludes sensors/logic, liquids, electricity, full save/load, time-based research, building costs, and withdrawals.
## Phase 6 automation branch

Five stable technologies extend Foundation: `automation.basic_sensing`, `automation.logic_control`, branching `automation.machine_control` and `automation.timed_control`, then `automation.advanced_routing`. Exact dependencies, costs, measured pacing, and unlocks are canonical in [AUTOMATION.md](AUTOMATION.md).

## Phase 6.5 unlock presentation

Research continues to unlock free build tools, not inventory stacks. Locked Screen/Overbelt Magnet entries remain visible and disabled in the Build Catalog and Quickbar. Research Bank remains the intentional physical-to-global progression boundary. Existing dry-route costs stay unchanged until measured physical recovery data justifies a retune.
# Phase 8 fluid branch

| ID | Prerequisites | Cost Glass/Iron/Gold | Effect |
|---|---|---:|---|
| `fluid.basic_handling` | `processing.dry_separation`, `logistics.belt_drive_1` | `2600/120/0` | Pipe, Junction, Intake, Outlet, Basic Pump, Reservoir Wall |
| `fluid.pressurized_transport` | `fluid.basic_handling` | `2200/180/0` | Pump `8192->12288` head, `4096->6144` rate |
| `fluid.flow_control` | `fluid.basic_handling`, `automation.basic_sensing` | `2400/160/0` | Valve, Flow Meter, Pipe Fill Sensor |
| `processing.wet_separation` | `processing.dry_separation`, `fluid.basic_handling` | `3600/240/0` | Wash Sluice |

Measured Phase-5 ferrous-Sieve production (`5008` Raw Sand -> `3580 Glass + 180 Iron` in `27.822 s`) reaches cumulative branch costs without passive waiting: Basic Handling about `3639` Raw / `2600 Glass` / `131 Iron` / `20.2 s`; Pressurized Transport about `8347` Raw / `5965 Glass` / `300 Iron` / `46.4 s`; Flow Control about `7790` Raw / `5568 Glass` / `280 Iron` / `43.3 s`; Wet Separation about `10016` Raw / `7158 Glass` / `360 Iron` / `55.6 s`. Gold remains `0` for every Phase-8 node.

## Phase 8.75 subsurface branch

`logistics.subsurface_1`, `logistics.subsurface_2`, and `logistics.subsurface_3` sequentially unlock depths I/II/III. They extend the existing logistics branch as early/mid factory routing, not endgame transport. Creative bypasses all three gates. Blueprint, Undo/Redo, Pipette, Copy/Cut/Paste, Info Mode and Factory Statistics are UX and never Research-locked.

## Phase 9 thermal branch

| Stable ID | Dependencies | Glass | Iron | Gold | Unlock |
|---|---|---:|---:|---:|---|
| `thermal.basic_thermodynamics` | `foundation.basic_industry`, `automation.basic_sensing` | 1200 | 40 | 0 | Temperature Sensor, Thermal Switch |
| `thermal.phase_processing` | `thermal.basic_thermodynamics`, `furnace.throughput_1` | 2600 | 140 | 0 | Heat Exchanger, phase-processing construction |
| `thermal.steam_handling` | `thermal.phase_processing`, `fluid.flow_control` | 3400 | 220 | 0 | Steam-compatible Pipes, temperature/pressure sensing |
| `thermal.molten_processing` | `thermal.phase_processing`, `processing.concentrate_recovery` | 5200 | 420 | 1 | heat-resistant molten-processing infrastructure |

Natural heat diffusion and phase transitions run before and after these purchases. Research grants tools and safe/rated infrastructure only. It never prevents Water from freezing/boiling or Glass/Iron from melting when physical conditions demand it.

Measured profile `4590` late-route pacing for the complete thermal branch (`12,400` Glass, `820` Iron, `1` Gold): `25,719` Raw Sand at `240/s`, `19,300` Glass, `1,565` Iron, `37` Gold, `268` Coal, conservative upper bound `107.162 s`. This includes enough output for all four branch nodes and is a deterministic route evaluation, not a promise about player build time.

## Reserved Power branch

`power.steam_generation`, `power.electrical_distribution`, and `power.energy_storage` are stable future identifiers only. They are not registered Research nodes and unlock nothing in Phase 9.5. Recommended Phase-10 migration preserves current machines as legacy/basic operation and makes powered variants or upgrades opt-in, avoiding an instant factory-wide shutdown.

## Phase 11 Character mobility

`mobility.sprint` costs `600 Glass / 10 Iron / 0 Gold` after `foundation.basic_industry`. `mobility.hover` costs `1800 Glass / 90 Iron / 1 Gold` after Sprint and `automation.basic_sensing`. Sprint has no stamina/upkeep. Hover stabilizes the always-unlocked Basic Jetpack for local aerial construction. Factory/Creative camera behavior is unaffected; natural movement and visibility are not Research-gated.

The Phase-11.5 deterministic equivalent-time Character fixture reaches Sprint at tick `10,200` (`2:50`) and Hover at tick `30,600` (`8:30`) with no Research-credit test mutation. This places Sprint in the first few minutes and Hover inside the target 5–15 minute window. See `GAMEPLAY_LOOP.md`.
## Phase 12 organic branch

Natural cutting, drying, combustion, pyrolysis and cooking laws are never Research-gated. `organic.wood_processing` records the future Wood-processing branch while basic Cut remains available immediately. `thermal.cookware` requires Basic Thermodynamics plus Ferrous Separation and unlocks Iron Pot for `900 Glass / 60 Iron / 0 Gold`. `organic.combustion_control` is deliberately deferred because Phase 12 adds no Air Vent, Fan or Fire Grate worth unlocking.

## Phase 13 consolidated arc

Research now exposes reusable components rather than player-facing recipe boxes: Mesh/Vibration, Riffle/channel, Electromagnet, structural/metal/ceramic/refractory geometry, Grate/Insulator/Blower and existing energy infrastructure. The terminal milestone requires real processing throughput, completed Research and simultaneously produced/consumed electricity. See `MVP_PROGRESSION.md`.
