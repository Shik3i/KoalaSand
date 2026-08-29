# Production Fluid Architecture

> **HISTORICAL ARCHITECTURE GATE:** This preserves the pre-production fluid selection. Current Water and Pipe behavior is defined by `FLUID_LOGISTICS.md`, `WET_PROCESSING.md` and `THERMODYNAMICS.md`.

## Scope and decision

Phase 6.75 selects a production direction without enabling dynamic Water. `NativeFluidPrototype` and `koalasand_fluid_benchmark` are isolated experimental surfaces. Normal world generation and gameplay still treat Water as static.

Selected direction: compact `uint8` fixed-mass liquid, chunk-local optional storage, row-span active frontiers, deterministic integer transfers, and persistent conflict-free native workers. The current prototype deliberately allocates one contiguous byte per benchmark cell; converting this to an optional `4096`-byte plane only for fluid-bearing production chunks is the first integration prerequisite.

## Research findings

- [Noita: Exploring the Tech and Design of Noita](https://www.gdcvault.com/play/1025695/Exploring-the-Tech-and-Design) describes a continuous cellular world divided into `64×64` chunks and spatially separated multithreaded work. Implication: local bounded interactions, explicit wake propagation, and conflict-free phases suit KoalaSand; global connected-ocean solves do not.
- [Godot 4.7 multithreading](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multiple_threads.html) emphasizes amortizing thread creation and avoiding excessive synchronization. Implication: the core owns a persistent pool and coarse phase barriers.
- [Godot thread-safe APIs](https://docs.godotengine.org/en/4.6/tutorials/performance/thread_safe_apis.html) restrict scene-tree work from worker threads. Implication: workers mutate only native arrays; Godot objects are updated after publication on the main thread.
- [ImageTexture.update](https://docs.godotengine.org/en/4.7/classes/class_imagetexture.html) supports replacing an existing texture image. Measurements show one large upload is substantially cheaper than hundreds of per-chunk calls.
- [Godot renderer overview](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html) and [internal rendering architecture](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html) keep Compatibility as the Windows/Web direction. [RenderingDevice](https://docs.godotengine.org/en/4.6/classes/class_renderingdevice.html) is unavailable with the Compatibility renderer, so authoritative compute shaders are rejected.
- [GDExtension](https://docs.godotengine.org/en/4.7/engine_details/engine_api/gdextension/what_is_gdextension.html) preserves the engine/native boundary used here.
- [Sandspiel](https://github.com/MaxBittker/sandspiel), [Falling Turnip](https://github.com/tranma/falling-turnip), and [WebGL Fluid Simulation](https://github.com/PavelDoGreat/WebGL-Fluid-Simulation) demonstrate data-oriented cellular rules and GPU presentation possibilities. KoalaSand keeps authoritative state CPU/integer for replay, Web fallback, and host-authoritative co-op.

No external implementation was copied.

## Regression and thermal preflight

The Phase-4 drop `158 → 153` came from deleting eleven obsolete hidden Furnace assertions and adding six physical-Furnace assertions during Phase 6.5. Removed contracts covered hidden input/fuel/output slots, recipe timers, product signatures, ash production, and a 64-grain fuel counter. Those behaviors contradict the physical Radiant Furnace. Five stronger assertions now prove unsigned thermal storage, no instant conversion/teleport, open heating geometry, retained accumulated reaction heat, and exactly one visible conserved product.

The Phase-6 drop `107 → 106` came from replacing obsolete `NO_FUEL`, hidden `RUNNING`, and hidden `OUTPUT_BLOCKED` Furnace sensor cases with physical disabled/heat/resume/active-processor coverage. One additional assertion now proves a disabled Furnace cannot react or consume a grain. Final totals: Phase 4 `158`, Phase 6 `107`.

Production temperature migrated from signed storage to absolute `uint16` without changing size:

| Property | Value |
|---|---:|
| Type / bytes | `uint16` / `2` |
| Unit / precision | `0.25 K` / one unit |
| Zero | `0 = 0 K` |
| Ambient | `1173 = 293.25 K` |
| Minimum | `0 K` |
| Maximum | `65535 = 16383.75 K` |
| Overflow | saturates at `0` or `65535` |
| Provisional Furnace reaction | `5893 = 1473.25 K` |

This covers freezing, boiling, glass, molten iron, industrial furnaces, and high-temperature future systems while retaining the `9 bytes/cell` production layout. The old Phase-0 GDScript reference uses `PackedInt32Array` centi-Celsius and is not the native production representation.

## Candidate comparison

| Property | A: discrete full cell | B: fixed mass, selected |
|---|---:|---:|
| Liquid state | material ID only | `uint8`, `0..255` |
| Added state | `0 bytes/cell` | prototype `1 byte/cell`; future optional `4096 bytes/fluid chunk` |
| 256k active median | `2.0754 ms` | `2.0675 ms` |
| 1M active median, 1 worker | `8.4311 ms` | `8.2694 ms` |
| Settled 1M | activity strategy makes both dormant | `0` active/visited; `0.1099 ms` scheduler average |
| Levels/thin streams | coarse, whole-cell only | fractional fill and conservative transfer |
| Pressure direction | weak local approximation | compact local mass gradients possible |
| Active work | same row spans | same row spans |
| Determinism | integer | integer; parity proven `[1,2,4,8]` |

Candidate A saves one byte but does not encode partial volume. Candidate B has equivalent hot-loop cost while giving visibly smoother levels, thin streams, and a path to local pressure. No hybrid was justified: sparse per-partial-cell objects or maps would add indirection and complexity without measured benefit.

Rejected: authoritative floats; object/hash entry per liquid cell; global connected-component pressure scans; global or per-cell mutexes; thread creation per tick/chunk; GPU-authoritative simulation; a separate approximate Web algorithm.

## State, activity, sleep, and wake

Material remains in the canonical `uint16` material plane. Liquid amount is `uint8`: `0` empty, `255` a full cell. Temperature moves with transferred mass using deterministic integer weighting. Future sparse chemistry may use an optional compact concentration plane or stable material variants, never an arbitrary object per cell.

Each experimental `64×64` chunk stores:

- one `uint64` active-row mask;
- `uint8 min_x[64]` and `uint8 max_x[64]`;
- fixed bookkeeping, measured as `136 bytes/chunk`.

A hostile thin-front comparison visited `4,194,304` cells with bounding rectangles versus `2,048` with row spans. Metadata was `8,192` versus `139,264` bytes. Scan time was `1.837062` versus `0.000728 ms`. Frontiers therefore cost modest metadata but scale with changed rows/spans, not reservoir volume.

Changed cells wake their local span and radius-one neighbors, including adjacent chunks. Activity lingers through both parity phases, then sleeps when no transfer occurs. Support removal, adjacent emptiness, cross-chunk inflow, gate/terrain changes, future phase changes, and future pump interaction issue local wakes. No event traverses an entire connected reservoir.

## Deterministic scheduler

The portable core owns a persistent `std::thread` pool behind `WorkerBackend { SingleThread, NativeThreads, WebThreads }`. Single-thread executes identical jobs directly. Emscripten without pthread support forces the single-thread path.

Each tick uses two disjoint pair phases:

1. vertical gravity pairs;
2. barrier and canonical activity merge;
3. horizontal equalization pairs;
4. barrier and canonical activity merge.

Pairs have radius one and never share destinations within a phase. Cross-chunk pairs are processed directly by the same partition. Compact border intents are therefore unnecessary for the current kernel; they remain the required extension if a future rule exceeds the proven conflict radius. There are no cell locks or a global simulation lock. Canonical merges make scheduling order irrelevant.

Final hashes are identical for workers `[1,2,4,8]`:

| Fixture | Hash |
|---|---|
| waterfall | `d0b5588170021527` |
| reservoir | `b83b9d9fddbb56c8` |
| dam break | `93c02f592b7e612b` |
| cross-chunk flow | `01cec239ed2da19b` |
| gate / granular interaction | `531245b08917f98c` |

WorldCommand serial/parallel replay and existing physical-processing worker parity remain covered by the regression suite; worker count changes execution only.

## Rendering decision

For highly dynamic visible liquid, selected experimental presentation is one `R8` material/fill page plus a Compatibility `CanvasItem` shader palette. It reduces 1080p upload from `8,294,400` RGBA bytes to `2,073,600` ID bytes and retains crisp cells. Interpolation may animate presentation between 60-Hz snapshots later, but cannot alter physics or blur material boundaries.

| 1080p update | Calls | Bytes | Upload avg/p99 | Frame avg/p95/p99 | FPS |
|---|---:|---:|---:|---:|---:|
| one RGBA8 page | 1 | 8,294,400 | `0.3484/0.4820 ms` | `0.9918/2.660/3.853 ms` | `1008.3` |
| one R8 ID page | 1 | 2,073,600 | `0.0915/0.1350 ms` | `0.4434/1.103/2.676 ms` | `2255.5` |
| 510 full RGBA chunks | 510 | 8,355,840 | `2.8701/3.5100 ms` | `4.4196/4.925/5.634 ms` | `226.3` |
| 128 partial RGBA chunks | 128 | 2,097,152 | `0.6839/0.9190 ms` | `1.9272/3.001/3.752 ms` | `518.9` |

Fewer page uploads win despite copying a broad region. Existing settled granular RGBA chunk rendering remains unchanged until production integration. CPU preparation measured `0.2506 ms` for full RGBA and `0.0688 ms` for R8 copy.

## Future pressure, density, thermal, and pipes

Material definitions will provide density, mobility, viscosity class, miscibility group, and surface behavior. Heavy grains may later displace lighter liquid; liquid stratification remains a local deterministic relationship. Pressure will be a bounded local mass/head relaxation or inexpensive regional hint, never a global ocean traversal or CFD solve.

Temperature is per physical cell and transfers with mass. Freeze, boil, steam, chemistry, contamination, slurry, and phase latent heat require later architecture/gameplay work. Open-world liquid stays physical. Pipes may use a specialized conserved network representation only at an explicit boundary where intake removes physical world mass and outlet restores it. No tanks, pumps, pipes, valves, sensors, steam, ice, lava, oil, acid, power, or chemistry are implemented here.

## Platform and multiplayer

The core uses C++20, fixed-width integers, contiguous arrays, and standard threading only. It is suitable in design for Windows, Linux, macOS, single-thread WASM, and threaded WASM with required browser isolation. Only Windows is built/measured. `WASM build: NOT_RUN — emcc unavailable`.

Deterministic fixed state supports a host-authoritative 60-Hz simulation, ordered WorldCommands, periodic world hashes, and optional-plane chunk resync. Phase 6.75 adds no network replication.

## Gate verdict

- Dynamic-liquid architecture: ready, conditional on production optional chunk-plane integration.
- Settled million-cell body: effectively free (`0` cells visited).
- Scaling axis: active row/frontier spans, not total liquid volume.
- One-million active: inside `16.67 ms` even serial; strong multithreaded headroom.
- Native deterministic worker model: sufficient for the selected local fluid/gas family; the legacy granular active scan remains serial and is not the model to copy.
- Compatibility renderer: comfortably above `100 FPS` in all dynamic upload experiments.
- Next phase may begin dynamic Water when explicitly authorized. It must start with the selected storage/scheduler integration. No production Water movement begins in Phase 6.75.

## Phase 7 production integration

Water is authoritative world matter, not an inventory quantity. A Water cell has `material_id = 3` and integer mass `1..255`; every non-Water cell has implicit or explicit mass `0`. Full Water is represented implicitly as mass `255` when a chunk has no liquid plane. The optional `uint8[4096]` plane is allocated only when partial mass `1..254` first appears. It is released after at least 120 quiet ticks only when the chunk is asleep and every entry again equals its implicit value (`255` for Water, `0` otherwise). Dry and full-only chunks pay no 4096-byte plane cost. Activity metadata remains 136 bytes per allocated chunk.

Transfers use integer mass only: bulk downward, deterministic downward diagonals, then lateral half-difference equalization with a two-unit deadband. The bounded pressure approximation is local capacity propagation through those moves; there is no connected-body or CFD solve. Equal choices use tick, row, coordinate, and stable hash state. Temperature travels with transferred mass and combines through wide-integer weighted averaging. There is no diffusion or phase transition.

Fluid work uses the persistent production worker pool and a deterministic 3x3 chunk-color schedule. Each color is barrier-separated, so adjacent chunks never write concurrently; direct cross-chunk transfers need no per-cell mutex or nondeterministic commit queue. Single-thread fallback executes the identical phase order. Water fronts use a 64-bit active-row mask plus per-row min/max spans. Two quiet evaluations sleep a front completely; stable million-cell reservoirs visit zero cells.

Terrain edits, gate changes, arrivals, Sand displacement, and Creative edits wake bounded neighbors. Streaming requests a generation halo; unavailable chunks block transfer until publication. Simulated changes mark chunks non-pristine. Raw Sand enters Water only when all displaced mass fits in a deterministic left/right/up neighbor; provenance and signature remain with Sand and Water is never discarded.

Rendering uses one visible-region `R8` mass page and one `ImageTexture` upload per revision. A Compatibility `CanvasItem` shader renders partial cells bottom-up and derives connected depth/surface tint without per-cell nodes. Base RGBA chunk pixels leave Water transparent.
# Phase 8 production decision

The Phase-7 open-world fixed-mass solver remains unchanged. Enclosed transport now uses sparse 16-byte local Pipe records and no global network inventory. `FLUID_LOGISTICS.md` defines capacity, potential, rates, head, temperature, sleep/wake, damage, and exact boundary conservation. Steam, phase transitions, contamination, and chemistry remain unimplemented.

## Phase 8.5 thermal preflight

Water's existing `uint16` temperature and mass-weighted capacity are compatible with the isolated conduction candidate. Empty cells do not conduct. Future Water/Ice/Steam transitions require conserved enthalpy/latent energy, density and pressure rules, and explicit world/Pipe boundary exchange; thresholds alone are insufficient. See `THERMAL_ARCHITECTURE.md`. No production fluid behavior changed.

## Phase 9 unified mobile matter

The Phase-8.5 paragraph above is historical. Phase 9 generalizes the optional Water mass plane into lazy `material_amount` for Water, Steam and molten phases. Liquid and gas jobs share active spans, fixed-capacity cells, deterministic cross-chunk work and proportional enthalpy transfer. Water falls; Steam rises; molten Glass/Iron fall and spread with material-specific mobility. Phase resolution occurs from conserved enthalpy after transfers. No phase owns a second world simulation or hidden reservoir.
