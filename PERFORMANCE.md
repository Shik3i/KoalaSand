# Performance Architecture

Phase 1.5 through Phase 3 performance gates. Latest measurements: 2026-08-26.

## Targets

- Authoritative simulation: fixed `60 Hz`, representative heavy Raw Sand `<= 16.67 ms/tick`.
- Presentation: `>= 100 FPS`, `<= 10 ms/frame`, VSync disabled.
- Work must scale with active regions, not allocated world size.

## Measured system and toolchain

- CPU: AMD Ryzen 7 7800X3D, 8 physical / 16 logical cores.
- GPU: NVIDIA GeForce RTX 4080 SUPER, driver `610.62`.
- RAM: `33,397,133,312` bytes available during preflight; installed-RAM WMI query was denied by the restricted environment.
- OS: Windows NT `10.0.26200.0`.
- Godot: `4.7.1.stable.official.a13da4feb`, GL Compatibility / OpenGL 3.3.
- Native compiler: MinGW-W64 GCC `16.1.0`; CMake `4.3.2`; C++20; optimized `template_release` GDExtension.
- godot-cpp: repository-local checkout pinned to commit `5ed72a0dc2517a8082598a950895c6b24e8aa282`, API `4.7`.

## Research

Primary references:

- [Godot performance guide](https://docs.godotengine.org/en/4.7/tutorials/performance/index.html) and [general optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/general_optimization.html): measure first; favor cache-local data and algorithms over micro-optimization.
- [Using multiple threads](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multiple_threads.html) and [thread-safe APIs](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html): create persistent workers before hot work; avoid frequent locks; do not touch the live SceneTree or GPU resources from arbitrary workers.
- [GDExtension](https://docs.godotengine.org/en/4.7/engine_details/engine_api/gdextension/index.html), [C++ integration](https://docs.godotengine.org/en/4.7/tutorials/scripting/cpp/index.html), and [godot-cpp](https://github.com/godotengine/godot-cpp): coarse native calls are appropriate for the cell hot path. The selected godot-cpp v10 line is pre-stable, so the exact commit and API JSON are pinned.
- [Compute shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/compute_shaders.html) and [renderer overview](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html): local compute requires a RenderingDevice renderer and immediate synchronization/readback stalls; this project intentionally uses GL Compatibility.
- [ImageTexture](https://docs.godotengine.org/en/4.7/classes/class_imagetexture.html): retain textures and call `update()` instead of recreating them.
- Petri Purho, [Exploring the Tech and Design of Noita](https://www.gdcvault.com/play/1025695/Exploring-the-Tech-and-Design/) (GDC 2019): separate simulation chunks from larger streaming regions; use small active chunks, dirty bounds, sleep, and conflict-free spatial scheduling.
- [Sandspiel source](https://github.com/MaxBittker/sandspiel): a credible Rust/Wasm/WebGL cellular-sandbox implementation; useful as evidence that simulation and presentation boundaries can remain coarse, not as copied code.

Applicable to KoalaSand: `64×64` simulation chunks, sleeping, conservative active rectangles, SoA storage, native hot loops, coarse Godot/native calls, persistent workers, and separation of authoritative material state from RGBA presentation. Not copied/adopted: Noita internals, a `512×512` streaming size, GPU-authoritative simulation, or another project's rules.

## Phase 1 profile

Probe: `tests/profile_phase1.gd`, medium state with 65,536 scanned cells unless noted.

| Cost | Measured |
|---|---:|
| Active scheduling, 2,000 iterations | 20.832 ms total; 0.010416 ms/tick |
| Category lookup traversal | 24.088 ms |
| Direct material-ID traversal | 1.358 ms |
| GDScript category overhead | 22.730 ms |
| 29,643 neighbor/world queries | 74.529 ms; 2,514 ns/query |
| Complete Phase 1 step | 230.614 ms |
| RGBA pixel generation, 131,072 pixels | 93.527 ms |
| ImageTexture upload after generation | 0.022 ms |

Dominant costs: GDScript calls and dynamic material lookup inside the cell loop; repeated dictionary/chunk lookup for neighbor queries; mutation/wake/dirty bookkeeping across GDScript method boundaries; and per-pixel GDScript color generation. Scheduling and the actual retained-texture upload were negligible.

Chunk scan probe for the same active footprint:

| Chunk | Active chunks | Cells visited | Scan-only time |
|---:|---:|---:|---:|
| `32×32` | 48 | 49,152 | 0.877 ms |
| `64×64` | 16 | 65,536 | 1.167 ms |
| `128×128` | 4 | 65,536 | 1.160 ms |

`32×32` reduces overdraw but triples scheduler/render objects relative to `64×64`. `128×128` has similar raw scan time but coarse wake, dirty, and future scheduling granularity. Production uses `64×64`; the `128×128` GDScript implementation remains the oracle.

## Selected production architecture

- `NativeSandWorld` owns `64×64` chunks and the entire Raw Sand hot path. Godot owns the scene, clock, input, UI, sprites, textures, and orchestration.
- Coarse boundary: whole steps, brush mutations, bulk fills, statistics, complete dirty-chunk payloads, and region/state queries. No per-pixel GDScript-to-C++ calls.
- Cell state remains structure-of-arrays: signed 32-bit material ID, signed 16-bit reserved temperature, 8-bit flags, and 16-bit Raw Sand provenance (`9 bytes/cell`). A separate `4 bytes/cell` RGBA cache is presentation memory. The compact temperature reservation holds simulation backing flat while provenance becomes movement-authoritative.
- Each chunk tracks one conservative simulation rectangle and one render-dirty rectangle. Movement expands the next simulation bounds with a halo. For oracle compatibility, an active rectangle is retained until the chunk reaches eight stable ticks; it is never incorrectly shrunk around temporarily supported sand. Tiny piles still visit only their bounded region, not all allocated cells.
- Render changes accumulate a one-cell visual halo. Native workers rebuild only dirty RGBA pixels. Godot receives a full `64×64` buffer for each touched chunk because `ImageTexture.update()` replaces a complete image; upload-pixel telemetry makes this residual cost explicit.
- Authoritative simulation traversal is serial and globally ordered, preserving exact Phase 1 behavior. A persistent native worker pool parallelizes independent dirty-chunk pixel generation; thread count changes cannot change material state. Workers never touch the SceneTree or GPU.
- The current measured step is small enough to run synchronously on the main thread. A future simulation-worker snapshot/double-buffer boundary is documented but deliberately deferred until measured simulation cost threatens the frame budget; adding it now would add state publication and input-order complexity without addressing a measured bottleneck.
- Future simulation parallelism: bottom-up chunk bands divided into conflict-free checkerboard phases, with deterministic phase/barrier order and buffered cross-chunk intents. It must pass the existing 1/2/4/N-worker state comparison before activation. No global hot-loop mutex and no thread creation per tick.

## GPU investigation

No compute-simulation prototype was run. It would not be a valid production-path comparison: GL Compatibility does not expose Godot's local RenderingDevice compute path. Moving to Forward+/Mobile only for this benchmark would change the renderer/platform contract. CPU-visible sensors, machines, saves, debugging, exact replay, and per-tick readback also favor a CPU-authoritative grid. Compute simulation is deferred, not rejected forever. GPU-derived palette/edge shading remains a future renderer option if native RGBA generation becomes measurable; it is currently `0.361 ms` average in the 1080p runtime.

## Performance matrix

Headless simulation runs use the optimized native DLL and 8 workers. Timing thresholds are reporting-only; deterministic work invariants catch catastrophic regressions.

| Scenario | Allocated | Active chunks / region cells | Avg / worst tick | Capacity | Avg / max visited | Moved | Render extraction | Dirty / uploaded pixels |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A sparse | 1,048,576 | 2 / 2,484 | 0.210 / 0.508 ms | 4,763.8 Hz | 1,660 / 2,457 | 46,500 | 0.083 ms | 2,484 / 8,192 |
| B medium, prior workload | 262,144 | 16 / 42,987 | 2.393 / 2.860 ms | 417.9 Hz | 31,856 / 42,504 | 444,645 | 0.226 ms | 42,504 / 65,536 |
| C 1M active pathological | 1,253,376 | 234 / 833,718 | 165.633 / 172.038 ms | 6.0 Hz | 979,601 / 1,057,864 | 6,298,770 | not run | not run |
| D 4M persistent | 4,194,304 | 8 / 9,656 | 1.412 / 1.829 ms | 708.1 Hz | 10,108 / 13,750 | 310,748 | not run | not run |

Phase 2 regression rerun after provenance integration:

| Scenario | Avg / worst tick | Change from Phase 1.5 final |
|---|---:|---:|
| A sparse | `0.182 / 0.212 ms` | improved |
| B medium | `2.347 / 2.781 ms` | `-1.9%` average |
| C 1M pathological | `161.945 / 172.113 ms` | improved average |
| D 4M persistent | `1.364 / 1.789 ms` | improved average |

The B/D figures are medians from three isolated final repeats; B averages were `2.337`, `2.366`, and `2.347 ms`. A chained full-gate run observed a Windows scheduling outlier (`26.932 ms` worst, `3.799 ms` average), while all work invariants still passed. Simulation backing stayed `9 bytes/cell`, but the former `0.0%` wording described total-layout change, not provenance cost: provenance is an eager `uint16` (`2 bytes/cell`) offset by narrowing reserved temperature from `int32` to a 16-bit field (`-2 bytes/cell`), now absolute quarter-kelvin `uint16`. Base simulation excluding provenance is now `7 bytes/cell`; RGBA remains `4 bytes/cell`.

## Phase 2 generation and streaming matrix

Optimized native DLL, two persistent generation workers:

| Scenario | Result |
|---|---:|
| One surface chunk | `0.579 ms` wall; `0.429 ms` worker; `0.074 ms` publish |
| 100 mixed surface/deep chunks | `38.287 ms` wall; `0.694 ms` average worker; `0.860 ms` worst worker |
| 10,000-cell camera pan | `79` hops; `463.034 ms` total; `28.160 ms` worst synchronous stress hop |
| Pan residency | `117` peak/final chunks; `1,386` pristine chunks evicted |
| 100 chunks at `y = 3072` | `39.558 ms`; hash `ab78e4af` |
| 64-chunk pristine eviction | `0.377 ms` |
| 64-chunk deterministic regeneration | `25.428 ms`; identical hash |

The pan benchmark deliberately flushes each hop, producing a conservative synchronous stress number. Runtime streaming does not flush: workers generate asynchronously and the main thread publishes at most four chunks per frame.

Before/after for the exact medium fixture: `231.882 ms` average and `259.986 ms` worst in GDScript versus `2.393 ms` average and `2.860 ms` worst native: `96.9×` average speedup. Sparse improved from `22.545 ms` to `0.210 ms`; its steady dirty render extraction improved from `9.249 ms` to `0.083 ms`.

Phase 2 non-headless 1920×1080 procedural-world run, VSync off, 300 measured ticks after a 30-frame warm-up, 15 render workers:

```text
fps=144.9
main_frame_ms=6.889
sim_avg_ms=0.029
sim_worst_ms=0.049
render_update_avg_ms=0.079
active_chunks=0
active_rectangles=0
active_region_cells=0
cells_visited=0
cells_moved=0
```

The fixed authoritative clock remains `60 Hz`; reported simulation Hz is measured throughput capacity, not a changed gameplay tick rate. Scenario C is intentionally pathological and honestly fails the 16.67 ms budget. The representative medium and rendered workloads pass with substantial headroom.

## Phase 3 logistics matrix

Optimized native DLL, serial authoritative simulation. Optional occupancy is one byte per cell only in structure-bearing chunks.

| Scenario | Structures / material | Avg / worst simulation | Avg logistics | Work |
|---|---:|---:|---:|---|
| A — idle infrastructure | `50,000` belts / `0` moving | `0.003 / 0.015 ms` | `0.000 ms` | `0` considered; `50,000` skipped/tick |
| B — moderate factory | `10,000` belts / `~20,000` sand | `3.207 / 6.739 ms` | `1.720 ms` | peak `10,000` considered; `144,155` moves / 60 ticks |
| C — dense active stress | `50,000` belts / `~50,000` sand | `15.479 / 27.532 ms` | `9.969 ms` | peak `49,925` considered; `373,225` moves / 30 ticks |
| E — long transport | `2,111` belts / one profiled cell | `10.088 ms` wall / `4,010` ticks | included | `2,005` cells; count `1`; hash `6b8891d8` |

Scenario C is a synthetic ceiling: its average remains within `16.67 ms`, while its worst tick does not. It identifies the serial active-logistics limit without introducing premature simulation threading. Scenario A proves that 50,000 empty belts do not keep chunks active and are not scanned. Three isolated final Phase 1.5 regressions produced medium averages `2.627`, `2.457`, and `2.383 ms` (median `2.457`) and 4M-persistent averages `1.487`, `1.453`, and `1.543 ms` (median `1.487`); all work invariants passed.

Structure memory from these fixtures:

```text
50,000 belts
64 structure-bearing chunks
262,144 bytes occupancy backing (0.250 MiB)
1 byte/cell only in those chunks
```

Final real OpenGL 1920×1080 runs, VSync disabled:

| Scene | FPS | Avg / p95 / p99 / worst frame | Avg / worst simulation | Avg logistics | Visible structure tiles |
|---|---:|---:|---:|---:|---:|
| Phase 2-style generated world, no structures | `704.9` | `1.419 / 1.515 / 2.083 / 3.389 ms` | `0.041 / 0.059 ms` | `0.000 ms` | `0` |
| Dense Phase 3 factory | `481.8` | `2.077 / 2.381 / 2.381 / 6.642 ms` | `3.515 / 6.252 ms` | `1.597 ms` | `10,541` |

The dense visible run used `10,400` Conveyor cells, `39` sand rows (three over each of 13 lines), six Funnels, two Storage Bins, and one inert Furnace shell. It averaged `4,972` belts considered/tick, peaked at `10,280`, and completed `554,700` belt moves during the measured window. Material render extraction averaged `0.699 ms`; structure rebuild was `0.000 ms` during steady state because the MultiMeshes were unchanged. A 120-frame setup warm-up excludes initialization/streaming from steady-state percentiles; setup remains separately visible in capture and generation telemetry.

## Regression commands

```powershell
.\scripts\build_native.ps1
.\scripts\godot.ps1 --headless --path . --script res://tests/test_runner.gd
.\scripts\godot.ps1 --headless --path . --script res://tests/native_correctness.gd
.\scripts\godot.ps1 --headless --path . --script res://tests/benchmark_phase15.gd
.\scripts\godot.ps1 --headless --path . --script res://tests/phase2_correctness.gd
.\scripts\godot.ps1 --headless --path . --script res://tests/benchmark_phase2.gd
.\scripts\godot.ps1 --headless --path . --script res://tests/phase3_correctness.gd
.\scripts\godot.ps1 --headless --path . --script res://tests/benchmark_phase3.gd
.\scripts\godot.ps1 --path . --user-args --benchmark-runtime-ticks=180 --empty-world
.\scripts\godot.ps1 --path . --user-args --benchmark-runtime-ticks=240 --dense-factory
```

Do not put strict microsecond limits in normal correctness tests. Preserve these work invariants: sleeping worlds visit zero cells; sparse activity visits a small fraction of allocation; 4M persistence scales with active regions; worker count never changes final state.

## Phase 4 processing matrix

Release GDExtension, Godot `4.7.1.stable.official.a13da4feb`:

| Scenario | Result |
|---|---|
| `10,000` idle Sieves | `0` active/visited; scheduler `0.000 ms`; full `step()` `0.008642 ms` average |
| Representative processing | `10,800` belts, `300` active/visited processors; `2.138 / 4.390 ms` average/worst total tick; `0.033 / 0.126 ms` machine phase |
| Processing stress | `1,500` active/visited blocked processors; `0.338 / 0.745 ms` average/worst total tick; production path |

The representative case intentionally ends in physical output blockage, proving that bounded completed results keep only those machines active while the `10,000` idle case proves total infrastructure is not scanned.

Phase 1.5 regression after `uint16` material migration plus `uint16` signature:

- medium averages: `2.474`, `2.495`, `2.478 ms`; median `2.478 ms`;
- 4M persistent averages: `1.481`, `1.513`, `1.465 ms`; median `1.481 ms`;
- simulation storage: unchanged `9 bytes/cell` (`36.00 MiB` for 4M cells).

Current Phase 3 logistics regression: moderate `2.932 / 5.296 ms` average/worst with `1.541 ms` logistics; dense 50k-active `14.071 / 27.884 ms` with `9.089 ms` logistics. Phase 2 generation: `37.479 ms` for 100 chunks; 10k-cell pan peak `117` chunks; deterministic regeneration `25.139 ms`.

Real OpenGL 1920x1080 dense Phase 4 factory, VSync disabled, 300 measured ticks after 120-frame warm-up:

```text
fps=442.1
frame_avg/p95/p99/worst_ms=2.262/2.778/3.834/9.686
simulation_avg/worst_ms=3.897/6.848
logistics_avg_ms=1.701
machine_avg_ms=0.053
belts=10,000+
visible_processors=300
active_processors=300
machine_instances=300
visible_structure_tiles=17,800
material_render_avg_ms=0.853
steady_structure_instance_update_ms=0.000
```

The representative authoritative tick remains comfortably below `16.67 ms`; the rendered scene exceeds the `100 FPS` gate by `4.4x`. Machine animation is shared-shader time plus state-change custom data, not per-machine GDScript animation.

## Phase 5 progression matrix

Release GDExtension, Godot `4.7.1.stable.official.a13da4feb`:

| Scenario | Result |
|---|---|
| `10,000` idle Research Banks | `0` active/visited; Bank `0.000 ms`; complete tick `0.028 ms` average |
| `400` active mixed-stream Banks | `54,000` accepted, `17,900` physically rejected over 180 ticks; Bank `0.005 ms`; complete fixture tick `0.686 ms` |
| Dense 1080p progression, tree closed | `318.0 FPS`; frame `3.144/4.167/7.823/43.532 ms` avg/p95/p99/worst; simulation `4.332 ms`; logistics `1.790 ms`; machine `0.156 ms`; Bank `0.007 ms` |
| Dense 1080p progression, tree open | `289.6 FPS`; frame `3.450/3.704/3.749/16.602 ms`; simulation `4.206 ms`; logistics `1.735 ms`; machine `0.147 ms`; Bank `0.005 ms`; UI update `0.0044 ms` |

The dense runtime contains `10,000+` belt cells, `300` processing machines, `200` Research Banks with continuously replenished mixed feed, `22,600` visible structure tiles, active material banking, generated world, and the normal reserve HUD. Closed/open runs complete `685,950` belt moves. Both exceed the `100 FPS` gate with substantial headroom.

Current regression snapshot after Phase 5: Phase-1.5 medium `2.457 ms`, four-million persistent `1.479 ms`; Phase-3 moderate `3.023 ms` and dense `14.399 ms`; Phase-4 representative `2.209 ms` with `0.034 ms` machine work. No idle infrastructure scan was introduced.

```powershell
.\scripts\godot.ps1 --headless --path . --script res://tests/phase5_correctness.gd
.\scripts\godot.ps1 --headless --path . --script res://tests/benchmark_phase5.gd
.\scripts\godot.ps1 --path . --user-args --dense-progression --benchmark-runtime-ticks=300 --capture-1080p
.\scripts\godot.ps1 --path . --user-args --dense-progression --phase5-view=tree --benchmark-runtime-ticks=300 --capture-1080p
```
## Phase 6 automation gate

Godot `4.7.1`, Windows, Ryzen 7 7800X3D, RTX 4080 SUPER, Compatibility renderer.

- Idle 50k components / 50k wires: `0.000380 ms/tick` circuit average; zero visited nodes after settle.
- Signal storm: 10k sensors `2.979 ms`, 10k logic `7.459 ms`, 30k actuators `7.503 ms`.
- Sensor-heavy factory: 2,000 sensors add `0.103 ms/tick`.
- Wire render 50k: OFF `0.270 ms/frame` (`3707.2 FPS`), ON `0.374 ms/frame` (`2672.5 FPS`), topology build `127.850 ms`, steady rebuilds `0`.
- Representative 1080p automation factory: `473.1 FPS`, frame average `2.116 ms`, p95 `2.778 ms`, p99 `4.233 ms`, worst `16.632 ms`; simulation average `2.130 ms`, automation average `0.0167 ms`.
- Regression: Phase 1.5 medium `2.539 ms`, 4M persistent `1.485 ms`; Phase 3 dense 50k active `15.198 ms`; Phase 4 representative `2.262 ms`; Phase 5 active Bank `0.696 ms`.

```powershell
.\scripts\godot.ps1 --headless --path . --script res://tests/phase6_correctness.gd
.\scripts\godot.ps1 --headless --path . --script res://tests/benchmark_phase6.gd
.\scripts\godot.ps1 --headless --path . --script res://tests/benchmark_phase6_research.gd
.\scripts\godot.ps1 --path . --script res://tests/benchmark_phase6_wire_render.gd
.\scripts\godot.ps1 --path . --user-args --dense-automation --benchmark-runtime-ticks=300 --capture-1080p
```

## Phase 6.5 physicality and UI gate

Godot `4.7.1`, Windows, Ryzen 7 7800X3D, RTX 4080 SUPER, Compatibility renderer, Release GDExtension:

| Scenario | Measured result |
|---|---|
| `10,000` idle Overbelt Magnets | `0` active, `0` cells tested, `0.000000 ms` magnetic work, `0.026177 ms/tick` complete fixture |
| `300` active magnets | `11` registered region chunks, `10,800` cells tested, `7,200` physical moves over 12 ticks, `1.3964 ms/tick` magnetic phase |
| `1,200` active magnets | `44` registered region chunks, `43,200` cells tested, `28,800` moves over 12 ticks, `9.9063 ms/tick` magnetic phase |
| `500` active Vibrating Screens | `12,000` grain tests and vibration evaluations, `1,000` physical mesh passes, `0.5433 ms/tick` screen phase |
| Separation quality, `100,000` stable signatures | `32,344` fine, `67,656` coarse, `3,404` magnetic, `96,596` nonmagnetic, `672` gold retained, `0` lost |

Dense physical 1920×1080 runtime, 300 measured ticks:

```text
fps=740.0
frame_avg/p95/p99/worst_ms=1.351/1.389/1.389/2.609
simulation_avg/worst_ms=1.121/1.529
material_render_avg_ms=0.395
structure_render_update_ms=0.000
ui_avg_ms=0.0067
magnetic_ms=0.5090
screen_ms=0.1700
cells_visited=41,717
cells_moved=201
```

UI/overlay variants use the same dense physical scene:

| View | FPS | frame avg | UI update | Overlay update/draw |
|---|---:|---:|---:|---:|
| Minimal HUD + Quickbar | `629.3` | `1.586 ms` | `0.0079 ms` | `0.0000 / 0.0000 ms` |
| Build Catalog | `564.8` | `1.768 ms` | `0.0077 ms` | `0.0000 / 0.0010 ms` |
| Research | `565.4` | `1.771 ms` | `0.0122 ms` | `0.0000 / 0.0000 ms` |
| Wiring Mode | `649.3` | `1.542 ms` | `0.0080 ms` | `0.0000 / 0.0010 ms` |
| Magnetic Field | `719.4` | `1.394 ms` | `0.0068 ms` | `0.0000 / 0.2040 ms` |

The field overlay is generated only when enabled and visible. It iterates spatially registered magnet rectangles, combines samples deterministically, and caches the result until visible chunks or structure revision change. The initial implementation scanned the full visible cell area and measured only `24.2 FPS`; that failed gate was removed before completion.

```powershell
.\scripts\godot.ps1 --headless --path . --script res://tests/benchmark_phase65.gd
.\scripts\godot.ps1 --path . --user-args --dense-physical --benchmark-runtime-ticks=300 --capture-1080p
.\scripts\godot.ps1 --path . --user-args --dense-physical --phase65-view=magnetic-overlay --benchmark-runtime-ticks=120 --capture-1080p
```

## Phase 6.75 pre-fluid architecture gate

Environment: Windows 11 Pro `10.0.26200`, AMD Ryzen 7 7800X3D (`8` cores / `16` threads), `31.1 GiB` RAM, NVIDIA GeForce RTX 4080 SUPER driver `610.62`, Godot `4.7.1.stable.official.a13da4feb`, Compatibility/OpenGL 3.3, CMake `4.3.2`, MinGW g++ `16.1.0`, Release `-O3 -DNDEBUG`. WMI's reported GPU byte count is omitted because it is truncated. Benchmarks use warm-up and sustained samples.

### Production granular baseline

| Scenario | Allocated cells | Average / worst | Work |
|---|---:|---:|---|
| sparse 1M | 1,048,576 | `0.307 / 0.603 ms` | `1,660` visited average |
| medium 256k | 262,144 | `3.867 / 4.554 ms` | `31,856` visited average |
| pathological 1M active | 1,048,576 | `250.766 / 262.512 ms` | `979,601` visited average, `1,057,864` maximum, `6,298,770` moves |
| 4M persistent | 4,194,304 | `2.150 / 3.179 ms` | `10,108` visited average |

The current production million-active granular path is serial and worse than the old `165.633 ms` snapshot. It is not suitable as the future fluid loop. Sleeping-world scaling remains strong.

### Candidate kernels

| Candidate / active set | Workers | Avg | Median | p95 | p99 | Worst | State / activity bytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| discrete full-cell, 256k | 1 | `2.1476` | `2.0754` | `2.3377` | `2.8753` | `7.3044` | `0 / 8,704` |
| fixed `uint8`, 256k | 1 | `2.1131` | `2.0675` | `2.4921` | `2.7047` | `2.7689` | `262,144 / 8,704` |
| discrete full-cell, 1M | 1 | `8.5298` | `8.4311` | `9.5675` | `9.9503` | `10.9586` | `0 / 34,816` |
| fixed `uint8`, 1M | 1 | `8.3883` | `8.2694` | `9.4411` | `9.9280` | `10.0461` | `1,048,576 / 34,816` |

The one-million-active fixture re-seeds its alternating dynamic pattern outside the timed region each tick, so essentially all cells genuinely evaluate; it measures kernel throughput rather than natural settling.

### Fixed-mass worker scaling, 1M active

| Workers | Avg | Median | p95 | p99 | Worst |
|---:|---:|---:|---:|---:|---:|
| 1 | `8.3883` | `8.2694` | `9.4411` | `9.9280` | `10.0461` |
| 2 | `5.9156` | `5.9089` | `7.0330` | `7.4943` | `11.9732` |
| 4 | `3.1706` | `3.2323` | `3.3828` | `3.4139` | `3.4356` |
| 8 | `1.8664` | `1.8735` | `1.9971` | `2.1158` | `2.2573` |

Each run visits `2,125,824` cells and performs `261,390` transfers per tick average: `260,865` downward, `525` lateral, `3,832` border pairs. All five fixtures produce identical hashes for workers `[1,2,4,8]`.

### Scenario matrix, selected fixed-mass kernel

| Scenario | Allocated | Active avg / peak | Visited avg | Transfers avg | Avg / median / p95 / p99 / worst ms | Workers |
|---|---:|---:|---:|---:|---:|---:|
| small waterfall | 262,144 | `10,174 / 16,305` | `21,506` | `5,372` | `0.0963 / 0.0933 / 0.1273 / 0.1878 / 0.4842` | 4 |
| 1M reservoir settling | 1,052,676 | `701,784 / 1,052,676` | `1,424,088` | `0` | `1.1644 / 1.6689 / — / — / 1.6849` | 4 |
| 1M reservoir settled | 1,052,676 | `0 / 0` | `0` | `0` | `0.1099 / 0.1132 / 0.1561 / 0.2213 / 0.5233` | 4 |
| dam break, 1,200 ticks | 524,288 | `7,629 / 11,707` | `16,211` | `4,694` | `0.0954 / 0.0911 / 0.1241 / 0.1733 / 0.4773` | 4 |
| 4M persistent mixed reservoirs/fronts | 4,194,304 | `561,936 / 714,164` | `1,149,319` | `310,966` | `2.7319 / 3.1895 / 3.5272 / 3.6823 / 3.7184` | 4 |

The reservoir becomes dormant after tick `2`. The dam-break fixture is still active after tick `1200` (`settled_after_ticks=-1`), reported rather than inferred. Mixed microchecks pass: `sand_displaces_water`, temperature conservation, local gate wake/flow.

### Representative existing factory plus experimental fluid

Two reservoirs, continuous waterfalls, gate interaction, and `300` continuously fed physical processors:

```text
allocated_fluid_cells=1048576
active_latest=85120
visited_avg=185062
transfers_avg=59800
simulation_avg/p95/p99/worst_ms=4.3989/6.2920/6.8360/6.9570
fluid_avg/p95_ms=0.4344/0.5170
workers=8
factory_structures=300
fluid_state_bytes=1048576
activity_bytes=34816
hash=84b384c4da45dc5a
```

Final post-build confirmation: `4.4198/6.0700/6.5960/10.4990 ms` simulation avg/p95/p99/worst, `0.4791/0.5600 ms` fluid avg/p95, identical hash `84b384c4da45dc5a`. The earlier sustained run above and this confirmation both remain below `16.67 ms`.

### Dynamic 1080p render/update experiment

| Path | Calls | Bytes | Upload avg / p99 | Frame avg / p95 / p99 / worst | FPS |
|---|---:|---:|---:|---:|---:|
| RGBA8 page | 1 | 8,294,400 | `0.3484 / 0.4820 ms` | `0.9918 / 2.660 / 3.853 / 4.142 ms` | `1008.3` |
| R8 ID page | 1 | 2,073,600 | `0.0915 / 0.1350 ms` | `0.4434 / 1.103 / 2.676 / 2.914 ms` | `2255.5` |
| 510 RGBA chunks | 510 | 8,355,840 | `2.8701 / 3.5100 ms` | `4.4196 / 4.925 / 5.634 / 9.250 ms` | `226.3` |
| 128 partial RGBA chunks | 128 | 2,097,152 | `0.6839 / 0.9190 ms` | `1.9272 / 3.001 / 3.752 / 4.571 ms` | `518.9` |

Selected future dynamic-liquid path: R8 material/fill page plus Compatibility CanvasItem shader. Existing granular RGBA chunks remain unchanged in this phase.

### Current-system regression snapshot

- Phase 1.5: medium `3.867 ms`; 4M persistent `2.150 ms`; pathological active 1M `250.766 ms`.
- Phase 3: five dense 50k-active averages are `16.805`, `16.326`, `16.862`, `16.184`, and `16.101 ms`; median `16.326 ms`. Four pass `16.67 ms`; one fails at `16.862 ms`. Identical hash `467213fe`; serial logistics remains a measured tail-risk ceiling.
- Phase 4: physical processing correctness `158`; no hidden Furnace inventory or teleport.
- Phase 5: 10k idle Banks `0.000 ms` Bank work / `0.0292 ms` wall; 400 active `0.007 ms` Bank / `0.742 ms` wall.
- Phase 6: 50k idle circuit `0.000905 ms`; 10k sensor/logic/30k actuator storm `3.469/8.123/7.864 ms`; 2k sensor overhead `0.110 ms`.
- Phase 6.5: 10k idle magnets `0.0279 ms` wall; 300 magnets `1.4652 ms`; 1,200 magnets `10.137 ms`; 500 screens `0.5367 ms`; 100k separation loses `0` grains.
- Dense physical 1080p: `687.0 FPS`; frame `1.455/1.515/1.667/4.351 ms`; simulation `1.233/1.559 ms`; material render `0.500 ms`; `14,804` structure tiles and `436` machine instances.

Portability: native core `PASS`; `WASM build: NOT_RUN — emcc unavailable`.

Final native-kernel confirmation remained within budget: one-million-active fixed mass measured `8.5818/9.1389/9.3206/9.3456 ms` avg/p95/p99/worst with one worker and `1.8836/2.0571/2.5558/2.7702 ms` with eight. The 1M settled reservoir again visited `0` cells and averaged `0.1075 ms`. Persistent 4M measured `2.8562/4.0051/4.8540/5.8459 ms`. All hashes remained identical.

## Phase 7 production Dynamic Water gate

Windows, Godot `4.7.1.stable.official.a13da4feb`, native Release, authoritative production paths. Times are milliseconds/tick.

### 1M active production scaling

| Matter | Workers | Avg | p95 | p99/worst | Barrier avg | Visited peak | Transfers/moves | Hash |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| Sand | 1 | 58.4062 | 61.5970 | 63.1960 | 0.0000 | 4,233,216 | 20,971,520 moves | `223f1510` |
| Sand | 2 | 29.1981 | 30.9700 | 31.3440 | 0.1419 | 4,233,216 | 20,971,520 moves | `223f1510` |
| Sand | 4 | 14.9695 | 15.4640 | 16.0910 | 0.2157 | 4,233,216 | 20,971,520 moves | `223f1510` |
| Sand | 8 | **8.2563** | 8.6140 | 9.0720 | 0.2454 | 4,233,216 | 20,971,520 moves | `223f1510` |
| Water | 1 | 99.5456 | 101.1630 | 101.2460 | 0.0000 | 4,233,216 | 20,971,520 transfers | `70b40853` |
| Water | 2 | 50.5010 | 51.6520 | 51.9560 | 0.2053 | 4,233,216 | 20,971,520 transfers | `70b40853` |
| Water | 4 | 25.5773 | 26.2280 | 26.4660 | 0.3146 | 4,233,216 | 20,971,520 transfers | `70b40853` |
| Water | 8 | **13.5275** | 14.1700 | 14.6260 | 0.3375 | 4,233,216 | 20,971,520 transfers | `70b40853` |

The old `250.766 ms/tick` 1M granular bottleneck is eliminated. The genuine moving fixtures contain at least 1,048,576 active cells and meet `16.67 ms` at 8 workers.

### Production scenario matrix, 8 workers

| Scenario | Avg | p95 | p99 | Worst | Granular avg | Fluid avg | Active peak | Visited peak | Work total |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 256k active Water | 3.7575 | 3.8900 | 3.9510 | 3.9510 | 0.0010 | 3.6670 | 267,776 | 1,078,272 | 7,864,320 transfers / 2,005,401,600 mass units |
| 1M active Water | 13.5275 | 14.1700 | 14.6260 | 14.6260 | 0.0010 | 12.9998 | 1,071,104 | 4,233,216 | 20,971,520 transfers / 5,347,737,600 mass units |
| 1M settled Water | 0.0409 | 0.0630 | 0.0660 | 0.0710 | 0.0010 | 0.0134 | **0** | **0** | 0 |
| Dam break | 1.7977 | 2.2850 | 2.3240 | 2.4000 | 0.0010 | 1.7796 | 4,929 | 8,337 | 391,871 transfers / 56,297,779 mass units |
| 4M persistent | 0.1705 | 0.2130 | 0.3190 | 0.4350 | 0.0010 | 0.0496 | 0 | 0 | 0 |
| 500k Sand + 500k Water | 10.8411 | 11.1700 | 12.1410 | 12.1410 | 3.9493 | 6.6424 | 535,552 | 2,158,592 Sand / 2,156,544 Water | 15,728,640 moves + 15,728,640 transfers / 4,010,803,200 mass units |

Long-distance streaming: 4,080 mass crossed 11.3 vertical chunks in 720 ticks with 177 border crossings, exact conservation, 36 peak / 34 final resident chunks, and `0.0068 / 0.0110 / 0.0150 / 0.0270 ms` simulation avg/p95/p99/worst.

### R8 production rendering

| Scene | Page | R8 bytes | CPU avg | p95 | p99/worst |
|---|---:|---:|---:|---:|---:|
| Small waterfall | 256x512 | 131,072 | 0.3862 | 0.4370 | 0.4560 |
| Full-screen moving Water | 1024x512 | 524,288 | 1.5488 | 1.6240 | 1.6620 |
| Large settled lake | 1024x512 | 524,288 | 1.5561 | 1.5990 | 1.6520 |
| Factory + Water | 768x384 | 294,912 | 0.8692 | 0.9000 | 1.0220 |

One visible page replaces hundreds of chunk uploads. Representative changed frames averaged `1.494 ms` Water-page CPU/upload preparation for `516,096` bytes.

### Representative 1920x1080 game

8 workers; procedural terrain; 14,805 structure tiles; 436 machine instances; several thousand Conveyor cells; Screen, Magnets, Furnaces, Banks, sensors, closed automated reservoir Gate, sleeping reservoir, and active waterfall:

```text
FPS                         320.9
frame avg / p95 / p99       3.113 / 3.333 / 3.704 ms
frame worst                 8.359 ms
simulation avg / p95 / p99  4.344 / 4.968 / 5.069 ms
simulation worst            5.778 ms
fluid latest / barrier      3.011 / 0.068 ms
active / visited Water      5,074 / 9,096
transfers latest            1,776
worker utilization          100.0%
material render avg         2.787 ms
```

The 8-worker default leaves render/main-thread headroom. Automatically consuming all 15 available threads caused catch-up starvation and was rejected.

### Memory

Base state remains 9 bytes/cell. Optional partial-liquid planes cost 4,096 bytes per affected chunk; activity costs 136 bytes per allocated chunk. The representative run measured 15 planes / 61,440 bytes, 16,456 activity bytes, and a 516,096-byte visible `R8` page. `ParallelExecutor` owns eight persistent worker threads plus job/barrier metadata; no scheduler state is stored per cell.

## Phase 8 Pipe and wet-processing gate

Final 2026-08-27 Release measurements, Godot `4.7.1`, Windows, 8 workers unless stated:

| Scenario | Avg / p95 / p99 / worst | Pipe avg/p95 | Active / peak visited | Other |
|---|---|---|---:|---|
| 100k empty Pipes | `0.0110 / 0.0160 / 0.0200 / 0.0880 ms` | `0 / 0 ms` | `0 / 0` | 1,600,000 record bytes; scheduler 0 |
| 100k stable filled | `0.0098 / 0.0120 / 0.0140 / 0.0170 ms` | `0 / 0 ms` | `0 / 0` | mass 3,276,800,000; hash `3fbacd6d` |
| 50k active stress | `12.3864 / 21.5190 / 22.0190 / 22.0190 ms` | `10.7506 / 18.6300 ms` | `6,700 / 50,000` | 615,250 transfers; 7,500 Pump; 5,300 Valve work |
| 1,001-cell uphill | `0.2100 ms` latest Pipe | — | — | 8 Pumps; top mass 1,958; exact mass 8,454,015; hash `ad560338` |
| 256 active Sluices | `0.6322 ms` wet avg | — | 117,953 grain visits | 26,305 moves; 245 captures; 1,024 grains and 655,360 Water exact |
| 5k-tick recycle loop | `0.00672 ms` Pipe avg | — | — | mass 22,185 exact; Intake 36,112; Outlet 24,244; hash `5d5b15da` |

The active-50k pathological tail exceeds `16.67 ms` at p95/p99 while its `12.3864 ms` average passes. This is a deliberate all-active stress ceiling, not the representative factory. Stable 100k networks visit zero segments.

Historical production regression: active 1M Sand `8.4543 ms`; active 1M Water `13.8651 ms`; settled 1M Water `0.0502 ms` with zero visits; mixed 500k/500k `11.2569 ms`; dense 50k Conveyor stress `15.068 ms` average / `25.886 ms` worst.

Representative Phase-8 factory: 4,428 structure tiles, 33 machine instances, 336 Pipe segments, physical reservoirs, Water loop, Sluice, 3 Pumps, Valve, automation and dry-processing rows:

```text
FPS                              340.0
frame avg/p95/p99/worst          2.945/3.030/3.910/5.556 ms
simulation avg/p95/p99/worst     0.859/0.988/1.024/1.116 ms
granular/open Water/Pipe latest  0.064/0.401/0.002 ms
wet/automation/logistics         0.004/0.001/0.034 ms
material render                  3.530 ms average changed-frame update
```

At the Phase-8 close, the separate 20k-visible-Pipe GL Compatibility stress reached `92.5 FPS`, frame `10.939/45.589/63.904/66.195 ms`, with zero simulation work and a static single Pipe `MultiMesh`. That below-100 result became the Phase-8.5 blocker and is retained as the pre-gate baseline.

Representative memory: 675,840 cells at 9 bytes = 6,082,560 bytes; four Water planes = 16,384 bytes; Water activity = 22,440 bytes; structures = 102,400 bytes; 336 Pipe records = 5,376 bytes; active Pipe scheduler = 48 bytes. The theoretical record cost is exactly 16 bytes/Pipe: 100k = 1,600,000 bytes. At that gate, presentation used three shared MultiMeshes plus material/Water texture pages; Phase 8.5 supersedes the dense infrastructure path below.

## Phase 8.5 rendering and pre-thermal gate

The Phase-8 `92.5 FPS` 20k-Pipe result above is the frozen pre-gate baseline. Phase 8.5 replaces dense Pipe/Conveyor instances with cropped `64x64` native pages and retains MultiMesh only for sparse Conveyors/machines. Godot `4.7.1`, GL Compatibility, 1920x1080, 120 ticks:

| Fixture | Total/visible | Pages | FPS | frame avg/p95/p99/worst |
|---|---:|---:|---:|---:|
| Pipes 2k | 2k/2k | 4 | 719.2 | 1.386/1.515/1.515/1.799 ms |
| Pipes 20k | 20k/20k | 8 | 559.8 | 1.782/2.381/2.778/6.656 ms |
| Pipes 50k | 50k/50k | 16 | 407.4 | 2.446/2.778/3.918/11.713 ms |
| Conveyors 20k | 20k/20k | 8 | 711.3 | 1.405/1.515/1.667/2.081 ms |
| Conveyors 50k | 50k/50k | 16 | 633.0 | 1.579/1.667/1.852/3.344 ms |
| Combined | 40k/40k | 16 | 541.5 | 1.845/2.381/2.381/2.778 ms |
| Visibility | 100k/2k | 4 | 745.2 | 1.342/1.389/1.389/2.148 ms |

Representative Phase-8 scene after the change: `424.7 FPS`, frame `2.351/3.030/3.333/9.721 ms`, simulation `0.937 ms` average. Mega fixture (20k Pipes, 20k Conveyors, 12 physical machines, 40 automation components): `444.3 FPS`, frame `2.250/2.381/3.030/5.852 ms`. With the isolated 30 Hz thermal candidate: `417.1 FPS`, frame `2.394/2.778/3.030/5.917 ms`; candidate cost `0.3579 ms` average over `5,008` active cells.

Temperature page comparison on the dense physical fixture: off `406.0 FPS`; visible `RG8` overlay on `361.3 FPS`, update `0.217 ms`, upload `0.065 ms`, payload `851,968` bytes.

Thermal candidate worker scaling:

| Active cells | 1 worker | 2 | 4 | 8 |
|---:|---:|---:|---:|---:|
| 65,536 | 1.2810 ms | 0.6443 ms | 0.3663 ms | 0.2390 ms |
| 262,144 | 4.8122 ms | 2.7282 ms | 1.2809 ms | 0.7506 ms |
| 1,048,576 | 20.4635 ms | 9.9211 ms | 5.1777 ms | 2.8432 ms |

All 64k worker runs hash `b4fa08fdef15f99b`. Uniform 1M visits zero cells at `0.001125 ms`. One-million active candidate memory: activity `6,299,648` bytes; reusable scratch `8,388,608` bytes. At this historical Phase-8.5 gate, `30 Hz` was selected and Phase 9 had not started.

## Phase 8.75 factory-foundation gate

Godot `4.7.1`, native Release, Windows, Ryzen 7 7800X3D / RTX 4080 SUPER:

| Workload | Result |
|---|---|
| Batch place 100 | validation `0.038 ms`; application `0.224 ms` |
| Batch place 1,000 | validation `0.159 ms`; application `2.682 ms` |
| Batch place 10,000 | validation `1.551 ms`; application `22.607 ms` |
| Batch undo/remove 10,000 | validation `0.930 ms`; application `22.522 ms` |
| Empty Subsurface | 100,032 cells; median `0.0110 ms`; p95 `0.4270 ms`; `0` visited |
| Active Subsurface | 50,000 packets; median `1.635 ms`; p95 `2.022 ms`; worst `2.513 ms` |
| Production rings | 1,000,000 events `2.434 ms`; `2.43 ns/event`; query `0.0870 ms` |
| Dense underground overlay | 600 routes; `771.9 FPS`; `1.294/1.389/1.389/1.391 ms`; overlay draw `0.0010 ms` |
| Info Mode | 3,941 visible machines; `611.5 FPS`; `1.635/1.667/1.852/6.004 ms`; UI `0.0086 ms`; overlay draw `0.0000 ms` |
| Overview | 100,000 Conveyors; `653.5 FPS`; `1.530/1.667/1.667/2.665 ms`; simulation `0.101 ms` |
| Phase-8.75 Megafactory | 20k Pipes + 20k Conveyors + physical machines/Water/Pump/Research/automation/tunnels/Blueprint section/statistics; `384.3 FPS`; `2.602/2.778/3.333/13.094 ms`; simulation `0.392 ms`; UI `0.0091 ms`; overlay `0.0010 ms` |

The earlier `112.5 FPS` Megafactory run exposed periodic `~145 ms` Alert Manager stalls caused by per-Pipe GDScript/native state calls. Alerts now scan the existing packed visible-Pipe records once per observation: the final full gate, including an active Pump and an actual `CommandBatch`-built section, reaches `384.3 FPS` with `3.333 ms` p99 and strong headroom. Dense route and Info presentation are one `MultiMesh` each; no per-route CPU dashes or per-machine UI nodes remain.

Regression rerun: active 1M Sand at 8 workers `9.5172 ms`; active 1M Water `15.4012 ms`; mixed 500k/500k `12.1668 ms`; stable filled 100k Pipes `0.0132 ms`; active 50k Pipes `14.9679 ms`; 256 Sluices `0.6717 ms`; Water recycling remains exact at `22,185` mass. Existing Phase-8.5 render baselines remain documented above.

## Phase 9 production thermodynamics gate

Final Windows release build, Godot `4.7.1.stable.official.a13da4feb`, RTX 4080 SUPER, GL Compatibility. Authoritative thermal and mobile-matter work uses 8 workers unless the matrix names another count.

| Scenario | Average | p99 | Kernel/detail |
|---|---:|---:|---|
| uniform hot 4M | `0.2417 ms` | `0.4470 ms` | `0` cells visited |
| active thermal 256k | `1.7142 ms` | `3.6120 ms` | thermal `1.7002 ms` avg, `3.5960 ms` p99 |
| active thermal 1M, 1 worker | `24.4512 ms` | `50.9660 ms` | thermal `50.8720 ms` p99 |
| active thermal 1M, 2 workers | `17.8284 ms` | `36.5140 ms` | thermal `36.3700 ms` p99 |
| active thermal 1M, 4 workers | `10.7687 ms` | `22.4590 ms` | thermal `22.3990 ms` p99 |
| active thermal 1M, 8 workers | `6.8930 ms` | `14.1300 ms` | thermal `14.0690 ms` p99, hash `2ec2bf8a` |
| active Steam 256k | `4.1552 ms` | `5.8380 ms` | gas `4.0458 ms` avg |
| active Steam 1M | `14.5747 ms` | `23.4890 ms` | gas/fluid `14.0163 ms` avg, gas `14.9040 ms` p99 |
| settled Steam 1M | `0.0454 ms` | `0.0850 ms` | fluid `0.0113 ms`, `0` active |
| Steam plume | `0.6265 ms` | `0.8000 ms` | `3,017` visited, `233` transfers |
| condensation | `0.2059 ms` | `0.5470 ms` | `1,568` condensed, `3,136` phase changes |
| molten Glass 256k | `0.3439 ms` | `7.1290 ms` | fluid `0.2492 ms` avg |
| molten Iron 256k | `2.8422 ms` | `7.0850 ms` | fluid `2.7269 ms` avg |
| Water + molten Iron | `2.2557 ms` | `3.5980 ms` | thermal `0.2825 ms`, fluid `1.9625 ms` |
| active Steam Pipes 50k | `15.7103 ms` | `39.4520 ms` | Pipe `13.2657 ms` avg, `30.1890 ms` Pipe p99 |

The 1M thermal 8-worker kernel and 1M active Steam kernel meet the `16.67 ms` target. The 50k active Steam-Pipe stress meets the average target but retains a high tail; it is recorded as optimization debt, not hidden or treated as a 60 Hz guarantee.

Historical final regression matrix after the generic whole-cell enthalpy fast path: active 1M Sand `9.2842 ms`; active 1M Water `14.6481 ms`; mixed 500k Sand/500k Water `11.9979 ms`; settled 1M Water `0.0534 ms`; persistent 4M `0.2089 ms`. Stable filled 100k Pipes `0.0137 ms`; active 50k Water Pipes `15.7274 ms`; 1000-cell uphill Pump reaches cell `0` with family mass `8,454,015` exact. Wet stress: 256 Sluices `0.6588 ms`; 5,000-tick recycling family mass `22,185 -> 22,185`, `exact=true`. Automation storm: 10k sensors `2.913 ms`, 10k logic `6.859 ms`, 30k actuators `7.058 ms`. Subsurface 50k packets: `1.468 ms` median, `1.723 ms` p95. One million statistics events: `2.570 ms` total. Thermal progression profile `4590`: complete branch cost `12,400/820/1` Glass/Iron/Gold, supplied within `25,719` Raw Sand at `240/s`, upper bound `107.162 s`.

Final 1920x1080 runtime fixtures:

| Fixture | FPS | frame avg/p95/p99/worst | simulation avg/p99 |
|---|---:|---|---|
| Phase-9 thermal factory | `162.2` | `6.162/7.407/8.727/12.390 ms` | `1.756/2.052 ms` |
| temperature overlay | `122.8` | `8.135/9.524/13.502/14.824 ms` | `1.764/2.018 ms` |
| overview LOD | `733.4` | `1.362/1.389/1.389/1.859 ms` | `0.846/1.107 ms` |
| Phase-8.75 Megafactory | `352.8` | `2.841/3.333/4.281/16.558 ms` | `1.076/2.721 ms` |

Temperature overlay visible update: `0.7260 ms`; upload `0.2010 ms`, `1,622,016` bytes. Factory production thermal: `0.1090 ms` average, `0.3020 ms` p99. Overview streaming is bounded to its fixture region; it does not allocate procedural chunks merely because minimum zoom sees a large area.

Godot directly wrote and returned `error=OK` for all fourteen required `phase9-*.png` captures plus eleven earlier fixture captures in `artifacts/phase9`. Representative early/late Ice, Steam rise/condensation, molten/contact, Pipe rupture, factory, overlay, overview and diagnostics frames were visually inspected. No Computer Use path was used.

## Phase 9.5 Steam, Pipe, and rendering gate (2026-08-28)

Phase-9 report baseline: 1M Steam approximately `14.3 ms` average / `22.9 ms` p99; 50k Steam Pipes approximately `15.6 ms` average / `40.0 ms` p99. Local pre-change instrumentation attributed Steam cost almost entirely to gas traversal (`~14.0 ms`) plus a cold thermal-page setup spike. Pipe tails split into repeated neighbor lookup/enthalpy conversion (`~19.9 ms` flow), state/damage (`~9.6 ms`) and scheduler rebuild (`~8.0 ms`).

| Workload | avg | p95 | p99/worst | notes |
|---|---:|---:|---:|---|
| 1M Steam, 1 worker | `40.8866 ms` | `41.7600 ms` | `41.9680 ms` | hash `47e74da4` |
| 1M Steam, 2 workers | `23.3256 ms` | `23.8820 ms` | `23.9010 ms` | `99.7%` worker utilization |
| 1M Steam, 4 workers | `12.5830 ms` | `12.9660 ms` | `13.1900 ms` | `98.0%` utilization |
| 1M Steam, 8 workers | `7.1305 ms` | `7.3640 ms` | `7.6590 ms` | `96.1%` utilization; cold `16.4930 ms` |
| 50k active Steam Pipes | `3.1736 ms` | `14.1690 ms` | `14.4520 ms` | active peak `50,000`; cold `20.0960 ms` |
| 100k active Steam Pipes | `11.5619 ms` | `28.3620 ms` | `28.3620 ms` | stress, not representative gate |
| stable 100k Steam Pipes | `0.3024 ms` | `0.3690 ms` | `0.5620 ms` | zero active/visited/transfers |
| 10k Water→Steam burst | `4.1589 ms` | `7.3470 ms` | `7.8920/8.2900 ms` | physical heating and pressure wave |
| 5k rupture storm | `0.7899 ms` | `1.6690 ms` | `1.6690 ms` | 5,000 local breaches; exact accounting |

Final 1080p GL Compatibility: Thermal Factory `229.3 FPS` (`4.353/5.000/5.556 ms` avg/p95/p99); Temperature Overlay `188.9 FPS` (`5.287/6.061/9.856 ms`, visible update `0.4820 ms`, upload `0.1370 ms`/`1,622,016` bytes); stable full-view Steam `305.3 FPS` (`3.273/3.333/3.333 ms`, zero steady material/fluid upload); historical Megafactory `490.8 FPS` (`2.036/2.381/2.703 ms`). Visible native material presentation is one cropped RGBA page, not one Sprite/extension upload per chunk.

Godot directly wrote and returned `error=OK` for the three required `1920x1080` captures under `artifacts/phase95`: `phase95-thermal-factory.png` (`306,346` bytes), `phase95-temperature-overlay.png` (`283,691` bytes), and `phase95-steam-render.png` (`905,582` bytes). All three were visually inspected without Computer Use.

Memory changes: gas profiling counters plus three fixed eight-worker arrays; no active-cell objects. Pipe segments remain `16` bytes. The 50k fixture uses `800,000` record bytes, up to `2,050,000` reusable scheduler-buffer capacity bytes and one process-global `1,048,576`-byte thermal-scale table; at 100k the reusable buffer capacity is `4,100,000` bytes. Buffers scale with active candidates and are derived/non-serialized.

## Phase 10 physical power gate (2026-08-28)

Native Release, Godot `4.7.1.stable.official.a13da4feb`, 30 Hz mechanical/electrical cadence. Times below include the whole empty-world `step()`, not only the reported subsystem timer.

| Workload | topology | avg | p95 | p99/worst | result |
|---|---:|---:|---:|---:|---|
| stable 100k Shaft segments, 1 cached component | `49.692 ms` | `0.0050 ms` | `0.0050 ms` | `0.0530 ms` | idle active networks `0` |
| 10k active isolated shaft networks | `7.138 ms` | `0.3846 ms` | `0.7940 ms` | `0.8630 ms` | 10k active |
| stable 100k Poles + 100k consumers | `297.163 ms` | `0.0044 ms` | `0.0050 ms` | `0.0210 ms` | 200,488 cached edges; no per-consumer tick rewrite |
| 10k active isolated Power networks | `11.598 ms` | `0.4014 ms` | `0.8090 ms` | `0.9000 ms` | 10k active |
| 300 physical Turbine/Shaft/Generator plants | event-built | `0.8116 ms` | `2.0910 ms` | `5.2040 ms` | 317,450,100 mechanical and 262,954,200 electrical quanta produced |

Exact native record sizes on this build: Shaft/member `48` bytes, mechanical network base `88` bytes, Pole `32` bytes, Power edge `32` bytes, consumer `72` bytes, electrical network base `144` bytes. Component member vectors, unordered-container capacity and allocator overhead are additional and implementation-dependent; the table does not mislabel record-only figures as total resident memory.

Topology rebuilds are event-triggered and measured separately from stable ticks. The 100k Pole cold construction rebuild is a `297.163 ms` editor/load spike, not per-tick work. Further localized split/merge optimization remains useful for live edits at extreme scale; normal stable and 10k-active gates have strong 16.67 ms headroom.

Final 1920x1080 GL Compatibility runtime:

| Fixture | FPS | frame avg/p95/p99/worst | simulation avg/p99 | Power presentation |
|---|---:|---|---|---|
| power factory wide | `456.2` | `2.192/2.381/2.778/5.800 ms` | `0.831/1.025 ms` | 11 Poles, 7 edges, 11 consumers, 2 plants |
| POWER overlay | `724.2` | `1.380/1.389/1.389/1.786 ms` | `0.347/0.438 ms` | batched update `0.0000 ms` at stable sample |

All thirteen required `1920x1080` captures were written by Godot with `error=OK` under `artifacts/phase10` and visually inspected without Computer Use.

## Phase 11 world/player gate

Final Release measurements on the same desktop: 10k validation `72.987 ms` (`137,010.7 seeds/s`, zero failures); 100 V2 chunks `37.630 ms` wall with `1.6565 ms` worker-average generation; 100k compact Character collision queries `0.001701 ms/query`; radius-72 FOV open average/p99 `1.9910/2.5500 ms`; solid shell `1.9511/2.2920 ms`; discovery `5136 bytes/chunk`. A 10k-cell traversal generated 1,141 chunks while bounding residency to 70 and ended with 70 resident chunks.

Character Factory 1080p after V2 InterestRegion fluid-boundary correction: `365.0 FPS`, frame avg/p95/p99/worst `2.732/2.778/4.545/9.980 ms`, simulation avg/p99 `1.992/2.266 ms`. Factory Mode reaches `394.1 FPS`. The historical Phase-8.75 Megafactory regression reaches `402.6 FPS` with frame avg/p95/p99/worst `2.487/2.778/2.778/7.547 ms`. The pre-fix recursive aquifer halo measured only `34.6 FPS` and 640 liquid planes; V2 now keeps generation interest-bounded.

The final Phase-9.5 confirmation run passes all 36 checks: 1M Steam at 8 workers `7.4492 ms` average and `8.1980 ms` p99; 50k active Steam Pipes `3.6357 ms` average and `16.3500 ms` p99. An immediately preceding unchanged run recorded a transient Pipe p99 of `17.3240 ms` against the `16.67 ms` tail gate while its average remained `3.8430 ms`; the variance is retained here rather than hidden.

## Phase 11.5 game-feel and UX gate

Release native/headless:

| Gate | Result |
|---|---|
| 25k correction sweep | `9.236 ms`; `2,706,799.5 seeds/s`; zero failures; no Moderate/Major correction |
| 100k Character ticks, FOV isolated | `868.506 ms` total; `0.008685 ms/tick`; 275,643 collision queries |
| radius-72 open cavern FOV | `2.0911 ms` average; `2.3360 ms` p99 |
| irregular solid shell | `0.7363 ms` average; `0.7770 ms` p99 |
| discovery memory | `5,136 bytes/chunk` |
| 100 generated V2 chunks | `36.486 ms` wall; `1.5659 ms` worker average; `1.9950 ms` worst |
| 10k-cell Character traversal | `547.081 ms` wall; 1,141 requests; resident peak/final `70/70`; publish total `272.669 ms` |

Player UI matrix:

| Surface | Main-thread cost |
|---|---:|
| normal HUD refresh | `0.004658 ms` average |
| Build Catalog refresh | `0.004606 ms` average |
| Statistics refresh | `0.004631 ms` average |
| Character Map open | `4.6730 ms` |
| Research open/update | `0.1470 / 0.0050 ms` |
| Info Mode open | `0.1790 ms` |
| 1,000-cell Blueprint preview update | `0.0010 ms` |
| Temperature Overlay open/update/upload | `0.9380 / 0.2130 / 0.0140 ms`; `516,096 bytes` |

1920x1080 GL Compatibility runtime:

| Fixture | FPS | frame avg/p95/p99/worst | simulation average | Character FOV |
|---|---:|---|---:|---:|
| Character normal | `387.0` | `2.581/2.778/5.556/15.309 ms` | `1.937 ms` | `1.622 ms` latest |
| Factory normal | `451.3` | `2.213/2.381/2.381/6.110 ms` | `1.547 ms` | n/a |
| Phase-8.75 Megafactory regression | `414.4` | `2.414/2.778/3.670/8.824 ms` | `1.000 ms` | n/a |

Unified-matter regression at eight workers: 1M active Sand `9.1796 ms` average / `9.9070 ms` p99; 1M active Water `9.1598 / 10.0290 ms`; 1M active Steam `7.2111 / 7.6330 ms`.

The pre-fix 50k active Steam-Pipe confirmations repeatedly missed the hard tail gate (`17.5270`, `17.8390`, `17.0000 ms` p99). The cause was four unordered-map neighbor chunk lookups per active segment on even ticks. Sorted traversal now caches adjacent matter chunk pointers without changing tick ordering or canonical hashes. Three final confirmations measured:

| Confirmation | average | p99 |
|---|---:|---:|
| 1 | `3.2841 ms` | `15.4700 ms` |
| 2 | `3.3109 ms` | `16.2570 ms` |
| 3 | `3.5699 ms` | `16.4880 ms` |

Representative/median confirmation p99 is `16.2570 ms`, inside the `16.67 ms` hard gate; hash remains `2b8f412e`.

## Phase 12 — Organic World, combustion and cookware

Final Release measurements, Godot `4.7.1`, Ryzen 7 7800X3D, eight native workers, RTX 4080 SUPER compatibility renderer:

| Scenario | Average | p95 | p99 / worst | Key work |
|---|---:|---:|---:|---|
| 100k idle standing Trees | `0.0048 ms` | `0.0050 ms` | `0.0050 / 0.0560 ms` | `0` records, clusters, atmosphere |
| 100 simultaneous Tree falls | `0.2563 ms` | `0.4070 ms` | `2.1480 ms` | settles to `0` active clusters |
| 1000 simultaneous Tree falls | `2.2223 ms` | `2.9720 ms` | `21.3680 ms` | synthetic settlement tail |
| 1M uniform Wood after wake | `0.2230 ms` | `0.3590 ms` | `0.3590 ms` | no atmosphere/cluster work |
| 1M implicit ambient cells | `0.0048 ms` | `0.0050 ms` | `0.0050 / 0.0530 ms` | `0` explicit cells |
| 256k disturbed atmosphere | `42.5851 ms` | — | `44.0380 ms` | `41.8490 ms` diffusion kernel |
| 100k active combustion | `36.5868 ms` | — | `68.2440 ms` | final reaction `15.7200 ms`, atmosphere `9.7400 ms`; deliberately harsher than representative play |
| 1M Smoke cold/settle stress | `3.5741 ms` | — | `18.1350 ms` | one cold active tail, then sleep |
| 256 kiln groups | `10.4744 ms` | `11.7990 ms` | `12.4830 ms` | reaction `0.6550 ms`, atmosphere `8.8190 ms` |
| 1000 heated Pots | `1.4865 ms` | — | `2.6520 ms` | Pot-specific storage `0`; generic cells/thermal |

The 100k-burning and 256k-atmosphere cases are synthetic saturation tests, not representative frame budgets. Representative 1080p organic Character reaches `399.3 FPS` (`2.499/2.778/2.778/3.239 ms` average/p95/p99/worst frame; `2.917 ms` average simulation). Organic Factory reaches `441.0 FPS` (`2.264/2.778/2.778/6.784 ms`; `2.529 ms` average simulation). Historical Megafactory reaches `414.2 FPS` (`2.413/2.778/4.768/14.802 ms`; `1.184 ms` average simulation).

Historical gates after removing nonorganic cells from the reaction scheduler and caching active Pipe records:

- 1M Sand: `10.8549 ms` average, `11.5410 ms` p99;
- 1M Water: `10.3465 ms` average, `11.5300 ms` p99;
- 1M Thermal: `7.0037 ms` average, `14.2390 ms` p99 (`14.1730 ms` thermal kernel p99);
- 1M Steam: `7.3780 ms` average, `7.8350 ms` p99;
- 50k active Steam Pipes: `2.5157 ms` average, `10.3970 ms` p99, hash `2b8f412e`;
- 100k stable Pipes: `0` active/visited, `0.5600 ms` p99;
- Automation 50k components idle: `0` visited, `0.137155 ms` average circuit;
- Subsurface 100,032 lane cells/50k packets: `1.492 ms` median, `1.942 ms` p95;
- Power 300 plants: `0.8690 ms` average, `5.9050 ms` p99.

Base simulation storage remains `9 B/cell`. Organic `uint8` moisture/oxidizer, `uint16` progress and `uint8` state planes allocate per 64×64 chunk only on use (`4096/4096/8192/4096 B`).

## Phase 13 — MVP consolidation gate

Final Release measurements on Windows, Godot `4.7.1.stable.official.a13da4feb`, Ryzen 7 7800X3D / RTX 4080 SUPER, eight native workers unless noted:

| Workload | Average | p99 | Result |
|---|---:|---:|---|
| 1M active Sand | `11.0491 ms` | `11.4670 ms` | pass |
| 1M active Water | `9.7910 ms` | `10.5110 ms` | pass |
| 1M active Thermal | `7.6645 ms` | `14.8740 ms` | pass |
| 1M active Steam | `7.6991 ms` | `8.0920 ms` | pass |
| 50k active Steam Pipes | `2.6787 ms` | `10.3100 ms` | pass; hash `2b8f412e` |
| 256k genuinely disturbed atmosphere | `1.9071 ms` | `3.1700 ms` | hard and preferred pass; baseline `42.1529 ms` |
| 100k actively burning cells | `9.3420 ms` | `22.2630 ms` | hard average and preferred average pass; preferred p99 miss retained |
| 1M active Smoke after explicit warmup | `3.2360 ms` | `10.9630 ms` | pass; hash `2f9daa27` |
| 1000 simultaneous Tree falls | `2.4102 ms` | `23.0320 ms` | synthetic settlement tail; nonblocking |

Atmosphere optimization caches surface limits and adjacent chunk/plane pointers, skips equilibrium interiors and avoids repeated hash lookups/allocations. Combustion uses sparse reaction fronts, sleep/wake deadbands, direct oxidizer access and the shared fixed-integer carry ledger. The atmosphere hard target improves by `22.1x` from the measured Phase-13 baseline; active-combustion average improves by `3.8x`.

Component and persistence workloads:

| Workload | Result |
|---|---:|
| 1,000,000 exact fraction events | `18.1690 ms`; `55,038,802.4 events/s`; balanced |
| connected Screen network, 1024 cells | `0.2390 ms` average; `0.3500 ms` p99 |
| Riffle field, 1024 cells | `1.2571 ms` average; `1.6120 ms` p99 |
| magnetic concentrate, 1024 cells | `0.1431 ms` average; `0.1640 ms` p99 |
| wet sediment/clay fines, 16,384 cells | `4.8478 ms` average; `6.4160 ms` p99 |
| component Furnace, 1024 cells | `0.1255 ms` average; `0.2590 ms` p99 |
| component vessel, 1024 cells | `0.1974 ms` average; `0.3240 ms` p99 |
| production save | `0.340 ms` snapshot capture; `22.331 ms` background/atomic write |
| production load | `2.090 ms` |

The autosave main-thread hitch is the consistent snapshot capture (`0.340 ms` in the final full regression); encoding, checksum, validation and atomic replacement run on the background writer.

Final 1920x1080 GL Compatibility runtime:

| Fixture | FPS | frame average | frame p99 |
|---|---:|---:|---:|
| Character | `491.3` | `2.030 ms` | `2.381 ms` |
| Factory | `557.4` | `1.790 ms` | `2.307 ms` |
| historical Megafactory | `425.5` | `2.350 ms` | `3.333 ms` |

All representative gameplay fixtures exceed the `100 FPS` hard target and the `200 FPS` preferred target. The first combined baseline Megafactory launch terminated with Windows status `0xC0000005`; an isolated rerun succeeded at `48.9 FPS`. Final post-fix confirmation is the stable `425.5 FPS` result above. This historical crash is retained rather than hidden.
# Phase 13.5 Playtest RC measurements

Current `0.1.0-playtest.1` measurements and limitations are recorded in `PHASE135_PLAYTEST_RC.md`. Representative packaged Factory: `491.4 FPS`; frame avg/p95/p99/worst `2.027/2.083/2.083/4.010 ms`. Realistic fire p99 ranges from `0.2210 ms` (campfire) to `2.2040 ms` (5k-cell industrial fire). Codex search p99 `0.4760 ms`; representative audio aggregation p99 `0.0690 ms`; VFX p99 `0.0560 ms`.

## Phase 13.6 factory bounds

1080p Compatibility renderer, RTX 4080 SUPER, Godot `4.7.1` wrapper:

- `REALISTIC_MAX_FACTORY`: `242.0 FPS`; frame avg/p95/p99/worst `4.129/4.762/6.335/10.631 ms`; simulation avg/worst `2.637/3.609 ms`; material render `2.930 ms`; `4,848` structure tiles; `56,127` active-region cells.
- Dense synthetic Megafactory: `51.5 FPS`; frame avg/p95/p99/worst `19.405/22.222/27.091/30.952 ms`; simulation avg/worst `7.217/11.431 ms`; material render `6.225 ms`; residual render `5.957 ms`; Water upload `2.597 ms` / `884,736` bytes; `15,600` structure tiles; `169,167` active-region cells.

The synthetic fixture is deliberately beyond the intended MVP view density: 13 near-full-width belts, 300 structures, moving matter plus incidental visible procedural Water. It exposes combined simulation, dirty-material upload and fill/draw cost rather than one isolated subsystem. It remains public and below 100 FPS. The intended maximum fixture exceeds the hard 100 FPS gate with `2.42×` headroom.

## Phase 13.7 baseline gate

Final Windows measurements on Godot `4.7.1.stable.official.a13da4feb`, Ryzen 7 7800X3D, RTX 4080 SUPER, GL Compatibility, eight simulation workers:

| 1920x1080 fixture | FPS | frame avg/p95/p99/worst | simulation avg/worst | Result |
|---|---:|---|---|---|
| Character Factory | `373.6` | `2.673/2.778/4.545/9.712 ms` | `2.053/2.268 ms` | pass; clean verbose shutdown |
| Full-game Factory | `713.4` | `1.401/1.515/1.515/3.131 ms` | `0.483/0.569 ms` | pass |
| Creative fixture | `569.4` | `1.755/1.852/1.852/3.237 ms` | `0.526/0.691 ms` | pass |
| Realistic maximum Factory | `241.1` | `4.142/5.000/6.878/10.579 ms` | `2.615/3.728 ms` | pass |
| Dense synthetic Megafactory | `51.8` | `19.286/22.222/22.727/27.194 ms` | `7.220/11.275 ms` | known pathological bound |

The complete scripted matrix passed `26/26` benchmark programs. Phase 13.7 adversarial scaling additionally measured `10,000,000` exact production events in `172.305 ms` with `163,200,000,000` input and accounted micro-mass, and `100,000` WorldGen seeds with zero failures (`0.649/0.704/0.734/0.753 ms` p50/p95/p99/max per 1,000-seed batch).

The accelerated four-hour soak was stopped at the user-approved 60-minute wall-time boundary after more than `64` minutes of continuous responsive execution. Live probes remained flat at approximately `104,157,184` bytes Working Set and `52,432,896` bytes Private Memory. Because the process was interrupted before its own terminal report, this is evidence for a stable 64-minute partial soak, not a completed four-hour pass.

## Phase 13.8 final player-experience gate — 2026-08-30

Host: Windows, NVIDIA GeForce RTX 4080 SUPER, Godot `4.7.1.stable.official.a13da4feb`, GL Compatibility, `1920×1080`, eight simulation workers, `Dummy` audio for every automated run.

| Runtime case | FPS | Frame p95 | Frame p99 | Worst frame |
|---|---:|---:|---:|---:|
| Character | 345.6 | 3.030 ms | 3.333 ms | 8.478 ms |
| Factory | 334.3 | 3.704 ms | 4.764 ms | 16.518 ms |
| Creative | 330.9 | 3.333 ms | 4.011 ms | 6.848 ms |
| Realistic Maximum Factory | 206.0 | 5.556 ms | 7.026 ms | 11.424 ms |
| Production Overlay | 315.0 | 3.333 ms | 3.333 ms | 6.852 ms |
| Build Catalog open | 277.1 | 3.704 ms | 4.571 ms | 8.294 ms |
| Dense Synthetic Megafactory | 44.2 | 25.000 ms | 28.343 ms | 29.190 ms |

The Dense Synthetic Megafactory deliberately places `15,600` structure tiles and keeps `169,351` active-region cells in the rendered stress view. Its below-target result is a documented scalability limit, not representative player density. Realistic Maximum remains above the `100 FPS` owner-playtest target.

The bounded stability smoke ran Realistic Maximum Factory for `699.990 s` (`11m 39.990s`), rendered `183,379` frames and completed `42,044` ticks. Result: exit `0`, `262.0 FPS`, `4.167 ms` p95, `4.762 ms` p99, `35.798 ms` worst, no `SIGSEGV`, no `0xC0000374` and no additional project error. The recurring root-certificate-store diagnostic remained nonfatal.

Full correctness: `26` scripts passed in `30.224 s`, including the eight-worker reactive-cell regression and `57` Phase 13.8 checks. Native Release build and Phase 9 render/simulation regression passed. Automated audio output was disabled; mixer generation, pool bounds, 16-bit format, loop bounds, seam delta and safe category headroom were verified structurally.

## Phase 13.9 final FTUE gate — 2026-08-30

Same host, renderer and strictly `Dummy` audio. Phase 13.9 adds UI guidance only; the runtime sanity gate confirms inactive tooltip/highlight systems do not compromise representative play.

| Runtime case | FPS | Frame average | Frame p95 | Frame p99 | Worst frame |
|---|---:|---:|---:|---:|---:|
| Character | `287.3` | `3.470 ms` | `4.762 ms` | `7.194 ms` | `13.465 ms` |
| Factory | `330.7` | `3.004 ms` | `3.333 ms` | `5.695 ms` | `16.548 ms` |
| Creative | `336.7` | `2.954 ms` | `3.333 ms` | `5.082 ms` | `16.523 ms` |
| Realistic Maximum Factory | `192.7` | `5.185 ms` | `5.556 ms` | `8.466 ms` | `11.471 ms` |
| Dense Synthetic Megafactory | `43.7` | `22.813 ms` | `25.000 ms` | `27.905 ms` | `28.965 ms` |

All four representative fixtures exceed `100 FPS`. Dense Synthetic remains a disclosed out-of-scope stress bound with `15,600` structure tiles and `169,351` active-region cells.

The required representative smoke ran Factory Mode for `599.983 s`, rendered `200,150` frames, completed `36,020` ticks and exited `0`: `333.6 FPS`, `2.998 ms` frame average, `3.333 ms` p95/p99, `16.664 ms` worst frame and `5.606 ms` worst simulation tick.

## Phase 13.9B final responsive-UI gate — 2026-08-30

Same Windows host, Godot `4.7.1.stable.official.a13da4feb`, GL Compatibility at `1920×1080`, and strictly muted automated audio.

| Representative runtime | FPS | Frame average | Frame p95 | Frame p99 | UI average |
|---|---:|---:|---:|---:|---:|
| Character | `308.6` | `3.235 ms` | `3.695 ms` | `4.868 ms` | `0.0086 ms` |
| Factory | `477.0` | `2.094 ms` | `2.381 ms` | `2.381 ms` | `0.0083 ms` |
| Creative | `414.5` | `2.409 ms` | `2.778 ms` | `2.778 ms` | `0.0091 ms` |
| Realistic Maximum Factory | `179.1` | `5.579 ms` | `6.061 ms` | `8.947 ms` | `0.0094 ms` |
| Dense Synthetic Megafactory | `42.2` | `23.699 ms` | `26.389 ms` | `28.663 ms` | `0.0098 ms` |

| Player UI surface | FPS | Frame average | Frame p95 | UI average |
|---|---:|---:|---:|---:|
| Build Catalog | `238.0` | `4.195 ms` | `4.545 ms` | `0.0091 ms` |
| Research | `259.8` | `3.846 ms` | `5.000 ms` | `0.0129 ms` |
| Codex | `515.1` | `1.938 ms` | `2.083 ms` | `0.0086 ms` |
| Inspector | `550.4` | `1.814 ms` | `2.083 ms` | `0.0092 ms` |
| Map | `320.8` | `3.113 ms` | `3.333 ms` | `0.0092 ms` |
| Production Overlay | `271.7` | `3.677 ms` | `4.167 ms` | `0.0091 ms` |

All four representative fixtures exceed the hard `100 FPS` owner-playtest gate. The UI remains event/layout driven; no per-frame full-tree overlap scan was added. Dense Synthetic remains the separately disclosed pathological rendered ceiling.

The final Factory stability run exited `0` after `600.006 s`, `36,020` ticks and `282,380` frames: `470.6 FPS`, `2.125 ms` frame average, `2.381 ms` p95/p99, `19.987 ms` worst frame and `0.864 ms` worst simulation tick. The clean-profile functional smoke additionally passed Character creation, Build, Save/Exit/Continue, Codex, Settings, Planning Pause, Factory, Creative and local Diagnostics.

The full historical benchmark script is not entirely green after a clean source build. The isolated Phase 3 50k-active Conveyor stress reproducibly measures `17.096 ms/tick` against its `16.67 ms` invariant. The isolated Phase 7 one-million-active Sand stress reproducibly measures `44.0126 ms/tick` at eight workers against the same invariant. Neither test loads the Phase 13.9B UI code, while representative runtime and UI measurements above pass with substantial margin. Both failures remain explicit optimization debt rather than being relabeled as passes.
