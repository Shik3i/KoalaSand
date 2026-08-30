# Status

## Current baseline

- Version: `0.1.0-playtest.4`.
- Scope: Phase 13 MVP through Phase 13.9 first-time-player experience and UX coverage.
- Branch: `main`.
- Engine: `Godot 4.7.1.stable.official.a13da4feb`; repository wrapper required.
- Native: C++20 GDExtension, pinned `godot-cpp` commit `5ed72a0dc2517a8082598a950895c6b24e8aa282`.
- Distribution status: owner playtest candidate; no tag, GitHub Release or PR.

Phase 13.8 retains the reviewed Phase 13.7 Git baseline and prepares a new owner-playtest package. The remote verification record is completed by the Phase 13.8 Git operation and its final report; this source document intentionally does not embed a self-referential commit SHA.

## Implemented

- One deterministic chunked physical world: granular matter, divisible liquids, gases, temperature, phase changes, atmosphere, combustion and organic reactions.
- Deterministic WorldGen V2, finite boundaries, async streaming, pristine eviction, 100k-seed validation path and owner visibility/discovery.
- Physical factory construction: Conveyors, storage geometry, Pumps, spatial Pipes, local damage/leaks, subsurface routes and editable component Blueprints.
- Exact six-constituent fixed-point composition and fractional carry across dry, wet, magnetic, thermal, organic and deconstruction boundaries.
- Physical Steam power, shafts, generators, cached electrical networks, priority/brownout behavior and automation.
- Factory, Character and Creative capability presets over identical simulation rules.
- Research, milestones, onboarding, Main Menu, Save/Load/autosave/backup recovery, Codex, Map, Inspector, overlays and diagnostics.
- Procedural bounded audio, pooled VFX and batched rendering.

## Phase 13.7 hardening

- Comprehensive `.gitignore`, safety snapshot and generated-artifact cleanup.
- Machine-independent Godot launcher discovery and safe clean native build.
- Canonical full test and benchmark scripts; meaningful native `ctest`.
- Maximum practical warnings for owned C++ without third-party warning floods.
- Transactional native snapshot validation before world mutation.
- Save envelope size/shape/checksum/trailing-byte guards, Windows-safe names and serialized same-path writes.
- Command, batch and Blueprint shape/count/type limits.
- Signed-coordinate, rectangle-end and work-size overflow guards.
- Worker stop/join before world storage teardown or reconfiguration.
- Adversarial save, command, Blueprint, coordinate, conservation, WorldGen and UI-state tests.

## Phase 13.8 player-experience polish

- Safe 16-bit procedural audio, seamless periodic loops, filtered one-shots, fixed bus headroom and smoothed loop gain/pitch.
- Automated Godot runs are explicitly silent and captures remain strictly sequential.
- Native parallel reactive-cell changes commit after the worker barrier, eliminating the reproduced eight-worker heap corruption.
- Unified modal entrance/exit motion, Reduced Motion bypass, reliable `Esc` ordering and correct modal-lock release.
- Visible Map close action, readable Experiments cards, improved Component/Power/Steam presentation and distinct Main Menu/New Game states.
- Two complete visual passes, `43` final captures, UI/gameplay/world-physics contact sheets and `1600×900`/`2560×1440` verification.

## Phase 13.9 first-time-player experience

- Central rich tooltip, control-attached highlight and bounded toast systems.
- Physical help coverage for MVP Components, materials, Automation, Inspector properties and common blockers.
- Factory, Character and Creative first-use paths with persistence, reset, disable and legacy-profile migration.
- Live Controls help, onboarding settings, mode explanations, Research legend/unlock feedback, Blueprint annotations and actionable empty states.
- Automated clean-state FTUE coverage plus sequential silent capture and packaged-profile gates.
- Final verification: `27/27` correctness scripts, `329` focused FTUE checks, `148` audited surfaces, `30` final captures and a `599.983 s` representative smoke.

## Verification commands

```powershell
.\scripts\build_native.ps1 -Clean
.\scripts\godot.ps1 --headless --editor --path . --quit
.\scripts\test.ps1
.\scripts\benchmark.ps1
.\scripts\benchmark.ps1 -IncludeRuntime
.\scripts\package_playtest.ps1
```

Exact current measurements belong in [PERFORMANCE.md](PERFORMANCE.md); repository findings belong in [REPOSITORY_AUDIT.md](REPOSITORY_AUDIT.md). The recurring Windows diagnostic `ERROR: Failed to read the root certificate store.` is nonfatal and recorded in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

## Remaining boundaries

- Advanced chemistry/clay processing, farming/survival/combat, Nuclear, networking and Web export are post-MVP.
- Dense synthetic stress fixtures are scalability evidence, not intended gameplay density.
- Manual owner playtesting remains necessary for subjective controls, readability and audio mix.
- No telemetry or online service is implemented.

## Operational rule

Never invoke Godot directly for this repository. Use `scripts/godot.ps1`; it pins 4.7.1 and isolates writable profile/log state under ignored local directories. Use `-MuteAudio` for every automated invocation.
