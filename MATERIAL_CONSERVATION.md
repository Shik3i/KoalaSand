# Exact Material Conservation

## Canonical representation

- One full `amount=255` cell is exactly `65,280` micro-mass units.
- One material amount unit is exactly `256` micro-mass units.
- Authoritative arithmetic is signed 64-bit integer arithmetic. Floats never decide mass or yield.
- Mixed sediment contains six exact constituents: silica, iron-bearing, heavy, Gold, clay fines, other.
- Ordinary cells retain the `9 B/cell` base. Generated sediment derives its immutable composition from provenance and mineral signature. Only true mixtures allocate optional composition state.
- `FractionalMassLedger` stores four bounded output channels, every constituent remainder, emitted totals and queued totals. It participates in authoritative hashing and snapshots.

For every split:

```text
sum(input constituent micro-mass)
= sum(emitted physical micro-mass)
 + sum(retained ledger micro-mass)
 + sum(physically queued micro-mass)
```

Completed output quanta that cannot enter the world remain in bounded pending channels. Full storage stops processing. Removing a component with retained mass returns `CONTENTS_PRESENT`; drain it first.

## Production path audit

| SYSTEM | INPUT | OUTPUT | CURRENT CONSERVATION METHOD | RNG? | FRACTIONAL LOSS? | STATUS |
|---|---|---|---|---:|---:|---|
| Raw Sand composition | generated sediment | six constituents | deterministic provenance/signature derivation | generation only | no | conserved |
| Mesh + Vibration | mixed sediment | fines + coarse concentrate | generic four-channel ledger | no | no | component path |
| Riffle wet separation | sediment + real Water flow | heavy concentrate + tailings | density route in generic ledger; Water stays world matter | no | no | component path |
| Electromagnet | mixed concentrate | magnetic + nonmagnetic concentrate | magnetic constituent route in generic ledger | no | no | component path |
| Refractory thermal separation | hot silica/iron sediment | Molten Glass, Molten Iron, Gold, residue | temperature-gated exact constituent split | no | no | component path |
| Legacy Sieve | Raw Sand | Fine/Heavy Sand | deterministic metadata-derived legacy split | no | no | `DEV_FIXTURE` |
| Legacy Magnetic Separator | concentrate | Iron/nonmagnetic output | deterministic metadata-derived legacy split | no | no | `DEV_FIXTURE` |
| Legacy Furnace | material + exposed fuel | thermal products + Ash/Smoke | legacy compatibility path plus physical heat/fuel | no yield RNG | no | `DEV_FIXTURE` |
| Legacy Wash Sluice | sediment + Water | concentrates/tailings | exact compatibility fixture | no | no | `DEV_FIXTURE` |
| Research Bank | Glass/Iron/Gold cell | signed 64-bit Research reserve | one accepted physical cell removed in same operation | no | no | conserved terminal boundary |
| Water/Steam | Water + enthalpy | Ice/Water/Steam | fixed-point mass/enthalpy phase state | no | no | conserved |
| Melting/solidification | Glass/Iron + enthalpy | molten/solid phase | fixed-point latent progress | no | no | conserved |
| Pipes | Water/Steam | transported Water/Steam/leak | integer segment mass; leaks emit physical cells | no | no | conserved |
| Tree fall | generated Tree | detached Wood/Leaves cluster | same material rasterized after motion | no | no | conserved |
| Sediment moisture | Sand + Water | Sand + bound Water | optional bound-water plane; free Water consumed exactly | no | no | conserved |
| Drying | bound Water + heat | Water or Steam | exact bound mass released physically | no | no | conserved |
| Combustion | fuel + oxidizer | Ash + Smoke + heat | generic fractional ledger for sub-cell products | no | no | conserved matter boundary documented |
| Pyrolysis | Wood/Leaves + heat | Charcoal + Smoke | generic fractional ledger | no | no | conserved |
| Cooking | Food + heat/time | Cooked/Burnt Food | material identity transition; mass unchanged | no | no | conserved |
| Gold/Iron extraction | generated constituent mass | pure quantum/concentrate/tailings | exact constituent routing only | no | no | conserved |

Oxidizer and released thermal energy are tracked in their own fixed-point domains. Their reaction stoichiometry is intentionally a simplified gameplay model; no separator or mineral reaction receives free valuable mass.

## Verification contract

- `5% × [1,19,20,21,100,1000]`: exact emitted Gold plus exact retained Gold.
- `1%, 3%, 7%, 12.5%, 33.333...%`: exact input equals emitted plus retained.
- Alternating high/low grade and reversed order: identical final constituent totals.
- `10,000` inputs through Screen → Wet → Magnetic → Thermal: zero per-constituent drift.
- `250,000` inputs across four stages: `1,000,000` split events, zero cumulative drift.
- Mid-fraction snapshot at `95%`, then one `5%` input: exactly one Gold quantum.
- One hundred snapshot cycles: mass, carry, heat, Research and Discovery hashes unchanged.
