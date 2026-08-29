# Physical Sandbox Roadmap

Phase 11.5 defines boundaries only. It implements no Tree, Wood, Fire, Charcoal, Cooking, Food, Pot, Health, Death, enemy, or combat gameplay.

## Future physical chain

### Tree felling

Trees should be spatial structures with support, local damage, mass, and deterministic fracture/fall output. Felling must create world-space Wood matter; it must not credit a hidden inventory or timed recipe.

### Wood

Wood should preserve origin/provenance and bounded material state such as amount, temperature, and moisture where those states become gameplay-relevant. Conveyors, bins, impact, Water, heat, and fire should interact through existing matter/structure/thermal contracts.

### Fire, pyrolysis, and Charcoal

Combustion should consume a physical oxidizer/fuel interface, release heat and gas locally, propagate through bounded active fronts, and leave conserved products. Charcoal should emerge from low-oxygen thermal decomposition of Wood, not a Furnace recipe slot. Exact chemistry and gas species require a separate architecture/performance gate.

### Metal cookware and casting

Cookware should be physically cast or formed from existing molten-metal/solidification systems. A vessel's geometry, material, temperature, capacity, leakage, and contact surfaces should matter; it must not become an abstract cooking machine inventory.

### Water heating and thermal cooking

Water heating must use the existing conserved enthalpy and phase-change model. Food/cooking, if authorized later, should depend on time-temperature exposure, contact, moisture, and vessel geometry. Heat sources act on matter and vessels; no hidden progress bar may replace the thermal state.

## Integration boundaries

- authoritative state remains native, deterministic, chunked, and fixed-tick;
- new hot fields require measured memory and active-front scheduling;
- structures fail locally and release their actual contents;
- provenance survives motion and transformation where physically meaningful;
- rendering/UI consume state and never author simulation outcomes;
- Research unlocks tools and structures, not natural physical laws.

## Phase 12 implemented boundary

Physical organic interactions now follow these contracts. WorldGen V2 Trees become fixed-point `FellableCluster` records only while detached, then rasterize to normal Wood/Leaves. Optional moisture, oxidizer and reaction planes preserve the `9 B/cell` base. Open combustion and low-oxygen pyrolysis create real Smoke/Ash/Charcoal; the Furnace consumes exposed physical fuels. Open Iron Pots prove generic conduction, Water boiling and temperature-time Food conversion without recipes. Survival, farming, weather, combat and advanced chemistry remain deferred.

## Phase 13 freeze

The MVP replaces player-facing processing prefabs with Mesh, Riffle, walls/plates, Grate, Insulator, Vibration Actuator, Electromagnet and Blower components. Legacy Furnace/Sieve/Magnet/Sluice/Pot structures remain hidden `DEV_FIXTURE` compatibility objects only. Advanced clay forming, chemistry, farming, survival, combat, Multiplayer and Web remain post-MVP. `MVP_SCOPE.md` is authoritative.
