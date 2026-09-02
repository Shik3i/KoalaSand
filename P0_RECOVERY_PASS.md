# P0 Playtest Recovery Pass

Historical P0 baseline: V3 remains available for save compatibility. New worlds use the P0.5 V4 generator documented in `P05_WORLD_QUALITY_PASS.md`.

## Compatibility boundary

- New worlds use deterministic `generation_version = 3`.
- Version `1` and `2` dispatch and canonical hashes remain available unchanged.
- Existing saves retain their stored generation version; modified chunks and all physical subsystem state keep the existing save schema.
- Godot remains pinned to `4.7.1` through `scripts/godot.ps1`.

## UI root causes and recovery

The old main page placed a fixed `1240x720` minimum inside a full-window `ScrollContainer`, while the project rendered through a `1152x648` canvas with the default keep-aspect behavior. Three fixed `400x124` mode cards and a fixed `760x340 + 400x330` preview/setup row exceeded that canvas before theme spacing. Both scroll axes and aspect gutters were structural consequences.

The project now uses a `1280x720` reference viewport with `window/stretch/aspect="expand"`. The main page is a margin-bounded responsive `VBoxContainer`; it contains no page `ScrollContainer`. Mode cards share available width, the preview consumes remaining flexible space, and the setup column keeps `Create world` visible.

The gameplay HUD is one `64 px` top row and one `96 px` bottom dock at `1920x1080`. Objective/tutorial detail is an on-demand popup. Onboarding highlights name the concrete action and hints can be dismissed. At narrow widths, the complete world-tool set moves into a compact `Tools` menu. The Catalog remains on `B`; Research, Catalog, Blueprints, Plan, overlays, map, statistics and help remain temporary overlays or explicit actions.

At `1920x1080`, the captured baseline used approximately `87 px` top and `113 px` bottom panels, leaving about `853 px` between them. The new measured geometry is exactly `64 px` top, `96 px` bottom and `892 px` between them: permanent panel height falls from about `200 px` to `160 px`, and unobscured vertical world space increases by `39 px`.

## Generation V3

V3 constructs stable initial conditions instead of asking simulation to settle invalid terrain:

1. A `256`-cell interpolated surface field limits adjacent height changes and keeps surface deposits supported.
2. Loose Raw Sand is local: a guaranteed spawn deposit plus deterministic regional deposits, each `3..7` cells deep on solid host rock.
3. Stone is the default underground mass. Coal uses depth-bounded capsule veins embedded in stone.
4. Caves are sparse chambers connected by bounded-width tunnels. A deterministic early dry route remains available.
5. Per-chunk void caps are hard limits by depth band: shallow `12%`, middle `18%`, deep `14%`. Candidate cores are retained by local structural support rather than high-frequency threshold noise.
6. The minimum ordinary surface roof is `max(34, sediment_depth + 18)` cells.
7. Aquifers are contained elliptical chambers with a solid exclusion shell and a horizontal full-cell waterline. Surface lakes are emitted only in measured basins below the lower spill rim.
8. Generated dynamic matter is published through the normal physical material representation. Activity is derived by the existing scheduler; no invalid arrangement is force-slept.

`get_generation_stability_report()` exposes generated-chunk diagnostics: unsupported Sand, initially active Water, vertical water drops, active dynamic chunks, void fractions and maxima by depth band, minimum roof, thin solid remnants, and bounded coordinate samples for invalid dynamic cells.

## Acceptance evidence

`tests/p0_recovery_correctness.gd` covers five representative V3 seeds, worker-count determinism, V2 compatibility, diagnostic purity, intentional Sand/Water destabilization, and UI geometry at:

- `1280x720`
- `1600x900`
- `1920x1080`
- `2560x1440`
- `1920x1200` (16:10)

Measured worldgen/activity comparison for the same traversal and seed:

| Metric | V2 | V3 |
|---|---:|---:|
| Initially active dynamic cells | 2234 | 0 |
| Active Sand chunks | 5 | 0 |
| Active fluid chunks | 28 | 0 |
| First-tick moves | 6747 | 0 |
| Settle ticks | >60 | 0 |
| First simulation tick | 4.6450 ms | 0.4120 ms |
| Average chunk generation | 1.8771 ms | 4.9710 ms |
| Worst chunk generation | 8.4350 ms | 9.1620 ms |
| Max shallow/mid/deep chunk void | 100/100/100% | 11.99/17.99/13.59% |
| Minimum measured roof | 28 | 74 |

The tradeoff is deliberate: V3 spends about `3.09 ms` more per asynchronously generated chunk to remove the much larger immediate simulation spike.

## Remaining follow-up

- The performant material renderer still uses high-contrast cave voids and blocky macro-preview strata. Structural readability is improved by solid-mass dominance, but a later renderer-only palette/detail pass can improve geological texture without changing generation.
- V3 currently prioritizes stable geology over the V2 subsurface authored ruin/geode/vent carving pass. V1/V2 worlds preserve those features. A future V3-authored-feature revision must participate in the same void-budget and equilibrium validator before reintroduction.
