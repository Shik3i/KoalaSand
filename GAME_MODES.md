# Game Modes

Phase 11.5 composes play from three independent, serialized axes. A mode never changes `WorldIdentity`, generated matter, geology, temperature, structures, Research definitions, or simulation rules.

| Axis | Values | Meaning |
|---|---|---|
| `ControlMode` | `GOD`, `CHARACTER`, `SPECTATOR` | Camera/embodiment and command authority |
| `ProgressionMode` | `NORMAL`, `CREATIVE` | Research enforcement and Creative tools |
| `VisibilityPolicy` | `OMNISCIENT`, `DISCOVERED`, `TEAM` | Presentation knowledge boundary |

## Player presets

| Preset | Control | Progression | Visibility | Notes |
|---|---|---|---|---|
| Factory | `GOD` | `NORMAL` | `OMNISCIENT` | Recommended; existing free camera and normal Research |
| Character | `CHARACTER` | `NORMAL` | `DISCOVERED` | Physical movement, local build/dig, persistent discovery |
| Creative | `GOD` | `CREATIVE` | `OMNISCIENT` | Everything unlocked plus material paint/erase |

`core/modes/game_mode_capabilities.gd` is the only capability map. It distinguishes `build_anywhere` from `build_in_range`, `creative_erase` from normal commands, and discovery from omniscient presentation. Spectator remains read-only and generation-budgeted; no networking runtime exists.

`GameSession` schema `1` serializes the three axes and preset ID. The Phase-6.5 `Mode` enum remains only as a compatibility adapter.

## Same seed, same world

World generation accepts only `WorldIdentity` and generator settings. Capability/preset state is never passed to a generation worker. Phase-11 worker, request-order, and Factory/Character/Creative parity tests compare complete region hashes. A displayed seed is never silently rerolled.

See `WORLD_GENERATION_V2.md`, `CHARACTER_MODE.md`, and `VISIBILITY_AND_DISCOVERY.md`.

## Player-facing distinction

Factory is recommended global factory planning with normal Research. Character inhabits the same world physically, builds/digs locally, and uncovers it through discovery. Creative is an explicit player sandbox with global construction and material paint/erase; diagnostics remain a separate developer layer. The New Game screen describes these outcomes and does not expose the internal enum names.
