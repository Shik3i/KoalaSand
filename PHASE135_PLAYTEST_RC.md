# KoalaSand Phase 13.5 Playtest RC

> **HISTORICAL PHASE REPORT:** Superseded by the `0.1.0-playtest.2` Phase 13.6/13.7 baseline.

Version: `0.1.0-playtest.1`
Engine: Godot `4.7.1.stable.official.a13da4feb` through `scripts/godot.ps1`
Scope: Phase 13.5 only; Phase 14 not started.

## Verification result

- Native Release build: PASS.
- Clean Godot import: PASS.
- Historical correctness, native goldens and worker parity: PASS.
- Phase 13.5 correctness: `53` checks PASS.
- Save abuse: `314` checks PASS across `100` serialize/load/hash cycles.
- Package boot outside repository: PASS, exit `0`.
- Packaged full-game scene smoke: PASS, exit `0`.
- Packaged Factory benchmark: `491.4 FPS`, frame avg/p95/p99/worst `2.027/2.083/2.083/4.010 ms`.
- Only recurring nonfatal diagnostic: `ERROR: Failed to read the root certificate store.`

## Player presentation

- Searchable data-driven Physics Codex: `122` entries, history, related links, contextual Inspector navigation and Character hidden-information policy.
- Tiered physical Inspector: interpreted summary, physical failure causes, optional advanced detail.
- Planning Pause: authoritative clock and Character physics frozen; camera and static construction UI remain usable.
- Action toolbar separated from ten-page Component/Blueprint Quickbar.
- Blueprint library distinguishes `EXAMPLE` and `PLAYER`; copied example geometry can be modified and resaved without hidden identity.
- Compact current goal and eight optional authoritative-state Experiments.
- Central procedural audio mixer: fixed pools, five categories, bounded spatial aggregation; no third-party audio.
- Pooled state-driven VFX with Reduced Motion.
- Release-facing Save Browser, explicit backup recovery, autosave status and local diagnostics export.

## Performance

- 1M active Sand, 8 workers: avg/p99 `10.3011/11.1580 ms`.
- 1M active Water, 8 workers: `9.0128/9.9210 ms`.
- 1M active thermal, 8 workers: `7.4633/14.4520 ms`.
- 1M active Steam, 8 workers: `7.6515/7.9930 ms`.
- 50k active Steam Pipes: `2.3875/9.2940 ms`.
- 256k atmosphere: `1.9135/3.1560 ms`.
- 100k synthetic burning cells: `8.9787/21.3410 ms`; documented unrealistic tail.
- 1M warm Smoke: `3.0730/10.5480 ms`.
- Realistic fires p99: campfire `0.2210`, charcoal chamber `0.2880`, 20 trees `0.6260`, 100 trees `0.9060`, industrial 5k cells `2.2040 ms`.
- Project Character/Factory/Creative: `365.5/397.3/403.0 FPS`.
- Dense synthetic Megafactory: `51.0 FPS`; non-blocking stress fixture, below the representative-gameplay gate.
- Codex search: avg/p99 `0.3442/0.4760 ms`.
- Audio representative: `0.0383/0.0690 ms`; 300-source stress `0.7470/0.7920 ms`; `74,160` requested contributions aggregated to `5` loops.
- VFX: avg/p99 `0.0269/0.0560 ms`.
- Save capture/write/load: `0.310/14.271/2.172 ms`.

## Session and soak evidence

- Deterministic progression: first Research `6m`, first separation/concentrate `12m`, Automation `24m`, Water `29m`, Steam `43m`, Electricity `56m`, Powered Factory `60m`.
- 60-minute-plus real-time mixed-system soak: no assertion/error, process remained responsive; externally observed Working Set stable at `103,702,528–103,706,624` bytes.
- The requested 4h run was stopped after the user explicitly accepted the 60-minute mark. No 2h/4h checkpoint assertion is claimed.
- Save abuse covers Tree fall, Wood fire, oxygen depletion, Steam, Molten Glass, moving Water, 95% Gold carry, changing Automation, split Power, rotating Shaft and completed Blueprint placement.
- 95% Gold carry survives 100 round-trips; the next 5% input emits exactly one Gold quantum with remainder `0`.

## Visual and display QA

- Twenty-five required 1920×1080 captures generated under `artifacts/phase135` and inspected.
- Additional 1600×900 Settings and 2560×1440 Codex captures inspected; scrollable layouts prevent critical clipping.
- Visual QA fixed clipped Codex/Pause centering and a diagnostic-capture refresh issue.

## Known release risks

1. No human blind playtest yet; automated fixtures cannot prove first-time comprehension.
2. 2h/4h soak checkpoints were waived/stopped at 60+ minutes; extended stability remains unproven.
3. Synthetic dense Megafactory measured `51.0 FPS`; ordinary Character/Factory remain far above `100 FPS`.
4. Component world art is intentionally compact; several wall/vessel silhouettes remain most distinguishable by internal pattern plus context at distant zoom.
5. Windows package is unsigned and uses minimal procedural audio; no soundtrack.
