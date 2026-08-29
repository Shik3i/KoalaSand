# Character Mode

Character Mode is embodiment and exploration, not survival. Phase 11 has no Hunger, Thirst, Health, Death, Respawn, enemies, combat, fall/Steam damage, drowning, inventory stacks, durability, or ladders.

## Controller and collision

`KoalaCharacterController` uses deterministic fixed-tick integer milli-cell position/velocity. Its compact logical body is `3×6` cells. Every collision query samples 18 native terrain/structure cells; there are no per-cell Godot physics Nodes. Water applies drag. Steam is nonblocking and harmless in Phase 11.

Inputs are InputMap actions: `move_left`, `move_right`, `jump`, `jetpack`, `sprint`, `hover`, `interact`, `dig`, and `center_camera`.

Walk, jump, air control, and the Basic Jetpack exist from tick `0`. The Basic Jetpack consumes no fuel, Steam, electricity, durability, or Research. The follow camera has bounded pointer look-ahead. Reduced-motion preference disables smoothing/effects that could cause discomfort.

## Local interaction

Build/dig range is centralized at `18` cells. A bounded line-of-interaction rejects actions through large solid walls. Structure placement remains unlimited/free after Research unlock; Character Mode adds locality, not placement material costs. Placement reports `OUT_OF_RANGE`, `BLOCKED_INTERACTION`, `COLLIDES_WITH_TERRAIN`, `COLLIDES_WITH_MATERIAL`, `TECH_LOCKED`, or `UNKNOWN_AREA`.

Basic Dig time is `0.35 s`:

| Input matter | Physical result |
|---|---|
| Stone | Rock Debris (`20`), granular and transportable |
| Coal terrain | Coal Chunk (`14`) |
| Raw Sand | Remains physical Raw Sand; never deleted |
| Bedrock | Protected |

Digging changes normal world cells and therefore wakes matter, render, thermal/fluid neighbors, and visibility through ordinary simulation paths.

## Mobility progression

- `mobility.sprint`: prerequisite `foundation.basic_industry`; `600 Glass`, `10 Iron`, `0 Gold`; meaningful ground-speed increase, no stamina.
- `mobility.hover`: prerequisites `mobility.sprint` and `automation.basic_sensing`; `1800 Glass`, `90 Iron`, `1 Gold`; damps drift and holds altitude for precise aerial building.

Hover supports toggle or hold behavior through `CharacterAccessibilityPreferences`. Preferences also serialize reduced motion and UI scale.

## Phase 11.5 movement profile

The 60 Hz fixed-tick profile uses milli-cells:

| Control | Final value |
|---|---:|
| Walk | `320 milli/tick` = `19.2 cells/s` |
| Sprint | `500 milli/tick` = `30.0 cells/s` |
| Jump impulse | `520 milli/tick` |
| Jump buffer | `5 ticks` |
| Coyote time | `5 ticks` |
| Jetpack acceleration | `42 milli/tick²` |
| Jetpack ascent cap | `680 milli/tick` = `40.8 cells/s` |
| Hover precision speed | `180 milli/tick` = `10.8 cells/s` |
| Hover damping | `125 milli/tick`; rest within at most `6 ticks` |

The camera allows at most `52 cells` of bounded pointer look, uses a `12 px` dead zone, `0.42` mouse-look factor, velocity-based vertical look, and `0.36` follow interpolation. Reduced motion snaps directly to the target. Movement preserves gravity, inertia, terrain/structure collision, and Water drag; Jetpack is not noclip.

## Persistence boundary

`KoalaPlayerState` schema `1` combines exact `WorldIdentity`, mode axes, Character fixed-point state, stable `VisibilityOwnerID`, and persistent discovery/last-known pages. Restore rejects a mismatched world identity. Full world save/load remains outside Phase 11.

See `GAME_MODES.md` and `VISIBILITY_AND_DISCOVERY.md`.

## Phase 12 tools

Character Tool slots are `Dig`, `Cut`, `Igniter` (`1/2/3`). `CUT` and `IGNITE` are serializable `WorldCommand`s, obey the existing 18-cell interaction range, obstruction and live-visibility checks, and require no durability/crafting. Cut detaches connected Tree matter; Igniter applies `24,000,000` thermal-energy units and cannot force a burning state. Factory uses global batched vegetation clearing; Creative additionally paints Wood, Leaves, Charcoal, Smoke and Food states.
