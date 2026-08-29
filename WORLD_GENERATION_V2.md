# World Generation V2

## Identity and compatibility

`WorldIdentity` schema `1` is:

```text
seed
generation_version
generator_settings_hash
```

`generation_version = 2` selects Phase-11 generation. Version `1` remains callable and its canonical regression hash remains `86dee9f0`. Changing player preset cannot change identity or generated content.

## Native pipeline

Workers build immutable `64×64` buffers. Only the main thread publishes them. The ordered V2 passes are:

```text
macro_world
surface
depth_regions
cave_systems
aquifers
geology
thermal_regions
authored_features
spawn_validation
initial_stabilization
```

The macro scale is `64` cells. Each sample stores surface elevation, sediment depth, cave tendency, water table, aquifer strength, geology province, thermal tendency, and feature density. Coordinate hashes only; no global RNG, frame time, worker ID, or request order.

## Terrain

- Surface: broad interpolated macro elevations, locally flattened over the spawn factory floor.
- Depth regions: `SURFACE`, `SEDIMENT_SHALLOW`, `UNDERGROUND`, `CAVERNS`, `DEEP_THERMAL`, `BEDROCK`.
- Caves: `CAVERN`, `TUNNEL`, `CRACK`, `SHAFT`, and `POCKET` grammars. A deterministic early route and chamber provide initial exploration without ladders.
- Aquifers: coherent cave volumes filled below a local water table. Water is real material ID `3`; no decorative water layer. V2 unloaded fluid boundaries remain sealed until an `InterestRegion` loads them, preventing aquifers from recursively generating the world.
- Geology: regional/depth-aware profile and immutable `uint16` provenance/mineral signature for Raw Sand.
- Thermal: deep, spawn-excluded real temperature fields. Only gradients enter active thermal work.

## FeatureTemplate system

The versioned catalog contains:

```text
collapsed_chamber.v1
industrial_ruin.v1
geode_chamber.v1
thermal_vent.v1
```

Every template has footprint, orientation count, depth bounds, placement exclusions, tag, and future reward tag. Placement uses deterministic macro anchors and excludes spawn safety, Bedrock, critical connectivity, and conflicting major features. Generated industrial ruins contain actual structure-layer Reservoir Wall cells; thermal vents contain actual temperature; collapsed/geode chambers contain physical Rock Debris where applicable.

## Streaming

`InterestRegion` records stable source ID, priority, chunk bounds, purpose, and request budget. Character vicinity is priority `0`; directional prefetch and visible pages follow. God camera remains camera-driven. Spectator requests are bounded. Generation publication is capped per frame, and pristine chunks can be regenerated and evicted.

The world preview calls the same native macro source but intentionally omits caves, hidden geology, mineral signatures, and Gold anomalies.

## Phase 11.5 correction boundary

Raw Sand at spawn, the early Coal vein, cave route, Water cavern, and thermal exclusion are generator guarantees, not validator repairs. The only reported intentional correction pass is `SPAWN_FLATNESS`: deterministic local blending creates a practical starting floor while preserving the displayed seed and surrounding terrain. Validation records category, `MINOR/MODERATE/MAJOR` severity, raw span, guaranteed span, and intentional status. It never rerolls a seed.

See `WORLDGEN_VALIDATION.md` and `WORLD_GENERATION.md`.

## Phase 12 organic features

`basic_tree.v1` and `mushroom.v1` extend the existing `WorldFeatureTemplate` contract. Tree placement uses slope, space, regional feature density and aquifer tendency; `abs(x) < 160` remains clear for spawn/factory construction. Height, thickness, branches, canopy and moisture vary deterministically. Mode is not an input. The final worker `[1,2,4,8]` organic-region hash is `4dbeedff`, with no feature duplication across generation order.

## Phase 13 save boundary

WorldIdentity still derives pristine chunks. Saves omit pristine generated chunks and persist only changed/non-pristine chunk state plus active subsystems. Raw Sand constituent ratios derive exactly from provenance and mineral signature; runtime processing never rerolls them. Explicit mixture IDs are optional state and persist only where mixing occurred.
