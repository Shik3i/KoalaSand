# WorldGen V2 Validation

## Command

Use only the repository-pinned Godot 4.7.1 wrapper:

```powershell
.\scripts\godot.ps1 --headless --path . --user-args --validate-seeds=25000
```

Optional start: `--validate-seed-start=N`. Output is one deterministic `phase11_seed_validation_json=...` report. Nonzero post-correction failures return a nonzero process exit code.

## Generator guarantees versus corrections

The displayed seed never changes or rerolls. These are base-grammar guarantees, not validator repair:

- surface Raw Sand at spawn;
- Coal vein within 70 cells;
- early tunnel/chamber route within 72 cells;
- coherent physical Water cavern within 192 cells;
- thermal spawn exclusion;
- authored-feature exclusion from spawn safety and critical connectivity.

The only intentional correction pass is `SPAWN_FLATNESS`: a deterministic local blend limits the generated starting floor to a three-cell span. Each correction record includes stable category, `MINOR/MODERATE/MAJOR` severity, intentional flag, raw span, and guaranteed span. All other stable categories remain explicit even when zero: `RESOURCE_ACCESS`, `WATER_ACCESS`, `CAVE_ACCESS`, `CONNECTIVITY`, `FLOOD_SAFETY`, `THERMAL_HAZARD`, `FEATURE_COLLISION`, `WORLD_BOUNDARY`, and `OTHER`.

The historical `19,307 / 10k` number did not measure actual generator repair. The old validator fabricated independent random “raw distance” values, then counted four hardcoded generator guarantees as corrections. Phase 11.5 removed that synthetic accounting. The remaining correction is a measured, local, disclosed starting-floor shape; it is not resource/cave/flood/thermal rescue.

## Current 25,000-seed report

Range `1..25000`, Godot `4.7.1`, Release native build:

```text
validation_failures          0
corrections                  24702
average corrections/seed    0.98808
corrections p50/p95/p99/max 1 / 1 / 1 / 1
severity NONE               298
severity MINOR              24702
severity MODERATE           0
severity MAJOR              0
major-correction percent    0.000
elapsed_ms                  9.036
seeds_per_second            2766710.9
spawn_flatness max          3
coal_distance max           70
water_distance max          192
first_cave max              72
hot_hazard min              640
```

## Canonical representative seeds

| Profile | Seed |
|---|---:|
| balanced | `3540` |
| flat surface | `17524` |
| rough surface | `13620` |
| cave-heavy | `2965` |
| cave-light | `10412` |
| aquifer-heavy | `13167` |
| dry | `18076` |
| nearest thermal | `1526` |
| deep-shaft-heavy | `10652` |
| feature-heavy | `3` |
| extreme-valid | `15508` |
| worst corrected | `1` |
| major corrected | none (`-1`) |

The twelve visual profiles and contact sheet are under `artifacts/phase115/seed-profiles` and `artifacts/phase115/18-seed-profile-contact-sheet.png`.

V2 correctness uses seed `8675309` for worker/request-order golden parity. V1 retains golden region hash `86dee9f0`. A second gate fully generates 35 chunks for each of 100 selected seeds, verifies publication and content diversity, then runs worker parity, request-order parity, pass hashes, streaming traversal, and runtime benchmarks.
