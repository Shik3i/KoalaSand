# Simulation

## Coordinates and chunks

Production chunks are `64×64` cells in `NativeSandWorld`. The reference oracle remains `128×128` through `WorldConfig`; parity tests prove chunk granularity does not change Phase 1 results. Floor division keeps local coordinates valid for negative world positions. Chunks are allocated lazily by signed coordinates.

Chunk state uses flags: `ACTIVE`, `SLEEPING`, and `DIRTY`. Mutation wakes and dirties its owning chunk and increments a revision. Eight consecutive simulation ticks without movement put an active chunk to sleep.

## Cell representation

The `128×128` GDScript oracle keeps its original three arrays. Production `64×64` native chunks use:

| Field | Native type | Bytes/cell | Meaning |
|---|---:|---:|---|
| Material | `uint16` | 2 | Stable stored registry ID; guarded `-1` exists only at the signed API boundary |
| Temperature | `uint16` | 2 | Absolute quarter-kelvin: `0..65535` = `0..16383.75 K`; ambient `1173` = `293.25 K` |
| Flags | `uint8` | 1 | Transient state; bit `0` is moved-this-authoritative-tick |
| Provenance | `uint16` | 2 | Stable packed Raw Sand geology profile; `0` for other materials |
| Mineral signature | `uint16` | 2 | Stable geological grain sample retained through processing |

Native temperature is absolute, not offset Celsius. Arithmetic clamps to `[0,65535]`; ordinary heating cannot wrap. The Radiant Furnace currently reacts at `5893` (`1473.25 K`) and preserves accumulated temperature when material changes. The Phase-0 GDScript reference simulator retains a separate `PackedInt32Array` centi-Celsius field and is not the production native layout.

Production simulation backing remains `9 bytes/cell`; `36,864 bytes` per 4,096-cell chunk. Phase 4 narrowed material IDs from four to two bytes and spent those two bytes on mineral signature. A separate RGBA cache costs `4 bytes/cell`. Optional structure occupancy costs `1 byte/cell` (`4,096` bytes) only in a structure-bearing chunk.

## Determinism and geology

Simulation code receives a world seed and uses coordinate hashes only. It must not use global random calls. Traversal and serialized output use chunks sorted by `(y, x)`. Production geology derives stable packed `uint16` profile IDs from continuous regional fields. Raw Sand stores the ID eagerly because it must survive arbitrary granular movement; decoded composition dictionaries are created only for inspection.

## Clock and rendering

`SimulationClock` accumulates render delta and emits fixed `1/60 s` ticks at pause, `1×`, `2×`, or `4×`. Render cadence cannot change the tick sequence. `NativeSandWorld` owns the matching deterministic tick index.

`NativeSandWorld` converts dirty bounds to cached RGBA8 in persistent background workers; `DebugCellRenderer` updates retained textures on the main thread. Stable palettes, coordinate variation, exposed edges, and depth tint remain deterministic and seam-safe. Rendering never owns material truth and never creates per-cell Nodes.

## Phase 1 granular algorithm

For each active granular cell:

1. Move to `(x, y + 1)` when Empty.
2. When blocked, hash `world_seed + source_position + simulation_tick` to choose the first diagonal.
3. Try that diagonal, then the other diagonal.
4. Remain when neither is Empty.

Water is occupied but has no update behavior; Phase 1 performs no displacement.

Traversal is global-row-safe rather than chunk-at-a-time. Chunk bands run from greatest chunk `y` to least; within one band, every chunk completes local row `63` before any begins row `62`. Global `x` alternates direction each tick. Every gravity target is one row lower, so no gravity-moved particle meets that cursor twice. Conveyor transport follows gravity. Both phases share bit `0` of the already allocated flags byte, so a cell that fell this tick cannot also travel on a belt. Double-movement prevention adds `0` new bytes/cell.

## Phase 3 logistics phase

Every second fixed tick, the native Conveyor phase sorts material-contact belt cells by `(y,x)`. Only the transportable cell directly above each belt is considered. A free horizontal destination receives the complete material state; a blocked destination remains a jam. First source in stable order wins conflicts. Empty belts never enter the active set, so sleeping factories do not scan their full infrastructure. Full semantics and batch APIs are in `FACTORY_LOGISTICS.md`.

## Phase 4 machine phase

Machine intake/progress/output follows Conveyors and precedes tick publication. The same moved flag prevents same-tick gravity -> belt -> machine chains and stamps newly emitted output until the next tick. Port mutations wake exact native watchers. Active machines are sorted by stable entity ID; starved idle machines leave the hot set. Mineral transformations copy provenance/signature and conserve one input grain to one output grain. Furnace fuel conserves one Coal Chunk to one Ash. Full tables and states are in `MATERIAL_PROCESSING.md`.

Each chunk has a conservative active rectangle. Initialization bounds granular cells; movement expands next-tick bounds with a one-cell dependency halo. The previous bounds remain until eight stable ticks to preserve supported-pile correctness. Sleeping clears them. Render-dirty bounds are separate and never wake physics.

The authoritative algorithm is serial. Worker count currently controls only deterministic, independent RGBA generation, so `1`, `2`, `4`, and `N` workers yield identical material state. Future checkerboard simulation phases require buffered boundary intents and parity proof before activation.

The active set is a tick-start snapshot. A movement records its source and destination chunk as unstable. An initially active chunk with no involvement increments `stable_tick_count`; `8` reaches `SLEEPING`. External mutations, incoming sand, and exact above-neighbor dependency wake-ups reset the counter. Distant chunks remain untouched.

Nonprocedural fixtures treat missing chunks as Empty. The finite generated world instead returns guarded `-1` for missing in-bounds chunks. Active regions enqueue the three downward halo chunks and defer movement until publication; no particle can disappear into unknown space. Horizontal/bottom overflow is Bedrock and sky overflow is Empty.
## Phase 6 circuit phase

After granular/logistics/processing work, the circuit phase evaluates only dirty or scheduled native components. It reads previous committed inputs, commits outputs together, and wakes downstream nodes for the next simulation tick. Actuator commands therefore affect the following physical tick. Stable cycles are legal; same-tick recursion is impossible.

## Phase 6.5 authoritative phase order

1. queued/commanded world mutations before the tick;
2. gravity and granular movement;
3. deterministic local magnetic lift and capture transport;
4. deterministic Screen vibration/permeability;
5. local physical heating and in-place reactions;
6. normal Conveyor transport;
7. intentional Research Bank boundary;
8. automation evaluation/actuators;
9. commit/publish and tick increment.

The shared moved flag prevents multiple full translations in one tick. Temperature, provenance, and signature move with the grain. Fixed-width field and trait math avoids platform-sensitive authoritative floating point.

## Phase 7 authoritative matter order

1. validated `WorldCommand`s are submitted before the tick;
2. granular gravity and bounded Sand/Water displacement;
3. Water gravity, diagonal transfer, and lateral equalization;
4. magnetic field, Screen interaction, and radiant heat;
5. Conveyor transport;
6. machines and Research Banks;
7. one-tick-delayed automation evaluation and actuator commit;
8. render dirtiness and telemetry publication.

Granular and Water phases share a persistent worker pool and deterministic 3x3 chunk coloring. A movement flag spans physical subsystems. The canonical coloring intentionally migrates the old serial granular hashes; the Phase-7 goldens in `tests/native_correctness.gd` are identical for workers 1, 2, 4, and 8.
# Phase 8 ordering

Each authoritative tick runs granular and open-world Water first, then local Pipe transfer, logistics/machines, physical fields, Wash Sluices, Banks, and automation. World/Pipe exchange wakes both systems. Pipe and Sluice state participate in `authoritative_physical_hash`; fixed-width integer state keeps replay independent of renderer, worker count, and platform floating-point behavior.

## Phase 8.5 experimental thermal order

Production tick order is unchanged. Only `--phase85-thermal-load` invokes the candidate after every second 60 Hz world tick: snapshot active temperatures, compute deterministic local/cross-chunk transfers in parallel, apply deltas in stable order, apply registered heat sources, then publish candidate statistics/hash. Rendering consumes the result afterward. This experimental phase is excluded from production hashes and gameplay.

## Phase 8.75 ordering

Validated player batches commit at the existing command boundary. Subsurface lanes advance once in logistics order: blocked Exit, tail-to-head packet move, physical-mouth admission. Each packet moves at most one hidden position per tick. Same-depth occupancy is validated at placement; cross-depth runs never interact. Production counters observe committed transformation/transfer events and have no simulation influence.

Permeability and physical-field kinds are compact stable records. Plain solid collision retains its direct hot path. Only implemented Magnetic and Heat Source registrations execute; Airflow, Gravity Modifier and Radiation are reserved IDs.

## Phase 9 ordering

Authoritative 60 Hz order is granular matter, unified liquid/gas matter, Pipe fluid, Subsurface logistics, physical fields, Screens, Furnace heat sources, production thermodynamics on even ticks (30 Hz), Wet Sluices, Conveyors, machines, then automation. Phase conversions occur in place; their new liquid/gas mobility begins through subsequent normal matter phases. Simulation-speed changes alter the number of authoritative ticks, never thermal wall-clock integration.

Mobile transfers preserve generic amount, metadata and proportional enthalpy. Thermal compute reads stable state, writes worker-local transfer deltas, commits deterministically, resolves latent transitions and carries integer remainder into the authoritative signed reservoir. Movement, gas and thermal activity are separate: a settled molten pool can sleep mechanically while cooling, and a sealed equalized Steam chamber can sleep as gas while a temperature frontier remains active.

## Phase 9.5 scheduling guarantees

Gas traversal uses direct chunk-local index access and the same deterministic 3×3 coloring. Pipe work reuses persistent vectors, filters by cached connection masks before map lookup, and retains the exact old wake/sleep result. Cold fixture construction is measured separately from steady production ticks. Power foundation cadence is reserved as `30 Hz` local mechanical conversion and `15 Hz` connected electrical balance, both derived from the authoritative tick; neither solver exists yet.

## Phase 11 embodied queries and streaming

Character collision is a native 18-cell query against material and structure layers. Character movement uses integer milli-cells at fixed tick; render frames never alter authoritative motion. V2 fluid activity cannot recursively generate beyond loaded interest bounds: unloaded V2 boundaries stay sealed until Character/camera/prefetch `InterestRegion`s publish the adjacent chunk. Publishing then refreshes normal granular/fluid/thermal boundaries. Visibility is owner knowledge state, not simulation state, and never participates in world hashes.
