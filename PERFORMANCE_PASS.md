# Input and Simulation Performance Pass

The owner started the game, held the left mouse button and moved it to spawn Sand, and reported
zero frames per second. This pass began there and ended with the whole benchmark suite passing
end to end for the first time.

Two gates were carried in `PERFORMANCE.md` as disclosed optimization debt. Only one of them was
actually failing. The Phase 3 50k-active Conveyor stress measured `15.346 ms/tick` on this host
before any change here -- already inside its `16.67 ms` invariant, not the `17.096 ms` on
record -- and `13.233 ms` after. The Phase 7 one-million-active Sand stress was genuinely red at
`41.914 ms`. The two could not be told apart from a suite run, because the harness aborted at
the first failure and never reached the rest (§5).

Everything below was measured on the host `PERFORMANCE.md` documents: Ryzen 7 7800X3D, RTX 4080
SUPER, Godot `4.7.1`, MinGW-W64 GCC `16.1.0`, optimized `template_release` GDExtension.

---

## What the report actually contained

Two separate defects, only one of which the owner had noticed.

Reproducing the drag headlessly through the production scene showed the frame cost, and the
same run also exited with:

```
terminate called after throwing an instance of 'std::out_of_range'
  what():  unordered_map::at
[exited with code 9]
```

An uncaught C++ exception in a GDExtension calls `std::terminate`. There is no Godot error, no
entry in the log and no crash dialog: the window is simply gone. It is the least visible way a
game can fail, and it was reachable from the first minute of play.

---

## 1. Starting a second world took the process down

`configure_world()` is the call behind every "New Game". It cleared `chunks_`, the generation
queues, `machine_entities_` and a handful of logistics lists. It did **not** clear:

`physical_processors_`, `physical_chunk_watchers_`, `active_magnets_`, `active_screens_`,
`active_heaters_`, `active_wet_sluices_`, `thermal_switch_cells_`, `closed_thermal_switches_`,
`heat_exchanger_cells_`, `thermal_candidate_statistics_`, and the whole of
`reset_automation()`, `reset_power()`, `reset_pipe_logistics()`, `reset_organic_physics()` and
`reset_phase13()`.

`reset()` cleared all of them. Two entry points into the same state, each maintaining its own
list, and one of them fifteen entries short.

So a second world began holding the first world's machine registries. The first `step()`
iterated `active_heaters_`, found the id in `physical_processors_`, and then:

```cpp
MachineEntity &entity = machine_entities_.at(id);   // no machine behind that id any more
```

**The fix is one list, called from both.** `clear_world_state()` now holds everything a world
owns, and `reset()` and `configure_world()` both call it. That is the only version of this that
stays correct as subsystems are added, and subsystems are still being added.

Finding it took work worth recording. The crash reproduced six times out of six from the
production scene but zero times out of three under `gdb` — the debugger changed thread timing
enough to hide it — and stdout is lost on `std::terminate`, so the last line printed was a lie.
Markers written through an explicitly flushed file located it in `step()`, and wrapping each
`process_*()` call in a temporary diagnostic named `process_physical_heaters()` directly.

### Second line of defence

Four call sites took an id from one registry and indexed another with `at()` without checking.
Those are now checked lookups that skip the entity. A subsystem skipping one machine is always
a better failure than the process disappearing:

| File | Was |
| --- | --- |
| `native_physical_processing.cpp` | four `machine_entities_.at(id)` after a `physical_processors_.find(id)` |
| `native_power.cpp` | `machine_entities_.at(id)` for turbine and generator waste heat |
| `native_automation.cpp` | `automation_components_.at()` on both ends of a connection |

### Test

`tests/new_world_state.gd` places one of every structure the world accepts, starts a second
world on top of it, and asserts that seventeen registry-size statistics all read zero and that
the new world can be stepped. It was checked against a deliberately reintroduced omission: the
census fails on four counts, which is exactly the bug.

---

## 2. Painting was five seconds a frame

`_paint_stamp()` submitted one `WorldCommand` **per cell**. Each one built a `CommandBatch`,
deep-copied its payload, read the entire statistics dictionary out of native, ran batch
validation, and serialised itself into a log. `_paint_line()` then called that stamp once per
interpolated point along the drag.

A radius-3 brush is 29 cells. A pointer moving 160 world cells between two frames is 161
stamps. That is **roughly 4,700 complete command round trips in a single frame**, for an edit
the simulation performs in a tenth of a millisecond.

Measured through the real editor path, before:

| Drag speed | Frame | Rate |
| ---: | ---: | ---: |
| 4 cells/frame | 50.16 ms | 19.9 fps |
| 16 cells/frame | 424.72 ms | 2.4 fps |
| 40 cells/frame | 1,115.52 ms | 0.9 fps |
| 80 cells/frame | 2,253.64 ms | 0.4 fps |
| 160 cells/frame | 4,763.40 ms | **0.2 fps** |

The same brush work in native, without the command layer, cost `0.26 ms`. Over 99% of the time
was bookkeeping.

### A stroke is one gesture

`paint_stroke(from, to, radius, material_id)` and `harvest_stroke(from, to, radius)` sweep the
brush natively, and `PAINT_STROKE` / `HARVEST_STROKE` carry the whole gesture as one command.
Cost is now independent of how fast the pointer moves.

Two decisions worth stating:

**The geometry is bit-identical to the old brush.** The obvious implementation is a capsule --
the exact swept shape, and arguably nicer. It is not what the brush painted. The old stamp path
walks interpolated points and unions discs, and on a diagonal that is a staircase, not a
capsule; the difference is small but it is a change to how the tool feels, and a performance
fix is not allowed to make that change quietly. The native sweep reproduces the same set,
interpolating in exact integer arithmetic rather than with `lerp` and `round`, because a stroke
edits the world and two machines have to agree on it. `tests/brush_stroke.gd` asserts the two
agree cell for cell across sixteen strokes.

**The igniter still leaves a trail.** It stays one command per point along the path, but all of
them in a single batch, so the per-command overhead is paid once per gesture instead of once
per point.

Measured through the real scene, after:

| Drag speed | Frame mean | p95 | Rate |
| ---: | ---: | ---: | ---: |
| 4 cells/frame | 6.76 ms | 10.54 ms | 148 fps |
| 16 cells/frame | 6.88 ms | 11.08 ms | 145 fps |
| 40 cells/frame | 6.98 ms | 12.39 ms | 143 fps |
| 80 cells/frame | 7.34 ms | 13.51 ms | 136 fps |
| 160 cells/frame | 6.81 ms | 11.30 ms | 147 fps |

**Roughly 700× at the worst drag speed**, and flat: the cost no longer scales with how fast the hand
moves. `tests/benchmark_brush_input.gd` drives the real scene and fails the run if any drag
speed exceeds the 16.6 ms frame budget at p95.

Three smaller things fell out of the same change. Painting into the world edge used to retrigger
the invalid sound once per rejected cell — hundreds of times a frame; it is now once per
gesture. Redrawing and rebuilding the status text moved out of the motion handler, which fires
several times per frame, into the frame itself. And the command and batch logs, which nothing
but the determinism tests reads, no longer grow for the length of the session.

---

## 3. A million falling Sand cells, and why Sand cost five times Water

The `benchmark_phase7.gd` gate had been failing and was disclosed as debt: one million active
Sand cells at `41.91 ms` against a `16.67 ms` budget. One million active **Water** cells, over
the same number of visited cells, cost `8.96 ms`.

The same number of cells, the same visiting order, a five-fold difference. That asymmetry is
the whole clue.

Every granular move pushed both the vacated and the occupied cell onto a list for the serial
barrier, where each one cost a hash-set erase and a chunk-map lookup to re-derive
`reactive_cells_`. A million moves per tick is four million serial map operations. Water moves
mass rather than cells and never touched that path.

A cell enters `reactive_cells_` only if its material is reactive or it carries bound water, and
`process_reactions()` clears the set every tick and rebuilds it. So for dry Sand the erase found
nothing and the re-activation inserted nothing: the entire notification was a provable no-op, at
four million map operations a tick.

Three changes, all inside `move_granular_fast()`:

1. **Notify only when reactive state can change.** `reactive_state_possible()` mirrors the
   insert rule in `activate_reactive_cell()` exactly, and is deliberately placed next to the
   caller so a change to one is visibly a change to the other.
2. **A same-chunk destination no longer goes through the chunk map.** Only cells on a chunk edge
   fall out of their chunk, so the hash lookup — three per cell, on the hottest loop in the
   simulation — was almost always resolving to the chunk already in hand. The fluid path has
   had this index all along.
3. **The structure plane is read from the resolved chunk** instead of going back through
   `get_structure()`, which repeats the lookup.

| Workers | Before | After |
| ---: | ---: | ---: |
| 1 | 96.22 ms | 50.37 ms |
| 2 | 69.48 ms | 25.53 ms |
| 4 | 51.52 ms | 14.34 ms |
| 8 | **41.91 ms** | **7.86 ms** |

`5.3×` at eight workers, and the scaling curve is close to linear now because the removed work
was the serial part. The fixture's content hash is `5d282148` before and after: the simulation
result is bit-for-bit unchanged.

`tests/granular_movement.gd` pins what the change depends on: bound water travels with the cell
that carries it, a burning cell is still reacting after it falls, dry Sand registers nothing
reactive, and nothing is created or lost falling across a chunk boundary. Against a deliberately
broken predicate the burning-cell check fails, so the test is not decoration.

---

## 4. Three and a half megabytes allocated every frame

`consume_dirty_render_page()` recoloured only dirty cells into each chunk's retained RGBA
buffer — that part was already incremental — and then assembled the visible page into a fresh
`PackedByteArray` every frame. At 1024×864 that is allocating and zero-filling `3.54 MB` and
then immediately overwriting nearly all of it. The preparation cost more than the copy it was
preparing for.

The buffer is now retained between calls, and only the regions no chunk covers are cleared,
which is what the fresh allocation was really providing.

Dense synthetic Megafactory, 1080p windowed:

| | Documented | After granular | After render page |
| --- | ---: | ---: | ---: |
| FPS | 43.7 | 69.0 | **79.4** |
| frame mean | — | 14.47 ms | **12.62 ms** |
| p95 | 25.000 ms | 17.17 ms | **16.67 ms** |
| p99 | 27.905 ms | 19.29 ms | **18.03 ms** |
| worst | — | 25.02 ms | **19.18 ms** |

---

## 5. The harness stopped at the first failure

Running the benchmark suite end to end exposed a fifth problem, in the tooling rather than the
game. Windows PowerShell 5.1 wraps every stderr line from a native executable in an
`ErrorRecord`. Under `$ErrorActionPreference = 'Stop'` that is a terminating error, and
`scripts/godot.ps1` runs with `Stop`.

So the first script that wrote to stderr — which is precisely what a failing script does — took
down the harness. The run reported `godot.ps1` itself as the fault, the remaining benchmarks
never ran and no summary was printed. So `scripts/benchmark.ps1 -IncludeRuntime` could not
complete while any script was failing, and the scripts after the first failure could not be
observed at all -- which is why the Phase 3 conveyor figure on record was stale.

The wrapper now relaxes the preference around the native call and restores it afterwards; the
exit code is what says whether a run failed, which is what it always meant. Both harnesses also
collect their streams through one helper rather than merging them inline.

---

## Also fixed

Re-capturing the UI to check the renderer change showed the production statistics panel drawing
its text straight past its own right edge and off the screen, and its content vertically centred
rather than starting at the top. The `Label` had no wrapping and no vertical fill; both are
pre-existing, both are visible in the earlier Phase 13.9B captures, and both are one line each.

---

## Verification

| | Result |
| --- | --- |
| `scripts/test.ps1` | `TEST_SUITE_PASS scripts=34` |
| `scripts/benchmark.ps1 -IncludeRuntime` | passes end to end, including `benchmark_phase7.gd` |
| `tests/brush_stroke.gd` | 54 checks |
| `tests/new_world_state.gd` | 39 checks |
| `tests/granular_movement.gd` | 17 checks |
| `tests/benchmark_brush_input.gd` | `BRUSH_BENCHMARK_PASS`, every drag speed inside budget |
| `scripts/capture_v5.ps1` | 30 contact sheets, `PASS` |
| `scripts/capture_phase139b.ps1` | UI captures, visually clean after the renderer change |
| owner package smoke | all eleven flows `1` |
| `scripts/package_playtest.ps1` | `39,488,669` bytes, SHA256 `20F324C0…` |

Runtime frame cost, 1080p windowed, 300 ticks per case:

| Fixture | FPS | frame mean | p95 | p99 |
| --- | ---: | ---: | ---: | ---: |
| character-factory | 495.2 | 2.02 ms | 2.08 ms | 2.78 ms |
| full-game-factory | 626.9 | 1.59 ms | 1.67 ms | 1.67 ms |
| creative-fixture | 504.9 | 1.98 ms | 2.08 ms | 2.08 ms |
| realistic-max-factory | 220.1 | 4.55 ms | 6.00 ms | 8.39 ms |
| dense-factory (pathological) | 79.4 | 12.62 ms | 16.67 ms | 18.03 ms |

---

## Still open

- **The visible page is uploaded whole.** Only dirty cells are recoloured and the assembly no
  longer allocates, but `ImageTexture.update()` has no partial form, so a changed page uploads
  every pixel. Uploading sub-rects would mean going back to per-chunk textures, which the page
  design deliberately replaced.
- **Character field of view costs `1.49 ms`** per recompute over about 9,800 cells. It only runs
  when the character crosses a cell boundary, so it is not a per-frame cost, but a sprinting
  character crossing one per frame pays it every frame.
- **The dense synthetic Megafactory is still the slowest fixture** at `12.62 ms` mean. It is a
  scalability probe and not a supported gameplay promise; it is now inside the frame budget on
  this host rather than well outside it.
- **Subjective checks remain owner-only.** Frame numbers say nothing about whether the brush
  feels right in the hand. `PLAYTEST_CHECKLIST.md` still applies.
