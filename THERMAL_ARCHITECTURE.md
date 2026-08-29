# Thermal Architecture Candidate

> **HISTORICAL ARCHITECTURE GATE:** This is the isolated pre-production candidate. Current behavior is defined by `THERMODYNAMICS.md`, `PHASE_CHANGES.md` and `STEAM_AND_GASES.md`.

## Gate boundary

Phase 8.5 contains an isolated deterministic prototype, material traits, benchmark fixtures, and a generic heat-source boundary. It does not enable production diffusion, phase changes, Steam, Ice, molten metal, gas, chemistry, or Phase 9 gameplay. The existing Radiant Furnace still applies its Phase-6.5 local behavior through `NativeHeatSource`; it is not a black-box recipe processor and does not silently invoke the prototype.

## Research basis

- [Explicit finite-difference diffusion](https://www.osti.gov/servlets/purl/420369) is stable only under a bounded time-step/coefficient relationship; the prototype uses deliberately conservative integer coefficients and fixed substeps.
- [Enthalpy methods](https://hal.science/hal-03480899v1/file/2108.13253.pdf) are the future phase-change direction because latent heat can be represented without discontinuous temperature jumps.
- [Noita](https://noitagame.com/) demonstrates the design value of cell materials; its public [temperature](https://noitagame.com/release_notes/20201015/) and [surface-reaction](https://noitagame.com/release_notes/20201022/) descriptions are design evidence only—not an implementation specification.

## State and material properties

Candidate temperature is the production `uint16` quarter-kelvin value. Each material supplies fixed integer conductivity and volumetric heat capacity. Water capacity is scaled by its local `uint8` mass; Empty has zero conductivity and capacity, so it does not conduct. A future weak ambient/radiative term must be explicit and separately budgeted.

The pair exchange between adjacent occupied cells is conceptually:

```text
energy = bounded_conductance(a, b) * (temperature[a] - temperature[b])
delta_temperature = energy / local_heat_capacity
```

Implementation uses wide integer energy and a normalized conservative remainder path. Pair energy removed from one side is added to the other exactly. No authoritative floating point is used.

Current candidate traits:

| Material | Conductivity | Capacity | Candidate transition threshold |
|---|---:|---:|---:|
| Stone | 64 | 48 | none |
| Raw Sand | 32 | 32 | none |
| Water | 48 | 128 x mass fraction | freeze `1092`, boil `1492` |
| Iron | 192 | 56 | melt `7245` |
| Glass | 24 | 40 | soften/melt `5873` |

Thresholds are inert metadata in this gate.

## Activity and scheduling

Each candidate chunk owns active-row masks plus min/max spans. A cell wakes when its temperature differs from an occupied neighbor by at least `2` units (`0.5 K`), when a source changes it, or when a cross-chunk neighbor wakes it. Stable uniform regions visit zero cells. Frontier propagation is local; there is no full-world temperature scan.

Cross-chunk edges are collected in deterministic coordinate order. Workers read one immutable temperature snapshot and write job-local deltas/edge transfers. Delta application uses fixed job order; no cell mutex and no schedule-dependent reduction exists. `ParallelExecutor` supplies workers `1/2/4/8`; single-thread runs the same phases.

Heat sources use stable IDs, rectangular regions, target temperature, rate, and enabled state. Disabled sources are filtered before cell work. Future fire, sunlight, hot Pipes, molten material, or cooling blocks must enter through this boundary rather than special-case black boxes.

## Benchmark evidence

All worker counts produce hash `b4fa08fdef15f99b` on the 64k parity fixture.

| Active cells | 1 worker | 2 workers | 4 workers | 8 workers |
|---:|---:|---:|---:|---:|
| 65,536 | 1.2810 ms | 0.6443 ms | 0.3663 ms | 0.2390 ms |
| 262,144 | 4.8122 ms | 2.7282 ms | 1.2809 ms | 0.7506 ms |
| 1,048,576 | 20.4635 ms | 9.9211 ms | 5.1777 ms | 2.8432 ms |

Sparse hotspot: `1,220` active/visited, `952` exchanges, `0.0573 ms`. Cross-chunk boundary: `8,192` active/visited, `5,120` exchanges, `0.3863 ms`. Uniform 1M: `0` active/visited/exchanges, `0.001125 ms`.

One-million active memory: activity `6,299,648` bytes; worker scratch `8,388,608` bytes. Scratch is reusable temporary memory, not save state. Candidate full-grid temperatures are benchmark storage only; production would reuse chunk temperatures.

The representative 40k-infrastructure fixture with 12 machines and 40 automation components runs `444.3 FPS` without the candidate and `417.1 FPS` with candidate cadence `30 Hz`. Candidate thermal cost: `0.3579 ms` average, `5,008` active/visited, `5,056` exchanges. Recommended cadence: `30 Hz`; it halves thermal tick count versus 60 Hz while avoiding the visible/coarse response of 15 Hz.

## Future phase-change contract

Production phase transitions require conserved enthalpy: sensible energy first, then latent phase energy at the threshold, then the next phase temperature. Material identity changes only after latent capacity is satisfied. Water/Ice/Steam density, pressure, expansion, condensation, Pipe heat exchange, Pipe rupture, molten-metal flow, casting, and cooling are separate future acceptance gates. None is implemented here.

## Determinism and persistence

Authoritative snapshots will eventually persist cell temperature, phase-energy/enthalpy state, and enabled heat-source state. Active masks, work queues, edge buffers, and worker scratch are derived caches and must not be serialized. Multiplayer remains ordered commands plus deterministic derived thermal state, periodic hashes, and localized chunk correction.

## Phase 9 promotion

This document preserves the Phase-8.5 preflight and its historical measurements. Phase 9 supersedes its non-production boundary. Production diffusion, enthalpy/latent progress, Ice/Water/Steam, molten Glass/Iron, world/Pipe heat exchange, local Steam pressure/failure, Thermal Switches and Heat Exchangers are now implemented. The canonical production contract and current memory/benchmark evidence are in `THERMODYNAMICS.md`, `PHASE_CHANGES.md`, `STEAM_AND_GASES.md`, and `PERFORMANCE.md`.
