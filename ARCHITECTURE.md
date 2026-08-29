# Architecture

## Ownership

`NativeSandWorld` is the production simulation, procedural-world, provenance, structure/logistics, and render-state source. It owns `64×64` chunks, SoA material state, lazy structure occupancy, compact machine records, conservative active bounds, sleep/wake state, deterministic traversal, generation queues, RGBA caches, a persistent generation pool, and a separate persistent render-worker pool. `CellWorld`, `SimChunk`, and `GranularSimulator` remain the independent `128×128` GDScript correctness oracle. `SimulationClock` converts render deltas into fixed ticks. `DebugCellRenderer` uploads one cropped visible native material page (with a legacy chunk fallback); `StructureRenderer` batches visible structures into two MultiMeshes.

No Autoload is needed. The debug composition root wires dependencies explicitly.

## Godot process isolation

All repository commands go through `scripts/godot.ps1`. It pins `Godot_v4.7.1-stable_win64_console.exe` and redirects both Windows application-data roots to ignored `.godot-runtime/`. Godot otherwise attempts to create editor state and `user://logs` below the normal Windows profile; when that location is unavailable, 4.7.1 can crash after the directory errors. The launcher makes the required write location explicit and repository-local without touching another project's Godot installation or profile.

## Boundaries

- Production simulation truth: `native/src/`; deterministic and independent of Nodes and frames. Reference truth and fixtures: `core/` and `tests/`.
- Definitions: `data/materials/*.tres`; stable numeric IDs, loaded in sorted order, duplicate IDs/keys rejected.
- World streaming: generation workers consume prioritized coordinate requests and return immutable chunk buffers. Only the main thread publishes them into simulation/render ownership, capped at four per frame in the debug composition root.
- Rendering: native workers generate deterministic RGBA only for dirty bounds; the main thread creates/updates Godot textures from complete `64×64` chunk buffers. Eviction notifications remove retained sprites. The normal presentation remains split into background, main cells, foreground, and HUD.
- Structures: centralized native definitions provide IDs, occupied cells, footprints, ports, category, direction, and future unlock key. `uint8[4096]` occupancy exists only in structure-bearing chunks. Tile Conveyors are bytes only; larger machines add stable native records. See `FACTORY_LOGISTICS.md`.
- Research/Bank: native compact global domain state. Exact Research Bank ports transfer physical Glass/Iron/Gold into authoritative `int64` balances; canonical research IDs, prerequisites, costs, and cached effects are native and serialization-ready. See `PROGRESSION.md`.

## Granular simulation

`NativeSandWorld` implements the granular rule in optimized C++. Initial stable IDs `0..5` are Empty, Stone, Raw Sand, Water, Coal, and Bedrock; Phase 4 extends the synchronized registry through ID `15`. `GranularSimulator` retains the data-driven Phase 1 reference behavior. Water remains occupied and static; embedded Coal and Bedrock are solid.

Active chunks are snapshotted at tick start, grouped by chunk `y`, and processed from greatest `y` upward. Within each `64×64` band, all chunks process local row `63` through `0` together. Global horizontal order alternates each tick. Active rectangles constrain local rows and columns without changing global ordering. Gravity is row-safe. Phase 3 additionally uses bit `0` of the existing flags byte as a transient mark shared by gravity and Conveyor phases; no new per-cell array is required.

Each initially active chunk counts consecutive ticks with no movement involving it. The centralized threshold is `8`; reaching it changes the chunk to `SLEEPING`. Successful source or destination movement resets stability. Newly created or woken chunks wait until the next tick snapshot, preserving deterministic traversal.

`CellWorld` wakes the mutated owner. A changed cell also wakes existing chunks containing the three possible granular sources above it: `(-1,-1)`, `(0,-1)`, and `(1,-1)`. This handles erased support at boundaries without broad neighbor wake storms. Movement dirties and wakes both source and destination chunks.

In the finite procedural world, missing in-bounds chunks read as guarded `-1`, never Empty. Sand therefore cannot fall into unknown space. Active chunks request the three downward halo chunks at immediate priority; movement resumes only after main-thread publication. The Phase 1 oracle and nonprocedural native fixtures retain their earlier missing-is-Empty semantics.

## Visual foundation

`MaterialVisualResolver` derives color from stable material metadata, world seed, cell coordinate, and the four cardinal material neighbors. Fine palette variation and coarse tint are visual-only deterministic hashes. Exposed surfaces receive a restrained edge treatment; fully surrounded cells receive depth tint. Rendering never mutates simulation state and does not participate in material-state hashes.

Each render-dirty bound is rebuilt independently in native workers. Neighbor reads are non-allocating and a one-cell cross-chunk halo preserves edge shading. The full cached `64×64` RGBA buffer is then published for a main-thread `ImageTexture.update()`. Presentation invalidation does not wake simulation.

The runtime scene now requests the finite procedural world around the camera. `ShowcaseWorldBuilder` remains only as a Phase 1 fixture and is no longer called by the production composition root. `CellWorld.initialize_cell` remains the oracle's narrow bulk initialization/load path.

The scene contains one controlled warm `PointLight2D` near the sand chute as a lighting-composition proof. Full day/night, emissive gameplay, particles, postprocessing, and production art remain later work.

Phase 3 structure presentation is batched. One MultiMesh holds visible occupancy tiles and one holds larger-machine silhouettes. Shared shader time animates all belts; no `Node2D`, `Sprite2D`, `Area2D`, or physics body exists per Conveyor cell.

## Phase 4 processing ownership

Native compiled process tables, exact port watchers, and an active-machine ID set own processing. GDScript never performs grain recipes and never scans machines per frame. Machine records contain bounded input/result/fuel/Ash state. The second machine MultiMesh receives state changes only; shared shader time animates running Furnaces, Sieves, and Magnetic Separators. See `MATERIAL_PROCESSING.md`.

## Phase 5 progression ownership

`NativeSandWorld` owns the Research Bank ledger, research definitions, unlocked-ID set, schema version, placement enforcement, and technology flags. Deposit and purchase transitions are atomic within the authoritative tick/API call. Idle Banks share the Phase-4 port-watcher scheduler and disappear from active work. The Research Tree reads compact definitions/state and never determines unlock truth. Creative bypasses placement gates explicitly but does not pretend upgrade research is unlocked.

## Persistence readiness

Do not serialize the world as a Godot scene. Generated chunks begin `pristine`; simulation movement or an external edit makes every involved chunk permanently `modified`. Only pristine sleeping chunks may be evicted and regenerated from seed. Modified chunks are retained until the future save layer can persist them. A versioned save container must hold generator version/settings, seed, research state, machine records, and independently encoded/compressed modified chunk payloads. Each chunk payload must include coordinate, revision/state, materials, provenance, and future mutable fields. Stable IDs decouple saves from resource paths. Unknown IDs require explicit migration or quarantine; silent substitution is unsafe.
## Phase 6 automation boundary

Factory control is native authoritative and data-oriented: compact component/edge records, numeric ports, committed `int32` signals, local watcher indexes, and dirty/scheduled ID sets. Godot owns only batched presentation and interaction. See [AUTOMATION.md](AUTOMATION.md).

## Phase 6.5 physical/platform boundary

`koalasand_core` contains standard C++20 fixed-width traits and worker-policy primitives. `koalasand_native` is the Godot façade and current world owner. Physical processors register compact chunk/rectangle watchers; cell mutation wakes only intersecting Screen, Magnet, or Heater IDs. Expensive field/screen/heat work is absent from idle ticks.

Normal gameplay mutation flows through versioned `WorldCommand` records. Capability presets separate Creative, future Character, and Spectator authority without changing the world format. Rendering consumes snapshots/queries only; overlays request visible coarse samples on demand.

## Phase 7 unified matter boundary

`NativeSandWorld` owns granular cells, optional liquid planes, Water temperature, activity spans, collision, and phase order. `ParallelExecutor` is the persistent native pool shared by granular and fluid phases. Godot receives RGBA chunk dirtiness plus one visible `R8` Water page; shaders remain presentation-only. Player mutation stays `WorldCommand`-only, while Water transfers are deterministic derived state.
# Phase 8 fluid infrastructure

`NativeSandWorld` owns sparse `PipeSegment` records keyed only by structure-bearing cells, a sorted local active set, exact world/Pipe boundary operations, local damage/leaks, and event-driven Wash Sluices. Godot receives page or batched visible snapshots. See `FLUID_LOGISTICS.md` and `WET_PROCESSING.md` for authoritative rules.

## Phase 8.5 render and thermal boundary

Dense Pipes/Conveyors are native-packed per chunk into independently dirty topology/dynamic texture pages; sparse Conveyors and machines remain MultiMesh batches. Temperature visualization is a visible `RG8` page. `THERMAL_ARCHITECTURE.md` defines a non-production fixed-integer conduction candidate sharing the persistent worker policy. Render caches, thermal active masks, edge buffers, and worker scratch are derived state.

## Phase 8.75 factory boundary

`CommandBatch` is the shared serializable mutation envelope for drag build, Blueprint, planners, replacement and linked transport. The native batch path prevalidates and applies structure arrays in one façade call. `ConstructionHistory` stores bounded forward/inverse commands, not world snapshots.

`NativeSandWorld` owns `LinkedTransportRun`, compact packets, stable endpoints, depth occupancy, active scheduling, production rings, permeability tables and field registrations. Godot owns previews, library/UI state, batched Info badges and route rendering. Save/hash rules are in `BLUEPRINTS.md` and `SUBSURFACE_LOGISTICS.md`.

## Phase 9 thermodynamic boundary

`native_thermodynamics.cpp` owns material traits, amount-scaled heat capacity, conserved enthalpy, latent phase progress, thermal activity, deterministic worker transfer/merge, Steam gas motion and production thermal diagnostics. `native_pipe_logistics.cpp` owns local Water/Steam Pipe enthalpy, pressure, heat exchange, damage and world leaks. `native_physical_processing.cpp` contributes physical heat sources only. Automation observes integer world/Pipe state and actuates Thermal Switches through the existing deterministic signal schedule.

The per-cell base layout remains unchanged. Generic amount and phase-energy planes are allocated lazily. The shared `ParallelExecutor` runs granular, fluid/gas and thermal jobs; each phase owns explicit scratch and deterministic merge order. Godot receives render pages, compact statistics and alerts only. See `THERMODYNAMICS.md`, `PHASE_CHANGES.md`, and `STEAM_AND_GASES.md`.

## Phase 9.5 boundaries

Gas work keeps the shared parallel executor but carries direct local chunk/index references through transfer. Pipe authority remains serial because profiling showed lookup/conversion and scheduler churn—not barriers—as the bottleneck; persistent exact-order buffers and lookup fast paths meet the 50k gate without introducing conflict phases. Visible material RGBA is assembled natively into one cropped page after parallel dirty-region rebuild.

## Phase 10 power boundary

`native_power.cpp` owns physical Pipe-Steam admission/exhaust, Turbine conversion, cached mechanical shaft components, Generator load, cached Power-Pole components, priority allocation, Power Switches, Accumulators, Flywheels and electric-drive satisfaction. Automation remains its separate signal graph. Godot consumes compact machine and POWER-overlay records only. Authoritative energy is fixed-width integer state at a deterministic 30 Hz cadence. Full rules and the explicit Transformer deferral: [POWER_ARCHITECTURE.md](POWER_ARCHITECTURE.md).

## Phase 11 world/player boundary

`native_worldgen_v2.cpp` owns V2 macro fields, generator passes, deterministic corrections, FeatureTemplates, native Character collision and owner-scoped visibility/discovery. `GameSession` owns composed control/progression/visibility axes. `KoalaCharacterController` owns one fixed-tick embodied controller, never terrain physics Nodes. `InterestRegion` is the only streaming-demand description. `VisibilityRenderer` consumes owner-filtered live/stale/unknown pages; it cannot query hidden provenance. Combined player persistence is bounded by `KoalaPlayerState`, while full world save/load remains deferred.
