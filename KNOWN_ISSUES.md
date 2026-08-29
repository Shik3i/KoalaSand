# Known Issues

Priorities describe engineering risk for continued owner playtesting, not a release schedule.

## P0

None known after the Phase 13.7 verification gate.

## P1

- **Dense synthetic Megafactory:** intentionally pathological density may remain below 100 FPS. It is reported separately from the realistic maximum-factory gate; see [PERFORMANCE.md](PERFORMANCE.md).
- **Manual playtest coverage:** automated captures and state assertions cannot establish subjective controls, readability, audio balance or fun. The owner checklist remains required.

## P2

- **Windows root certificate diagnostic:** some restricted Windows sessions print exactly `ERROR: Failed to read the root certificate store.` from `platform/windows/os_windows.cpp`. Local simulation, import, tests and packaging do not use TLS; treat it as nonfatal only when the process exits `0` and no subsequent project error exists.
- **Restricted-session audio fallback:** rendered automation on this host can print `ERROR: WASAPI: init_output_device error.` followed by `WARNING: All audio drivers failed, falling back to the dummy driver.` Interactive owner sessions must still verify real audio; automated rendering remains valid when the process exits `0`.
- **Long soak coverage:** the Phase 13.7 accelerated soak was stopped after the user-approved 60-minute wall-time boundary with stable live memory. Its four-hour terminal checkpoint was not reached in this gate.
- **Synthetic stress scope:** million-active-cell planes, 50k active Pipes and dense synthetic factories are scalability probes rather than supported gameplay promises.
- **Platform scope:** Web export and multiplayer are architecture documents only. No runtime networking or browser build exists.
- **Advanced content:** chemistry/clay production, farming/survival/combat and Nuclear are post-MVP.

## Operational constraints

- Use `scripts/godot.ps1`; direct Godot execution bypasses the repository-local profile isolation that prevents the known Windows access-violation environment failure.
- Generated packages, captures, build trees, dependencies, runtime profiles and the safety snapshot are intentionally ignored. Reproduce them with the documented scripts.
