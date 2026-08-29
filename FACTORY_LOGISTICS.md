# Factory Logistics

## Scope

Phase 3 established free construction and physical logistics. Phase 4 activated Furnace/Sieve/Magnetic processing. Phase 5 adds the Research Bank and native unlock enforcement while preserving physical transport and free placement after unlock.

## Native representation

Physical material and built structures are independent layers. Every `64×64` material chunk owns material `uint16`, absolute quarter-kelvin temperature `uint16`, flags `uint8`, provenance `uint16`, mineral signature `uint16`, and a separate RGBA8 cache. A structure-bearing chunk additionally allocates one `uint8[4096]` occupancy array; chunks without structures allocate none. Occupancy lookup is one chunk lookup plus one cache-local byte read, never a hash lookup per material cell.

| ID | Definition | Category | Footprint | Unlock key |
|---:|---|---|---:|---|
| 1 | Conveyor Left | Logistics | `1×1` | `logistics.conveyor.basic` |
| 2 | Conveyor Right | Logistics | `1×1` | `logistics.conveyor.basic` |
| 3 | Funnel | Logistics | `7×4` | `logistics.funnel.basic` |
| 4 | Storage Bin | Storage | `8×8` | `storage.bin.basic` |
| 5 | Radiant Crude Furnace | Processing | `10×4` | `processing.crude_furnace` |
| 6 | Vibrating Screen | Processing | `10×5` | `processing.vibrating_screen` |
| 7 | Overbelt Magnetic Separator | Processing | `12×6` | `processing.overbelt_magnet` |
| 8 | Research Bank | Progression | `8×6` | `progression.research_bank` |

The centralized native registry owns footprint, occupied cells, direction support, ports, category, display name, and unlock key. Conveyor cells are only their occupancy byte. Larger structures own a monotonic native entity record. Physical processors add only field/deck/heater configuration and telemetry; they own no material inventory. Research Banks retain bounded meta-progression state. No ECS and no Godot Node exists per tile or machine cell.

| Layer | Bytes/cell |
|---|---:|
| Base simulation excluding provenance | `7` |
| Provenance | `2` |
| Complete simulation | `9` |
| RGBA cache | `4` |
| Optional structure occupancy | `1` only in structure-bearing chunks |

The Phase 2 `0.0%` figure compared two nine-byte layouts. Phase 4 again remains at nine bytes by narrowing material from four to two bytes and adding two-byte mineral signature.

## Placement and removal

Normal placement succeeds only when every occupied cell is inside generated world space, contains Empty physical material, and has no structure occupancy. Validation is atomic. Placement never erases or replaces matter. Construction has no cost.

`place_conveyor_line(from, to, direction)` validates and writes a complete horizontal range in one native call. Repeating the same belt direction is idempotent; conflicting structure or matter rejects the whole operation. `remove_structures_rect()` is the matching coarse removal operation. Removing one occupied machine cell resolves its machine record and clears its complete footprint. Matter, provenance, and neighboring structures are untouched. Changed support wakes the local dependency region.

## Authoritative tick

The fixed `60 Hz` order is:

1. queued/direct mutations occur before `step()`;
2. granular gravity runs bottom-up;
3. local magnetic fields move susceptible grains one physical cell;
4. Vibrating Screens agitate supported grains and permeability governs later downward entry;
5. local Radiant Furnaces add heat and apply in-place threshold reactions;
6. Conveyor and magnetic-capture transport run on their cached cadence;
7. Research Bank meta-progression intake and automation run;
8. next activity, dirty render state, counters, and tick publication complete.

Basic Conveyor speed begins at one cell per two authoritative ticks: `30 cells/s`. Belt Drive I changes all existing/future Basic Conveyors to one cell/tick without rebuilding. Only the physical cell immediately above a belt is eligible. Transportability is a centralized material-behavior table; every Phase 4 granular material is enabled while Stone, Bedrock, Water, and embedded solid Coal remain disabled. The move copies material, temperature, flags/state, provenance, and mineral signature, then clears the source.

Movement bit `0` in the existing `uint8` flags array enforces one meaningful move per tick. A cell falling onto a belt cannot move horizontally until the next tick. Active chunks and material-contact belt chunks clear that transient bit at tick start; no extra movement-stamp array exists.

Active belt positions are contact-driven. Material edits/moves activate only nearby support belts. Empty networks are absent from the active set. Active positions are sorted by `(y,x)` before transport; stable source order resolves competing targets. The first valid source claims the target, later sources remain blocked. Opposing belts cannot duplicate or multi-move matter. Blocked targets remain physical jams; belt ends move horizontally once and gravity handles the later fall.

## Funnel, storage, and ports

The Funnel is a stepped V of solid structure cells. Thick outer steps block the outward diagonal, guiding ordinary granular fall toward the open bottom cell. A blocked outlet causes physical backup; there is no internal buffer.

The Storage Bin is an open-top structural container with side walls and floor. Capacity is its cavity volume. Full bins back up and overflow physically. Phase 3 has no controllable outlet.

Ports are exact spatial metadata for structures that need them. Funnel and Bin remain geometric. Screen, Overbelt Magnet, and Radiant Furnace have no recipe ports: registered physical regions wake when nearby cells change, and matter remains in world cells throughout processing. Research Bank retains one intake and one physical reject port as an intentional meta-progression boundary.

## Streaming and persistence

Structure placement prepares every required generated chunk before atomic validation/write. Unknown guarded cells are never treated as Empty. Material transport retains the Phase 2 generation halo contract.

Every structure write permanently marks its chunk modified. `evict_pristine_outside()` already requires `pristine`; structure-bearing chunks therefore cannot be discarded or regenerated from seed. Until save/load exists, all modified material and structure chunks remain resident.

## Rendering and telemetry

`StructureRenderer` uses one `MultiMeshInstance2D` for visible occupancy tiles and one for visible larger-machine records. Conveyor treads and processor mechanisms use shared shader `TIME`; custom state changes are uploaded only when native visual revision changes. Visibility and construction cross the GDScript/native boundary as packed batches.

Debug telemetry exposes structure/logistics counters plus registered/active physical processors, field/deck/heater work, physical passes/moves/reactions, Research Bank activity, visible instances, and state-update time.

## Future boundary

Phase 6.5 supersedes the Phase-4 processor implementation. Exact spatial watchers activate local Screen, Magnet, and heat regions; no bounded recipe state replaces belt/pile storage. Phase 5's Research Bank remains type `8`: `8×6`, input `(3,-1)`, reject `(8,4)`, one cell/tick. Accepted Glass/Iron/Gold leave physical logistics; every other transportable material exits physically or blocks the Bank. See `MATERIAL_PROCESSING.md` and `PROGRESSION.md`.
## Phase 6 controls

Individual Conveyors cache ENABLE in the structure record high bit: `0` stops active transport but preserves support. Control Gate structure type `9` is passable while open and solid while closed; occupied close requests remain safely `CLOSE_BLOCKED`. Routing remains physical—no teleporting smart splitter.

## Phase 6.5 physical processing transport

Screens, capture belts, and radiant heaters no longer expose recipe ports. Players provide the lower fine collector, coarse continuation, upper magnetic destination, lower nonmagnetic route, and furnace-through Conveyor. Their throughput emerges from the existing physical transport and congestion rules.

## Phase 7 Water collision

Conveyors do not classify Water as transportable. Shared structure collision blocks Water at Conveyor bodies, machine footprints, Storage, Funnel walls, Furnaces, Banks, and closed Gates. Open Gates are ordinary fluid space. Screen apertures remain permeable where their cell collision permits passage; there is no wet recipe or hidden liquid intake.
# Phase 8 fluid logistics

Pipes are a second physical logistics family with local cardinal edges. Horizontal/vertical drags submit one batched `PLACE_PIPE_LINE` command. Pumps, Valves, Intakes, Outlets, Reservoir walls, and Sluices occupy native structure space. Filled Pipe removal breaches locally and preserves mass as a simulated leak; it never silently deletes contents.

## Phase 8.75 construction and subsurface coexistence

Drag building, Blueprints, fast replace and planners all produce `CommandBatch`. Surface Conveyors keep their established complete-cell transport. Subsurface mouths are ordinary structure cells; hidden lane occupancy is a separate three-depth spatial index. Entrance/Exit backpressure is local and finite. See `SUBSURFACE_LOGISTICS.md` and `BLUEPRINTS.md`.
