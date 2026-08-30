# Known Issues

Priorities describe engineering risk for continued owner playtesting, not a release schedule.

## P0

None known after the Phase 13.9 verification gate.

## P1

- **Dense synthetic Megafactory:** intentionally pathological density measured `43.7 FPS`, `25.000 ms` p95 and `27.905 ms` p99 on the Phase 13.9 host. It is reported separately from the realistic maximum-factory gate; see [PERFORMANCE.md](PERFORMANCE.md).
- **Manual playtest coverage:** automated captures and state assertions cannot establish subjective controls, readability, audio balance or fun. The owner checklist remains required.

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
