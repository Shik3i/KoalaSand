# Save Format

## Generation V4 compatibility

New worlds store `generation_version = 4`. Existing V1/V2/V3 saves keep their stored generator identity and reproduce pristine chunks through the matching legacy dispatch. Save schema `1` is unchanged because the generation version was already part of world identity and snapshot settings. V4 is the P0.5 world-quality generator documented in `P05_WORLD_QUALITY_PASS.md`.

## Envelope schema 1

```text
uint32 magic_length
bytes  "KOALASAND_SAVE"
uint32 envelope_schema
uint64 payload_length
bytes[32] SHA-256(payload)
bytes payload (Godot Variant Dictionary)
```

Metadata: world name, UTC/unix timestamp, playtime, seed, generation version, Factory/Character/Creative mode, game version and save schema version.

## Atomic write and recovery

`WorldSaveManager` captures one consistent native snapshot, writes `*.tmp`, flushes, rereads and validates the checksum, moves the previous `*.ksave` to `*.bak`, then renames the validated temporary file. Failed replacement restores the backup. Load validates header, length, SHA-256 and payload before deserialization; a corrupt primary automatically falls back to its backup. Future migrations chain from `_migrate_payload` without modifying the only disk copy.

Envelope and payload lengths are capped at 256 MiB before allocation. The loader rejects truncated files, unsupported future envelope schemas, invalid magic, mismatched checksums, malformed Variant shapes and any trailing bytes. Native world snapshots receive full collection/count/type/range validation in a fresh validation world before the live world can be reset or mutated.

Save names are limited to 128 characters and converted to one 64-character ASCII-safe stem. Traversal, drive paths, Unicode substitutions, filesystem-invalid characters and Windows reserved device names receive a deterministic hash suffix/prefix and cannot escape `save_root`.

Autosave snapshot capture happens on the main thread. File encoding and atomic write run on a background `Thread`; `poll_async_save()` reports completion. All writers share one mutex, so manual save, autosave, rename, delete and backup replacement cannot race the same paths. Load/restore/delete/rename and explicit exit join an active save first.

## Authoritative world payload

Persisted state includes modified/generated non-pristine chunks; materials, amount, provenance and mineral signature; optional composition, bound moisture, thermal, phase, organic, atmosphere and discovery planes; structures; machines and bounded slots; physical Pipes and fluids; falling Trees; automation; subsurface logistics; mechanical/electrical topology plus rotational/accumulator energy; Research and Bank totals; generic fractional ledgers; milestones; active/reactive scheduler state; and WorldIdentity.

Session context includes Character state, camera/zoom, HUD/Quickbars/onboarding, editable Blueprints, objectives and world-owned settings. Pristine procedural chunks are omitted and regenerate from WorldIdentity.

Blueprints contain geometry/configuration only. They never contain a processing ledger or constituent carry.
