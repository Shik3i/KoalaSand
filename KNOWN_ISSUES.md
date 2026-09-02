# Known Issues

Priorities describe engineering risk for continued owner playtesting, not a release schedule.

## P0

None known after the Phase 13.9 verification gate.

## P1

- **Dense synthetic Megafactory:** intentionally pathological density now measures `79.4 FPS`, `16.667 ms` p95 and `18.031 ms` p99, up from `43.7 FPS` / `25.000 ms` / `27.905 ms`. It is still reported separately from the realistic maximum-factory gate; see [PERFORMANCE.md](PERFORMANCE.md).
- **Manual playtest coverage:** automated captures and state assertions cannot establish subjective controls, readability, audio balance or fun. The owner checklist remains required.

## Fixed in the input and simulation performance pass

- **The game closed itself when a second world was started:** `configure_world()` -- the call
  behind every "New Game" -- cleared `machine_entities_` but left `physical_processors_`, the
  active magnet/screen/heater/sluice sets, the thermal switch and heat exchanger cells and the
  whole automation, power, pipe, organic and phase13 registries holding the previous world's
  ids. The first `step()` of the new world walked a heater id with no machine behind it and
  `machine_entities_.at(id)` threw `std::out_of_range`. An uncaught exception in a GDExtension
  takes the process down with no Godot error, no log line and no crash dialog, so it looked
  like the window had simply disappeared. `reset()` and `configure_world()` now share one
  `clear_world_state()`.
- **Painting collapsed the frame rate to zero:** the editor submitted a separate command --
  each with its own `CommandBatch`, deep-copied payload, full statistics read and serialised
  log entry -- for every cell of every brush stamp. A radius-3 brush dragged 160 cells in a
  frame came to roughly 4,700 round trips and `4,763 ms`. A stroke is now one command.
- **The command log grew without limit:** `WorldCommandBus` kept every command and batch it had
  ever applied. Nothing but the determinism tests reads them, and a minute of painting left
  tens of thousands of serialised commands in memory.
- **Production statistics ran off the right edge of the screen:** the panel's `Label` had no
  wrapping and no vertical fill, so long rows drew straight through the panel and the block sat
  vertically centred instead of starting at the top.
- **A failing test or benchmark aborted its own harness:** Windows PowerShell 5.1 turns each
  stderr line from a native executable into a terminating error under
  `$ErrorActionPreference = 'Stop'`, so `scripts/godot.ps1` reported itself as the fault, the
  suite stopped at the first failure and no summary was printed.

## Fixed in the V5 release-polish pass

- **Character spawned buried:** `get_character_spawn()` returned the V4 surface height for a
  V5 world, so Character mode began inside rock with only a small discovered pocket visible.
- **Prototype showcase light in every view:** an unreferenced orange `PointLight2D` pinned to
  one world coordinate washed a large warm glow across the terrain in all player-facing views.
- **Developer beacon in player views:** the fixed-cell beacon marker now draws only alongside
  the other chunk-debug overlays.
- **Streaming deadlocked after loading a save:** `reset()` stopped the generation workers and
  only restarted the render pool, so the first chunk streamed after a load blocked
  `flush_generation()` indefinitely. Reproduced on V4, so it predates the V5 work.
- **Reported and conserved composition disagreed:** `composition_for()` and
  `get_geology_profile()` decoded different, overlapping bit windows of the same 16-bit
  provenance id. V5 worlds now share one decoder.
- **Unreadable check states:** `CheckBox`/`CheckButton` had no authored theme, so an unchecked
  box rendered with no box at all.
- **Entrance shafts capped at chunk boundaries:** a surface entrance leaves its descriptor's
  reach box, so a chunk containing the surface never scanned the deeper descriptor rows whose
  entrances reach up into it. Neighbouring chunks disagreed about the same cell. Covered by a
  cross-chunk agreement check in `tests/v5_worldgen.gd`.
- **Release package could not be built:** `scripts/package_playtest.ps1` used three PowerShell
  7-only APIs while every other repository script runs under Windows PowerShell 5.1, and no
  document stated a PowerShell 7 requirement. Rewritten against APIs both versions provide.
- **Floating food specimens:** vegetation placed a specimen on the first empty cell above
  anything, including tree canopies, which read as dots hanging in the sky.

## P2

- **Windows root certificate diagnostic:** some restricted Windows sessions print exactly `ERROR: Failed to read the root certificate store.` from `platform/windows/os_windows.cpp`. Local simulation, import, tests and packaging do not use TLS; treat it as nonfatal only when the process exits `0` and no subsequent project error exists.
- **Real-device audio remains owner-verified:** automation deliberately uses Godot's `Dummy` driver after the pre-fix procedural mix produced harsh interference. The new 16-bit/seamless/headroom-limited implementation passes structural tests, but subjective speaker/headphone balance must be verified manually at low system volume first.
- **Long soak coverage:** the Phase 13.7 accelerated soak was stopped after the user-approved 60-minute wall-time boundary with stable live memory. Its four-hour terminal checkpoint was not reached in this gate.
- **Synthetic stress scope:** million-active-cell planes, 50k active Pipes and dense synthetic factories are scalability probes rather than supported gameplay promises. Both million-cell planes are now inside the 60 Hz gate (`7.86 ms` Sand, `9.20 ms` Water at eight workers); the scope note stands because the fixtures still are not gameplay.
- **Platform scope:** Web export and multiplayer are architecture documents only. No runtime networking or browser build exists.
- **Advanced content:** chemistry/clay production, farming/survival/combat and Nuclear are post-MVP.

## Operational constraints

- Use `scripts/godot.ps1`; direct Godot execution bypasses the repository-local profile isolation that prevents the known Windows access-violation environment failure.
- Never run automated tests, benchmarks or captures audibly. Use `-MuteAudio`; benchmark/capture flags enforce `Dummy` audio automatically.
- Generated packages, captures, build trees, dependencies, runtime profiles and the safety snapshot are intentionally ignored. Reproduce them with the documented scripts.
