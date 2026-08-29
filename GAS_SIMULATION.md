# Gas simulation

Phase 9 adds the production gas path to the unified mobile-matter solver. Steam is currently the only gas material. This document defines the generic scheduling and movement contract; `STEAM_AND_GASES.md` defines Steam/Pipe gameplay.

## State and rules

Gas identity remains the ordinary stable material ID. Amount is the lazy generic `uint8` amount plane (`1..255`), temperature is the base `uint16` quarter-kelvin cell field, and latent progress uses the optional phase-energy plane. No gas particle objects, gas graph, global chamber inventory, or separate persistent Steam plane exists.

Local deterministic priority is buoyant/upward motion, upward diagonal opportunity, lateral amount equalization, then bounded downward equalization when local concentration requires it. Full and partial cells preserve proportional enthalpy. Solids and solid structures block gas. Barrier changes, new gas, transfers, temperature/phase changes and cross-chunk arrivals wake only local activity spans.

## Scheduling and sleep

Gas jobs reuse `FluidActivity`, `ParallelExecutor`, immutable phase inputs, worker-local results and deterministic commit order. The same worker policy supports `1`, `2`, `4`, and `8` workers with identical authoritative hashes. Cross-chunk destinations use the normal chunk halo and ordered border accounting.

Movement activity is independent from thermal activity. A sealed, equalized Steam region reaches zero active gas cells even if a remaining temperature gradient keeps thermal work alive. Shader animation may continue without waking simulation.

## Phase 9.5 hot path

Local transfers now carry source/destination chunk and index references through the hot path instead of repeating world-to-chunk hash lookup. Scheduling/traversal/commit/sleep and per-worker jobs/cells/time are separately instrumented. There is no per-cell heap state or per-tick thread creation. Exact Phase-9 hashes are unchanged.

The production 1M active fixture on eight workers is `7.1305 ms` average, `7.3640 ms` p95 and `7.6590 ms` p99 after one explicitly reported `16.4930 ms` construction/cold-start tick. The same 32-tick hash is `47e74da4` for workers `[1,2,4,8]`. A sealed 1M Steam field reaches zero visited work (`0.0358 ms` whole tick in the historical matrix).

## Pressure limit

World gas uses local finite-amount equalization, not a scientific pressure field. Enclosed Pipe Steam adds a local temperature/fill pressure approximation documented in `STEAM_AND_GASES.md`. Full compressible CFD, mixtures, pressure-dependent boiling curves and a scientific equation of state remain future work.

## Phase 12 Smoke and oxidizer

Smoke material `24` is finite gas in the existing world-gas solver: it rises, spreads, crosses chunks, transports mass/temperature and sleeps. Ambient oxidizer is implicit `255`. Only disturbed chunks allocate a `4096 B` oxidizer plane; dense Smoke/Steam displaces it. Four-neighbor diffusion and an open-surface ambient boundary replenish openings while sealed disturbed spaces retain depletion. This is a combustion boundary, not breathing or atmospheric chemistry.
