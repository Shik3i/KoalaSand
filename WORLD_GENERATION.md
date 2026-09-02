# World Generation

> **HISTORICAL / SUPERSEDED:** Phase 2 generator contract. Current generation is WorldGen V2; see `WORLD_GENERATION_V2.md` and `WORLDGEN_VALIDATION.md`.

## Contract

The Phase 2 world is finite and deterministic. Defaults:

| Axis | Inclusive range |
|---|---:|
| `x` | `-8192..8191` |
| simulated `y` | `-512..4095` |
| nominal surface | near `y = 0` |
| immutable bottom shell | final `8` rows |

Above `y = -512` is Empty. Horizontal overflow and `y >= 4096` read as Bedrock. An in-bounds but ungenerated cell reads as guarded material `-1`; it is never interpreted as Empty or writable world matter.

`generation_version = 1` plus the exact world settings and seed define generated content. Generation uses integer coordinate hashing, interpolated value noise, and fBM only. No global RNG, frame time, worker ID, request order, or generation order participates.

## Terrain stages

Each worker generates one complete `64×64` chunk into private arrays:

1. Three continuous one-dimensional noise bands create broad elevation, medium terrain, and fine relief around `surface_baseline`.
2. The first `sediment_depth` rows below the surface become Raw Sand.
3. Warped two-dimensional fBM carves coherent caves below the sediment safety band.
4. A second continuous field fills uncommon deep cave basins with static Water.
5. Deposit and seam fields replace portions of intact deep Stone with solid Coal.
6. The final eight world rows become Bedrock.

All fields sample global world coordinates, never chunk-local coordinates. Adjacent chunks therefore share the same mathematical field and require no seam repair pass. Golden region hashes in `tests/phase2_correctness.gd` protect the exact v1 output.

## Geology and provenance

Raw Sand carries one `uint16` provenance profile ID per cell. The ID is a stable packed quantization, not an insertion index:

| Bits | Meaning |
|---:|---|
| `0..4` | silica bucket |
| `5..9` | iron bucket |
| `10..12` | heavy-mineral bucket |
| `13..15` | rare gold-anomaly bucket |

Decoding returns `silica_fraction`, `iron_fraction`, `heavy_minerals_fraction`, `other_fraction`, and `gold_ppm`. Primary fractions are normalized so all four fractions sum to `1.0`; gold is separately expressed in ppm. Adjacent cells usually share an ID because the source fields are regional. Gold buckets are activated only above a high coherent-field threshold, making them uncommon and spatially clustered.

The provenance ID and Phase 4 mineral signature move atomically with geological granular matter. The signature hashes seed, generation version, original coordinate, and stable salt; no original coordinate is stored. Processing intermediates, products, and Crude Residue retain both fields. `material_and_provenance_hash()`, processing hashes, and cross-chunk tests detect loss or reassignment.

Production simulation storage remains `9 bytes/cell`: material `uint16` (`2`), absolute quarter-kelvin temperature `uint16` (`2`), flags `uint8` (`1`), provenance `uint16` (`2`), and mineral signature `uint16` (`2`). The API still returns signed `-1` for ungenerated guarded space. RGBA presentation remains a separate `4 bytes/cell`.

## Streaming and publication

The camera requests three priorities: center/simulation halo `0`, visible `1`, and prefetch `2`. Duplicate coordinates are coalesced across queued, running, and completed states. Persistent generation workers select by priority, then `(y, x)`, and produce private immutable buffers. They never mutate live chunks, Godot objects, textures, or the SceneTree.

`pump_generation(4)` transfers at most four completed buffers per frame on the main thread. Publication creates simulation arrays and one render-dirty chunk, then refreshes activity at the new chunk and its cardinal generated neighbors. Results are identical across `1`, `2`, and `4` generation workers and reversed/mixed-priority request order.

Active sand requests the three chunks below its current chunk at priority `0`. Until those chunks publish, guarded `-1` cells block movement. This is the simulation halo contract: unknown space cannot swallow matter and publication cannot expose a partially initialized chunk.

## Eviction and future persistence

Generated chunks start `pristine`. Any external cell edit, successful sand movement, structure placement, or structure removal marks every involved chunk `modified`. `evict_pristine_outside()` removes only generated, pristine, sleeping chunks outside the camera retention rectangle. The renderer consumes explicit eviction coordinates and deletes the corresponding sprites.

Evicted pristine chunks regenerate byte-identically from seed. Modified chunks are never discarded. Phase 2 does not implement disk saves; retaining modified chunks is the deliberate safe fallback until versioned modified-chunk persistence exists.

## Tools, tests, and captures

- Seed field or `F5`: regenerate current seed.
- `F6`: increment and regenerate.
- Copy button or `F7`: copy decimal seed.
- `F4`: geology heatmap; F3 diagnostics show cursor material/profile and fractions.
- `tests/phase2_correctness.gd`: provenance, bounds, async states, order/worker determinism, content, seams, composition, gold rarity, eviction, and golden seeds.
- `tests/benchmark_phase2.gd`: single/100-chunk generation, 10k-cell camera pan, deep load, eviction/regeneration, and memory gate.
- `artifacts/phase2/`: `surface.png`, `cave.png`, `water.png`, `coal.png`, `geology.png`, and `multichunk.png`.

## Dynamic Water streaming boundary

Generated reservoirs start full (`mass = 255`) and normally allocate no mass plane. Publication activates only unstable fronts; supported interiors sleep. A simulated transfer or Creative edit clears `pristine`, preventing dynamic Water from being evicted and regenerated. Untouched reservoir chunks retain deterministic eviction. Cross-streaming flow requests the neighbor halo and waits; ungenerated terrain is never interpreted as Empty.

## Phase 9 thermal streaming boundary

Generated base materials retain deterministic ambient temperature and implicit full amount. Any thermal change, phase transition, non-default amount, or moved Steam/molten state marks the chunk modified and therefore non-evictable until the future save layer can persist it. Thermal/gas halo work requests real neighboring chunks and never treats ungenerated space as ambient Empty. Activity masks and scratch are derived after publication or load.

## Phase 11 V2

Version `1` remains regression-locked. New worlds use `generation_version = 2` and stable `WorldIdentity`. V2 adds native macro fields, broad surface interpolation, explicit depth regions, five cave grammars, coherent physical aquifers, depth/regional geology, deep thermal fields, deterministic spawn corrections, and versioned authored FeatureTemplates. Streaming demand is expressed by `InterestRegion`; V2 Water does not recursively expand generation outside interest bounds. Full contract and validation: `WORLD_GENERATION_V2.md` and `WORLDGEN_VALIDATION.md`.

New worlds now use `generation_version = 5`. V5 keeps every V4 streaming and stability
guarantee and replaces the content model: per-subsystem seed domains, regionally
differentiated terrain, climate-space biomes, warped-Voronoi geological provinces with real
bedding planes, cave *systems* rasterised from world-space descriptors, local water tables
with impermeable barriers, and fractional liquid levels. V1-V4 saves keep their own
generator. Full contract, statistics and known weaknesses: `WORLD_GENERATION_V5.md`.
