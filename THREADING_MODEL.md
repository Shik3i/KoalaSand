# Threading Model

## Ownership

- The Godot main thread owns scenes, Nodes, textures, UI state, world publication and all calls that mutate presentation resources.
- `NativeSandWorld` owns authoritative simulation state. A simulation step completes before the main thread reads the published result.
- Persistent native workers receive bounded immutable/range work. They write disjoint scratch/output regions; deterministic merges happen after barriers.
- World-generation workers produce immutable chunk results. The main thread publishes accepted results and applies generation/version checks.
- Native render workers generate CPU-side pixel/page payloads only. Godot texture creation and upload stay on the main thread.
- `WorldSaveManager` captures the authoritative snapshot on the main thread. Its optional worker performs file encoding/atomic replacement only on the detached payload.

## Lifetime rules

- `reset()`, world reconfiguration and destruction stop/join render and generation workers before clearing chunks, cached pointers or buffers.
- Worker jobs may not retain Godot Object pointers or borrowed chunk references beyond their barrier.
- Cached IDs are values, not object pointers. Every network/component lookup is revalidated after topology changes.
- Save/load, delete, rename and scene-exit boundaries finish an outstanding async save before touching the same files or world lifetime.
- Native snapshot input is fully shape/range validated before `reset()`; rejected input cannot partially replace the live world.

## Synchronization

- Native worker pools use explicit job publication, barriers and stop/join ownership; no detached native worker owns world memory.
- Save writes are serialized through one mutex. Temporary write → validation → previous-primary backup → atomic rename is the only replacement path.
- Authoritative subsystem order remains deterministic. Parallel work partitions cannot change merge order, conflict resolution or hashes.

## Audited risks

- Fixed in Phase 13.7: render workers could still reference chunk-backed state while `reset()`/configuration cleared it.
- Fixed in Phase 13.7: manual and async saves could race the same temporary/primary/backup paths.
- Fixed in Phase 13.7: malformed native snapshots could reset/mutate the current world before a late validation failure.
- No remaining raw Godot Object retention was found in native simulation workers.

See [ARCHITECTURE.md](ARCHITECTURE.md), [SIMULATION.md](SIMULATION.md) and [SAVE_FORMAT.md](SAVE_FORMAT.md).
