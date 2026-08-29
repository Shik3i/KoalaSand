# Blueprints and Command Batches

## CommandBatch schema 1

Each batch contains `batch_id`, `actor_id`, `sequence`, optional `label`, explicit `validation_mode`, and ordered serialized `WorldCommand` records. No pointer or hash-map iteration order is authoritative.

- `ATOMIC`: native prevalidation succeeds for every operation or no operation applies. Required for linked tunnels and replacements.
- `BEST_EFFORT`: valid entries apply in canonical order; compact rejection reason codes describe failures.
- Result: applied/rejected counts, compact reason codes, affected `Rect2i`, validation/application microseconds, and relative-ID map.
- The native structure path submits the whole operation array through one GDExtension call. A 10,000-structure Blueprint is not 10,000 script-to-native calls.

`WorldCommandBus` serializes batch logs and replays by `(sequence, batch_id)`. Each command receives canonical order and actor identity before execution. Future hosts can validate capability, actor and sequence before committing the same batch.

## Construction history

`ConstructionHistory` stores serialized forward/inverse batches, default capacity 64. `Ctrl+Z` applies the inverse against current world state; `Ctrl+Y` reapplies the forward batch. Place/remove/configure/wire/Pipe/subsurface operations are eligible when a safe inverse exists. Research, granular movement, Water/Pipe movement, processing and other simulation evolution are excluded. Inverse removal uses ordinary conservation-safe current-world semantics; it never resurrects a material snapshot.

## BlueprintDefinition schema 1

Blueprints contain relative structures, configurations, Pipe/device data, automation components/wires, and subsurface endpoint/channel references. Automation components instantiate before their wires; relative IDs remap to allocated component IDs inside the same batch. They never contain Sand, Water, processed grains, Pipe mass, machine runtime buffers, Research reserves or thermal state.

- positions, orientations, ports and linked endpoints share canonical rotate/flip-H/flip-V transforms;
- relative component/channel IDs remap deterministically to newly allocated world IDs;
- `BuildExecutionMode.IMMEDIATE` executes for current Creative capability;
- `BuildExecutionMode.GHOST` is a serialized future Character/drone boundary, not implemented gameplay;
- `U` anchors a rectangular selection; `Ctrl+C` or `Ctrl+X` captures every selected structure origin, automation component/internal wire, and fully enclosed Subsurface Channel as relative data;
- cut preflights `MUST_DRAIN`, then submits one safe deconstruction batch; paste submits one batch and records allocated automation/channel IDs for exact construction-only Undo;
- clipboard history is bounded to 16 entries by default;
- the in-memory named library stores name, description, schema and definition; disk/cloud sharing and Blueprint Books remain future work.

## Planners and fast replace

`ConstructionPlanner` expresses pipette metadata, compatible family replacement, region upgrades and region deconstruction. Replacement preserves compatible orientation/configuration and refuses unsafe matter deletion. Tunnel removal returns `MUST_DRAIN` while occupied.

## Measured batching

Godot 4.7.1, native Release:

| Commands | Validation | Application |
|---:|---:|---:|
| 100 place | 0.038 ms | 0.224 ms |
| 1,000 place | 0.159 ms | 2.682 ms |
| 10,000 place | 1.551 ms | 22.607 ms |
| 10,000 undo/remove | 0.930 ms | 22.522 ms |

These timings include normal native placement/removal validation. Render invalidation remains region/page based.
