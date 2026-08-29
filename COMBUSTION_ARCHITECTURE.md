# Combustion Architecture

Combustion is a sparse thermal reaction over real materials, local oxidizer and physical products. It is not a furnace recipe or visual timer.

## Research basis

The cellular-fire model in [Sullivan et al., a coupled cellular automata fire model](https://pmc.ncbi.nlm.nih.gov/articles/PMC7302257/) separates solid pyrolysis, released volatiles, gas combustion and heat transfer. KoalaSand deliberately uses a smaller gameplay model, but preserves the important boundaries: heat-driven activation, oxygen-limited conversion, gas products and feedback of released heat. [The Powder Toy](https://github.com/The-Powder-Toy/The-Powder-Toy) additionally validates keeping heat, gases and reacting substances in one cellular world.

No source code was copied and no claim of industrial-chemistry accuracy is made.

## Atmosphere

Empty/open cells implicitly contain oxidizer `255`; no air plane exists in an untouched chunk. The first local disturbance allocates a `4096 B` `uint8` plane and initializes Empty to 255, dense solid to 0, and gas to `255 - gas_mass`.

Disturbed chunks diffuse deterministically through four neighbors. Surface-open cells relax toward the external ambient reservoir. A sealed disturbed enclosure does not reset to ambient. Dense Steam or Smoke displaces oxidizer through the same gas occupancy rule. Uniform state sleeps by leaving the disturbed-chunk set.

This model is strictly for combustion. Character breathing, poisoning and weather are out of scope.

## Sparse reaction state

Only reactive cells enter `reactive_cells_`. Their chunk lazily allocates `uint16 ReactionProgress` plus `uint8 OrganicReactionState`: `NONE`, `DRYING`, `BURNING`, `PYROLYZING`, `COOKING`, or `BURNING_FOOD`. Thermal updates activate this path only for combustible matter; nonreactive Water, Steam and thermal fields pay no reaction hash-set cost.

No runtime RNG participates. Stable cell-key order plus fixed-point rates makes results independent of worker count.

## Drying and ignition

Bound moisture absorbs real thermal energy. At sufficient temperature, up to two moisture units per reaction step leave the Wood as Water or Steam; remaining moisture plus emitted Water-family mass equals initial bound moisture.

Ignition requires material temperature at/above its data threshold and a neighboring oxidizer value at/above `72`. The Igniter only adds `24,000,000` energy and wakes the cell; it cannot set a burning flag.

## Open combustion

Each successful step:

1. computes bounded fuel mass from material burn rate;
2. requires and consumes local oxidizer;
3. reserves physical capacity for Ash and Smoke;
4. emits both products into nearby world cells;
5. removes exactly the converted fuel mass;
6. injects `fuel × combustion_heat` into the normal thermal system;
7. heats/wakes cardinal neighbors.

If products cannot fit, conversion stalls; nothing is deleted. Flame spread occurs only through transferred heat. Fire ends through exhausted fuel, insufficient oxidizer, cooling or blocked products. Flame geometry is a batched visible-state overlay with reduced-motion support; Smoke remains actual gas matter.

## Pyrolysis and Charcoal

Wood/Leaves above their pyrolysis threshold with oxidizer below `72` advance the same ReactionProgress plane. On completion, Wood mass becomes a fixed Charcoal fraction plus physical Smoke; temperature is preserved. In the canonical Wood definition, `96/255` becomes Charcoal and the remainder becomes Smoke. A Stone enclosure with a restricted opening therefore functions as a kiln without a dedicated machine or recipe.

Charcoal ignition is hotter (`2692` quarter-kelvin), energy is `24000/mass`, and burn rate is `2`, versus Wood `12000/mass` and rate `4`. Physical Coal, Wood and Charcoal are the three generic furnace fuels. The Radiant Furnace scans exposed fuel in its open bay, transfers its stored energy into nearby matter, and relies on this reaction system for fuel loss and exhaust.

## Conservation and determinism

Correctness fixtures cover open ignition, blocked products, oxygen starvation, diffusion/replenishment, Steam suppression, moisture, combustion mass, combustion energy, pyrolysis yield/temperature, Charcoal fuel behavior, Smoke/gas parity and worker `[1,2,4,8]` hashes. Authoritative hashing includes organic amount, temperature, moisture, oxidizer, reaction progress and detached-cluster state.

Phase 13 routes sub-cell Ash, Smoke and Charcoal through the same generic `FractionalMassLedger` used by mineral processing. Product-capacity checks sleep blocked reactions until adjacent state changes. Cached surface heights, neighbor chunks and direct plane access remove redundant atmosphere lookups while preserving deterministic hashes.
