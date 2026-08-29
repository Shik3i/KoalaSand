# Production thermodynamics

Phase 9 replaces the isolated Phase-8.5 candidate with deterministic production thermodynamics. `NativeSandWorld` is authoritative. Godot renders state and submits ordered commands; it does not calculate heat, phase transitions, Pipe pressure, or material conversion.

## Units and material contract

Temperature is stored as unsigned quarter-kelvin (`uint16`): `1092 = 273 K`, `1492 = 373 K`. All authoritative heat and enthalpy arithmetic is fixed-width integer arithmetic. Material definitions are stable data indexed by material ID.

| ID | Material | Phase | Conductivity | Specific heat | Density | Mobility | Transition | Latent heat |
|---:|---|---|---:|---:|---:|---:|---|---:|
| 3 | Water | liquid | 48 | 128 | 1000 | 255 | freeze `1092`, boil `1492` | `12000`, `42000` |
| 10 | Glass | granular solid | 24 | 40 | 2500 | 0 | melt `5873` | `20000` |
| 11 | Iron | granular solid | 192 | 56 | 7870 | 0 | melt `7245` | `16000` |
| 16 | Ice | solid | 80 | 64 | 917 | 0 | melt `1092` | `12000` |
| 17 | Steam | gas | 20 | 32 | 1 | 255 | condense `1492` | `42000` |
| 18 | Molten Glass | molten | 28 | 48 | 2350 | 4 | solidify `5873` | `20000` |
| 19 | Molten Iron | molten | 160 | 64 | 7000 | 12 | solidify `7245` | `16000` |

Water, Ice, Steam, molten Glass, and molten Iron use the generic local `material_amount` value `1..255`. Heat capacity and latent capacity scale with amount. Provenance and mineral signature survive phase changes and material motion.

## Enthalpy and phase transitions

Each cell resolves from one conserved enthalpy value:

```text
enthalpy = phase_base + sensible_heat + signed_latent_progress
sensible_heat = amount_scaled_heat_capacity * temperature
```

Heating reaches the transition temperature, fills latent progress at constant temperature, then changes material identity and resumes sensible heating in the new phase. Cooling follows the exact inverse path. The implementation records fractional integer loss in the signed world-level `thermal_rounding_reservoir`; it is part of authoritative hashing and conservation accounting.

Heat exchange is pairwise and conservative. A tick reads a stable source state, accumulates bounded integer transfers into reusable scratch, merges in deterministic order, then resolves enthalpy and phase changes. The physical Radiant Furnace injects heat into nearby matter and Pipe contents. It owns no input slot, recipe timer, or output inventory. Thermal Switches gate conduction locally; Heat Exchangers transfer heat between their external ports without moving matter.

Natural diffusion and phase laws are always active. Research unlocks measurement and construction tools, never the laws of nature.

## Activity, parallelism, and memory

Production cadence: `30 Hz`. Each `64x64` chunk has deterministic active-row spans for current and next thermal work. Stable uniform regions visit zero cells. Cross-chunk fronts wake only the required boundary region. `ParallelExecutor` is persistent and shared; supported validation workers are `1`, `2`, `4`, and `8`. Authoritative output is worker-count invariant.

Persistent base world storage remains `9 bytes/cell`. Additional thermal/mobile state is lazy:

| State | Cost | Lifetime |
|---|---:|---|
| material amount | `4096` bytes/chunk | allocated only when values differ from implicit full/empty |
| phase energy | `8192` bytes/chunk | allocated on latent/remainder state; released after stable empty state |
| thermal activity | `272` bytes/chunk | two `FluidActivity` span sets |
| thermal transfer scratch | `32768` bytes/working chunk | two reusable `int32[4096]` arrays; released after sleep |

Steam and molten material reuse the generic amount plane and shared fluid activity. There is no Steam-specific world plane. Active masks, scratch, edge buffers, render caches, and work queues are derived and must not be serialized.

## Determinism and persistence boundary

Authoritative state includes material ID, amount, temperature, phase progress/direction, provenance, mineral signature, Pipe fluid/temperature/phase progress, Thermal Switch state, and `thermal_rounding_reservoir`. Stable IDs and schema migrations are mandatory. Generated activity, schedulers, scratch, and visual pages are rebuilt after load.

Normal mutations use `WorldCommand`, including `SET_MATERIAL_STATE`, `SET_PIPE_FLUID`, and `SET_THERMAL_SWITCH`. Replay validation covers different worker counts and exact physical/automation hashes.

## Explicit limits

This is deterministic game thermodynamics, not a scientific CFD or equation-of-state solver. There is no radiation field, combustion chemistry, electricity, turbine, generator, nuclear system, advanced chemistry, player character, networking, or full save/load in Phase 9.

## Phase 9.5 boundary

Steam and Pipe optimizations preserve exact family mass, total enthalpy and every Phase-9 replay/worker hash. The Pipe conversion lookup precomputes mass-dependent heat capacities/latent budgets only; authoritative temperatures, phase progress and rounding remain unchanged. Future Turbines must remove energy from actual inlet Steam, retain its mass in lower-energy exhaust, and transfer accounted energy through a compact mechanical boundary. Electrical distribution is intentionally abstract and is defined separately in `POWER_ARCHITECTURE.md`; no Phase-10 conversion exists yet.

## Phase 12 organic heat and vessels

Reactive activation is sparse and restricted to combustible cells; normal Water, Steam and nonreactive thermal fields do not enter the organic scheduler. Moisture evaporation consumes energy and emits conserved Water/Steam. Combustion adds configured energy to the same enthalpy system. Iron Pot transfer coefficient `16` versus Ceramic test coefficient `2` produced cavity Water temperatures `1492` versus `1231` after identical two-tick exposure. Boiling remains the normal Water/Steam phase transition.

## Phase 13 constituent reactions

Only actual silica-bearing and iron-bearing micro-mass can become Molten Glass or Molten Iron. A hot sediment cell adjacent to Refractory geometry enters the generic exact ledger; nonparticipating constituents remain Gold/concentrate/residue carry. Cooling uses the existing fixed-point phase-change path. Metal and Ceramic/Refractory component properties differ in conductivity and heat capacity; there is no Pot/Furnace/Boiler recipe branch.
