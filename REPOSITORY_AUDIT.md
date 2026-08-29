# Repository Audit — Phase 13.7

## Inventory

| Path | Classification | Git policy |
|---|---|---|
| `core/` | SOURCE | track |
| `native/src/`, `native/core/` | SOURCE, TEST, BENCHMARK | track |
| `rendering/` | SOURCE | track |
| `scenes/`, `data/` | RUNTIME_ASSET, PROJECT_CONFIG | track |
| `debug/` | SOURCE, DEV_ONLY | track; composition root retained because moving it was cosmetic/risky |
| `tests/` | TEST, BENCHMARK | track |
| `scripts/` | BUILD_TOOL, DEV_ONLY | track |
| root `*.md`, `docs/` | DOCUMENTATION, curated RUNTIME_ASSET | track |
| `project.godot`, `export_presets.cfg`, `native/CMakeLists.txt` | PROJECT_CONFIG, BUILD_TOOL | track |
| `licenses/`, `LICENSE`, `THIRD_PARTY_NOTICES.txt` | DOCUMENTATION, LICENSE | track |
| `.deps/` | GENERATED dependency checkout | ignore |
| `.godot/`, `.godot-runtime/`, `.runtime-captures/` | CACHE, GENERATED, TEMPORARY | ignore |
| `native/build/`, `native/bin/` | BUILD_OUTPUT | ignore |
| `artifacts/`, `BUILD_MANIFEST.json` | ARTIFACT, GENERATED | ignore |
| `.safety-snapshots/` | SAFETY_BACKUP | ignore |

## Cleanup result

- Removed `artifacts/`: 459 generated capture/package/diagnostic files, 362,117,261 bytes. Four final Phase 13.6 screenshots were curated into `docs/assets/screenshots/` first. The complete pre-cleanup tree remains recoverable from ignored `.safety-snapshots/phase136-before-phase137.zip`.
- Duplicate hashing found generated capture/package copies only; no source/resource duplicate was blindly removed.
- Empty editor-template directories require no Git entry and remain local-only when recreated.
- Historical phase-named tests remain intentionally named; they identify regression origin. Permanent production code was not cosmetically moved merely to erase history.

## Markdown audit

Every Markdown file present before documentation refresh was read. New Phase 13.7 documents are canonical current records.

| File | Purpose | Status |
|---|---|---|
| `README.md` | player/developer landing page | rewritten current |
| `STATUS.md` | implementation and gate status | rewritten current |
| `PROJECT_CANON.md` | physicality/design invariants | current |
| `ARCHITECTURE.md` | system boundaries | current |
| `SIMULATION.md` | authoritative simulation | current |
| `MVP_SCOPE.md` | implemented/optional/dev/post-MVP split | corrected current |
| `ROADMAP.md` | phase completion/future boundary | corrected current |
| `PERFORMANCE.md` | historical and current measurements | canonical; Phase 13.7 appended after gates |
| `SAVE_FORMAT.md` | save envelope/state contract | updated by Phase 13.7 hardening |
| `THREADING_MODEL.md` | worker ownership and shutdown | new current |
| `KNOWN_ISSUES.md` | prioritized residual risk | new current |
| `DEVELOPMENT.md` | clean-clone workflow | new current |
| `REPOSITORY_AUDIT.md` | repository evidence | new current |
| `GAMEPLAY_LOOP.md` | physical vertical slice | current |
| `GAME_MODES.md` | Factory/Character/Creative presets | current |
| `MVP_PROGRESSION.md` | shared progression | current |
| `PROGRESSION.md` | Phase 5 progression origin | historical design context |
| `MATERIAL_CONSERVATION.md` | exact constituent ledger | current |
| `MATERIAL_INTERACTIONS.md` | interaction matrix | current |
| `COMPOSABLE_PROCESSING.md` | no-black-box processing | current |
| `MATERIAL_PROCESSING.md` | Phase 4 processing origin | historical; superseded by physical components |
| `PHYSICAL_PROCESSING.md` | current processing canon | current |
| `WET_PROCESSING.md` | Water/Riffle separation | current |
| `PHASE_CHANGES.md` | phase-family laws | current |
| `THERMODYNAMICS.md` | production thermal model | current |
| `THERMAL_ARCHITECTURE.md` | pre-production candidate gate | historical architecture evidence |
| `GAS_SIMULATION.md` | gas solver | current |
| `STEAM_AND_GASES.md` | Steam integration | current |
| `COMBUSTION_ARCHITECTURE.md` | combustion contract | current |
| `ORGANIC_PHYSICS.md` | Trees/organic state | current |
| `PHYSICAL_COOKING.md` | cookware interaction | current |
| `FACTORY_LOGISTICS.md` | conveyors/storage | current |
| `FACTORY_FOUNDATIONS.md` | Phase 8.75 construction origin | historical architecture evidence |
| `BLUEPRINTS.md` | Blueprint/CommandBatch semantics | current |
| `SUBSURFACE_LOGISTICS.md` | finite hidden routes | current |
| `FLUID_LOGISTICS.md` | production Pipes/damage/leaks | current |
| `FLUID_ARCHITECTURE.md` | pre-fluid selection history | historical architecture evidence |
| `POWER_ARCHITECTURE.md` | Steam/mechanical/electrical chain | current |
| `AUTOMATION.md` | signal graph and controls | current |
| `WORLD_GENERATION.md` | WorldGen V1 phase record | historical; superseded by V2 |
| `WORLD_GENERATION_V2.md` | current generator contract | current |
| `WORLDGEN_VALIDATION.md` | corrections/seed validation | current |
| `CHARACTER_MODE.md` | character controller/capabilities | current |
| `VISIBILITY_AND_DISCOVERY.md` | FOV/map knowledge | current |
| `UI_UX.md` | UI architecture | current |
| `UX_GUIDELINES.md` | interaction canon | current |
| `DESIGN_SYSTEM.md` | visual tokens | current |
| `AUDIO_EVENT_MATRIX.md` | procedural audio coverage | current |
| `RENDERING_ARCHITECTURE.md` | batched rendering/LOD | current |
| `PLATFORM_ARCHITECTURE.md` | platform boundaries | current/future clearly split |
| `MULTIPLAYER_ARCHITECTURE.md` | future network design | planned only |
| `PHYSICAL_SANDBOX_ROADMAP.md` | physicality expansion | roadmap |
| `RECOVERY_AUDIT.md` | softlock/recovery analysis | current |
| `OWNER_FIRST_PLAYTEST.md` | owner manual runbook | current |
| `PLAYTEST_CHECKLIST.md` | packaged manual checklist | current |
| `PLAYER_FACING_AUDIT.md` | Phase 13.5 UI inventory | historical audit |
| `PHASE135_PLAYTEST_RC.md` | Phase 13.5 result | historical report |
| `PHASE136_POLISH.md` | Phase 13.6 result | historical report |
| `docs/INDEX.md` | documentation navigation | new current |

Historical design files are grouped and labeled in `docs/INDEX.md`; current documents no longer present pre-component processing, missing Character/Save/Fire, or Phase 13.5 as future work.

## Tooling and safety audit

- Removed owner-local Godot executable dependency; exact 4.7.1 discovery is portable.
- Clean build deletion resolves and verifies its target remains inside `native/`.
- Package manifest excludes dependency/runtime/build/artifact trees and includes required source extensions.
- Important subprocesses have explicit nonzero handling.
- `ctest` now runs `koalasand_core_probe`.
- Canonical `scripts/test.ps1` and `scripts/benchmark.ps1` cover complete suites.

## Source/lifetime/bounds findings

- Fixed `INT32_MIN` floor division overflow and unsafe rectangle-end arithmetic.
- Added work caps for rectangle/chunk/visibility/material operations.
- Added snapshot collection/type/range/count validation before world reset.
- Stopped workers before world storage clear/reconfiguration.
- Serialized save writes and joined async work at file/world lifecycle boundaries.
- Added save, command, batch and Blueprint input caps and structural validation.
- Fixed procedural `AudioStreamWAV`/playback shutdown retention by stopping, detaching and freeing pooled players before a drained engine exit; verified with Godot `--verbose` and zero leaked instances.

## Unknown or preserved

- The `debug/debug_world.gd` composition root mixes runtime orchestration with developer fixtures. It is intentionally preserved: moving it during an initial baseline would create broad scene/resource churn without reducing runtime coupling.
- Historical phase documents and tests remain evidence, not current feature claims.
