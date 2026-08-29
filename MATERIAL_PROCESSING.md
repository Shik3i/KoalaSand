# Physical Material Processing

> **HISTORICAL / SUPERSEDED DESIGN CONTEXT:** This records the Phase 4–6.5 transition. Current component-built processing and exact constituent conservation are defined by `PHYSICAL_PROCESSING.md`, `COMPOSABLE_PROCESSING.md` and `MATERIAL_CONSERVATION.md`.

Phase 6.5 processing is native, deterministic, dry, visible, and mass-conserving. Power, liquids, gas, pollution, filters, casting, and residue reprocessing remain out of scope. `PHYSICAL_PROCESSING.md` is the detailed physical contract.

## Cell identity

Production chunks use SoA arrays totaling exactly `9 bytes/cell`:

| Field | Type | Bytes |
|---|---:|---:|
| material | `uint16` | 2 |
| temperature | `uint16`, absolute `0.25 K` units | 2 |
| flags | `uint8` | 1 |
| provenance | `uint16` | 2 |
| mineral signature | `uint16` | 2 |

Godot-facing reads retain signed `-1` for guarded, ungenerated in-bounds cells. Stored stable material IDs are `0..15`; no stored sentinel is required. Natural Raw Sand signatures hash world seed, generation version, original coordinate, and a stable salt. Creative repaint uses the painted coordinate. Erasing clears provenance/signature; repainting the same coordinate reproduces both.

Gravity, Conveyors, chunk crossings, Screen permeability, magnetic lift/capture, Radiant Furnace reactions, and Crude Residue preserve provenance/signature. The hidden constituent is derived, not stored:

```text
packed geological profile + mineral signature
-> SILICA | IRON_BEARING | HEAVY_MINERAL | GOLD_BEARING | OTHER
```

Gold-bearing grains only exist when the profile's gold-anomaly bucket is nonzero. Processing cannot manufacture a constituent absent from the source population.

## Stable materials

| ID | Material | Behavior |
|---:|---|---|
| 6 | Fine Sand | granular, transportable |
| 7 | Heavy Concentrate | granular, transportable |
| 8 | Iron Concentrate | granular, transportable |
| 9 | Nonmagnetic Concentrate | granular, transportable |
| 10 | Glass | granular product |
| 11 | Iron | granular product |
| 12 | Gold | rare granular product |
| 13 | Crude Residue | granular waste with retained metadata |
| 14 | Coal Chunk | granular fuel |
| 15 | Ash | granular fuel residue |

Embedded solid Coal remains ID `4`. `harvest_cell()` maps Coal terrain to one physical Coal Chunk. Bedrock is protected.

## Deterministic reaction tables

Every imperfect decision hashes only `mineral_signature`, `provenance`, and stable process definition ID. Machine ID, position, tick, worker scheduling, and runtime RNG are excluded. All mineral transformations are exactly one physical input to one physical output.

| Feed / process | Constituent | Primary configured recovery |
|---|---|---:|
| Raw / Crude Furnace | Silica -> Glass | 80% |
| Raw / Crude Furnace | Iron-bearing -> Iron | 25% |
| Raw / Crude Furnace | Gold-bearing -> Gold | 5% |
| Fine / Furnace | Silica -> Glass | 95% |
| Heavy / Furnace | Iron-bearing -> Iron | 50% |
| Heavy / Furnace | Gold-bearing -> Gold | 20% |
| Iron Concentrate / Furnace | Iron-bearing -> Iron | 90% |
| Nonmagnetic / Furnace | Gold-bearing -> Gold | 50% |
All failed thermal reactions become Crude Residue. Screen classification instead derives stable grain size; magnetic capture derives susceptibility. Neither uses a random output table, and neither duplicates or destroys a grain.

## Physical machines

Stable structure/unlock IDs:

| Type | Unlock key | Physical behavior | Hidden material state |
|---:|---|---:|---|
| 5 Radiant Crude Furnace | `processing.crude_furnace` | local distance-attenuated heat; in-place threshold reaction | none |
| 6 Vibrating Screen | `processing.vibrating_screen` | stable aperture permeability plus deterministic deck agitation | none |
| 7 Overbelt Magnetic Separator | `processing.overbelt_magnet` | local integer field, cell-by-cell lift, upper capture transport | none |
| 8 Research Bank | `progression.research_bank` | one useful physical cell deposited per tick; physical reject | intentional global reserve boundary |

The three processors contain no feed slot, finished-product slot, fuel counter, Ash slot, or teleport output. Blocked matter remains visible in world cells and physically backs up.

Fixed tick order:

1. queued/direct mutations;
2. granular gravity;
3. magnetic fields;
4. screen vibration;
5. radiant heat and in-place reactions;
6. Conveyor/capture transport;
7. Research Bank and automation;
8. publish tick.

Movement bit `0` prevents a cell from gravity-moving, magnet-moving, screen-moving, and belt-moving more than once per tick.

Native spatial watchers map changed chunks/cells to nearby physical processors. Active sets are sorted by stable ID. Empty fields/decks/heating bays sleep; local matter changes wake only interested processors.

## Measured recovery

Same `100,000`-grain profile `2386`:

| Route | Glass | Iron | Gold | Residue | Coal | Ash |
|---|---:|---:|---:|---:|---:|---:|
| A Raw -> Furnace | 67,522 | 1,251 | 0 | 31,227 | 1,563 | 1,563 |
| B Sieve -> Furnaces | 77,043 | 2,323 | 0 | 20,634 | 1,563 | 1,563 |
| C Sieve -> Magnetic -> Furnaces | 76,478 | 4,024 | 0 | 19,498 | 1,563 | 1,563 |

Gold anomaly profile `64848`: Route A/B/C yielded `58 / 177 / 476` Gold. A profile with gold bucket `0` yielded exactly zero Gold on all routes.

## Debug and verification

`F3` shows signature, hidden constituent, scheduler/throughput totals, and a cursor-selected machine inspector. `H` harvests Coal; `V` selects the Sieve; `M` selects the Magnetic Separator. Normal machine inspection omits the hidden constituent.

```powershell
.\scripts\godot.ps1 --headless --path . --script res://tests/phase4_correctness.gd
.\scripts\godot.ps1 --headless --path . --script res://tests/benchmark_phase4.gd
.\scripts\godot.ps1 --path . --user-args --dense-factory --benchmark-runtime-ticks=300 --capture-1080p
```

Direct captures are under `artifacts/phase4/`. No Computer Use is required.

## Phase 5 technology effects

Research changes physical parameters and stable reaction definitions. Belt Drive changes shared belt cadence; Precision Screening changes aperture classification; Thermal Efficiency reduces distance attenuation; Radiant Intensity increases local heat flux; High-Throughput Handling changes upper capture cadence. Existing physical cells, provenance, signatures, temperature, and residue are never rewritten retroactively. Exact costs and dependencies are canonical in `PROGRESSION.md`.
## Phase 6 machine control

Existing processors expose deterministic state telemetry and a cached ENABLE input. Disabled processors retain no material internally: world cells remain where physics leaves them and receive no field, vibration, or heat work. State transitions wake only sensors registered to that entity ID.
