# Known Issues

Priorities describe engineering risk for continued owner playtesting, not a release schedule.

## P0

None known after the Phase 13.9 verification gate.

## P1

- **Dense synthetic Megafactory:** intentionally pathological density measured `43.7 FPS`, `25.000 ms` p95 and `27.905 ms` p99 on the Phase 13.9 host. It is reported separately from the realistic maximum-factory gate; see [PERFORMANCE.md](PERFORMANCE.md).
- **Manual playtest coverage:** automated captures and state assertions cannot establish subjective controls, readability, audio balance or fun. The owner checklist remains required.

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
- **Synthetic stress scope:** million-active-cell planes, 50k active Pipes and dense synthetic factories are scalability probes rather than supported gameplay promises.
- **Platform scope:** Web export and multiplayer are architecture documents only. No runtime networking or browser build exists.
- **Advanced content:** chemistry/clay production, farming/survival/combat and Nuclear are post-MVP.

## Operational constraints

- Use `scripts/godot.ps1`; direct Godot execution bypasses the repository-local profile isolation that prevents the known Windows access-violation environment failure.
- Never run automated tests, benchmarks or captures audibly. Use `-MuteAudio`; benchmark/capture flags enforce `Dummy` audio automatically.
- Generated packages, captures, build trees, dependencies, runtime profiles and the safety snapshot are intentionally ignored. Reproduce them with the documented scripts.
