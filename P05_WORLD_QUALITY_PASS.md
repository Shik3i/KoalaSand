# P0.5 World Quality and Presentation Pass

## Result

New worlds use deterministic `generation_version = 4`. V1, V2, and V3 dispatch remain intact for existing saves. The final V4 build starts with zero accidental dynamic activity in the measured sample, contains physical Sand and Water across every one of 100 generated seeds, stays inside all explicit void budgets, and is faster than the retained V3 generator in the same traversal fixture.

Godot was invoked only through `scripts/godot.ps1`. Visual QA used deterministic automated captures; no interactive GUI control was used.

## 1. Retained P0 architecture

- Native `64x64` immutable worker buffers and main-thread publication.
- Coordinate-hash generation without frame time, worker identity, or shared RNG state.
- Chunk streaming, bounded resident set, simulation halos, sleeping active regions, and stable-on-publication material state.
- V3 stable Sand, contained Water, spawn guarantees, save identity, regression dispatch, responsive no-scroll UI root, and compact top/bottom HUD foundation.
- Godot `4.7.1` pin through `scripts/godot.ps1`.

## 2. Added architecture

- Versioned V4 generation path with multiscale surface synthesis, semantic surface profiles, geological provinces, four cave grammars, lake basins, regional aquifers, ore veins, and quantitative quality reporting.
- Cached per-column hot-path descriptors; native arrays and analytic coordinate fields only.
- `get_worldgen_quality_report()` for physical content, activity, surface, topology, deposit-size, aquifer-size, ore-size, and province metrics.
- Zero-cost-when-disabled worldgen inspector layers for macro regions, geology, cave archetypes, aquifers, and start constraints.

## 3. Macro-region design

| Field | Scale | Contract |
| --- | ---: | --- |
| Surface macro band | `1024` cells | Large terrain silhouette |
| Surface meso band | `256` cells | Hills, valleys, basin shape |
| Surface micro band | `64` cells | Local variation without high-frequency noise |
| Geological province | `512` cells | Five coherent rock palettes and profiles |
| Cave descriptor grid | `512x384` cells | Cross-chunk cave archetypes |
| Aquifer descriptor grid | `640x448` cells | Contained regional water bodies |
| Lake search region | `1024` cells | Basin floor and spill-rim test |

Descriptor lookup halo: `640` cells. Every field is evaluated in world coordinates, so chunk edges do not define geological edges.

## 4. Chunk-order determinism

The same V4 region was generated in request orders `A-B-C`, `C-A-B`, and `B-C-A`; pass hashes and final world hashes matched. V3 was checked separately and remains dispatched by its stored version. The renderer and quality reporter read published cells only and do not affect generation.

## 5. Surface generation

- Smooth macro/meso/micro synthesis replaces the broad, nearly flat strip.
- A `176`-cell spawn blend keeps the initial construction area usable without flattening the world globally.
- Slope, curvature, valley position, and elevation drive sediment depth from `5..28` cells.
- Surface Sand appears in bounded local deposits rather than as a universal painted band.

## 6. Geological strata

Stable Stone cells carry V4 semantic provenance for topsoil, packed sediment, weathered rock, and deep rock. Five deterministic provinces alter the base palette; depth waves and mineral signatures add low-cost strata modulation. Province color transitions blend across the renderer instead of forming hard vertical seams. These are semantic profiles over existing physical material IDs, preserving simulation compatibility.

## 7. Cave archetypes

- Elliptical chambers.
- Bent two-segment directional tunnels.
- Leaning two-segment fissures/shafts.
- Rare large caverns.
- Contained flooded pockets and occasional basin-linked surface water.

The generator prioritizes coherent pocket/tunnel candidates, removes isolated one-cell remnants twice, and enforces per-chunk shallow/middle/deep void budgets of `13% / 20% / 16%`.

## 8. Cave statistics

Actual 100-seed region sample (`7x12` chunks per seed): descriptor cave systems mean `2.05`, p50 `2`, p90 `3`, p99 `4`, min `1`, max `4`. The metric counts deterministic descriptor systems intersecting the sampled region; it is not a full connected-component topology solve.

## 9. Sand and sediment

- Seed-varied spawn deposit plus regional deposits with bounded horizontal radius and `4..10` cell physical depth.
- Placement requires adjacent surface support and acceptable local slope.
- Topsoil/packed/weathered profiles vary separately from loose physical Sand.
- Removing host support in the fixture wakes Sand; after `120` ticks movement is nonzero and Sand cell count is conserved.

## 10. Water, lakes, and aquifers

- Lakes require a measured basin whose floor lies below the lower spill rim.
- Aquifers use seed-varied elliptical descriptors, a stable horizontal water table, and a five-cell solid shell.
- Generated water uses full-cell mass where the discrete water table intersects the cell grid; no artificial pre-settling is required.
- Opening an aquifer shell produces fluid transfer and conserves total Water-family mass through `180` ticks.

## 11. Sand amount versus activity

Twelve-seed correctness region: `11,085` physical Sand cells, `0` initially active Sand cells. Actual 100-seed sample: mean `899.89`, p50 `753`, p90 `1,620`, p99 `2,358`, min `229`, max `2,658`; no seed was empty.

## 12. Water amount versus activity

Twelve-seed correctness region: `9,494` physical Water cells, `0` initially active Water cells. Actual 100-seed sample: mean `654.83`, p50 `649`, p90 `962`, p99 `1,395`, min `229`, max `1,695`; no seed was dry.

## 13. Starting-region constraints

- Usable surface blend within `176` cells of spawn.
- Guaranteed seed-varied supported Sand deposit near spawn.
- Guaranteed shallow Coal access at x `48..82`, depth `38..48`.
- Ordinary caves excluded within `abs(x) < 104` above depth `220`.
- A seed-varied early aquifer is placed beyond the protected build core.
- Start-region contact sheet includes the spawn marker for all 20 inspected seeds.

## 14. Seed statistics

Actual generated sample: `100` seeds, `8,400` inspected chunks. Results: `0` unstable, `0` dry, `0` without Sand. Ore-vein descriptors mean `4.68`, p50 `5`, p90 `7`, p99 `8`, min `1`, max `9`. Surface slope mean `0.070224`; longest flat run mean `117.37`, p90 `152`, p99 `207`, min `68`, max `221`. Twelve focused seeds also passed physical content, structure, activity, and all 36 depth-band budget checks.

## 15. Visual artifacts

- `artifacts/p05-world-quality/contact-sheets/surface-shallow-20-seeds.png`
- `artifacts/p05-world-quality/contact-sheets/underground-caves-20-seeds.png`
- `artifacts/p05-world-quality/contact-sheets/water-aquifers-20-seeds.png`
- `artifacts/p05-world-quality/contact-sheets/start-regions-20-seeds.png`
- `artifacts/p05-world-quality/contact-sheets/manifest.json`
- Final menu, HUD, and inspector captures: `artifacts/p05-world-quality/final/`

Every sheet uses 20 deterministic seeds in a uniform `5x4` grid and a category-specific fixed frame.

## 16. Preview redesign

The new-world preview is a fast postcard generated from V4 macro descriptors: sky gradient, distant silhouette, surface profile, geological province palette, strata, and eligible surface water. Exact caves, ores, aquifers, and the generator signature remain hidden. Copy names the visible province and mode and explicitly keeps the underground undiscovered.

## 17. Menu polish

- Empty save state removes Continue, session row, and save details rather than reserving dead space.
- Shorter mode cards with a clear selected state.
- Diagnostics moved to a quiet `...` control beside the preview note.
- Compact seed controls and a dominant Create World action.
- Verified without scrolling at `1280x720`, `1600x900`, `1920x1080`, `1920x1200`, and `2560x1440`.

## 18. HUD polish

- Transparent outer dock with three separate action, quickbar, and build groups.
- Icon-like action glyphs with help/tooltips replace long toolbar labels.
- Objective is complete at wide layouts and becomes the explicit `Objective >` affordance at narrow layouts; no ellipsis clipping.
- Bottom dock width is bounded to `82%` with a practical minimum; permanent top/bottom bars remain `64 / 96` pixels at `1920x1080`.

## 19. Camera framing

Factory captures move vertical focus `20` cells toward terrain and use zoom index `4` (`3x`) instead of index `3` (`2x`). Character framing moves `8` cells toward terrain. The result reduces unused sky and makes the physical world readable at default play scale.

## 20. World-visible height

At `1920x1080`, the prior P0 fixture exposed `892` pixels between permanent panels. The P0.5 separated dock exposes `904` pixels: `+12` pixels while retaining every primary action. The original pre-P0 baseline was approximately `853` pixels.

## 21. Generation benchmark

Final same-process traversal:

| Metric | V3 retained | V4 final | Change |
| --- | ---: | ---: | ---: |
| Average chunk generation | `4.8799 ms` | `3.7956 ms` | `-22.22%` |
| Measured worst | `9.1250 ms` | `7.2100 ms` | `-20.99%` |
| First simulation tick | `0.4640 ms` | `0.4550 ms` | `-1.94%` |
| Traversal wall time | `607.452 ms` | `478.738 ms` | `-21.19%` |

The 100-seed V4 sample reports generation mean `3.5226 ms`, p50 `3.4991`, p90 `4.3061`, p99 `4.6829`, min `2.2837`, max `4.8935`.

## 22. Streaming benchmark

Both traversals issue `897` chunk requests, peak at `156` resident chunks, finish with `156`, and start with `0` active simulation cells. V4 produces the same bounded streaming shape while reducing wall time. The traversal path is intentionally far from the guaranteed start deposits; its local `sand=0 water=0` counters are not used as content evidence. The separate 100-seed physical sample supplies that evidence.

## 23. Sand destabilization

Fixture: locate supported generated V4 Sand, remove one supporting solid cell, simulate `120` ticks. Result: nonzero movement, wake-on-disturbance confirmed, physical Sand cell count exactly conserved.

## 24. Aquifer breach

Fixture: locate a generated V4 Water cell adjacent to its solid shell, open an eight-cell outlet, simulate `180` ticks. Result: nonzero fluid transfers, total conserved Water-family mass unchanged.

## 25. Remaining weaknesses

- Some fissures and long connector segments remain visibly straight in the cave contact sheet.
- The low-resolution renderer makes semantic strata broad and blocky; profiles are more varied than their preview pixels suggest.
- Topsoil, packed sediment, weathered rock, and province rock are Stone provenance profiles, not separate physical material IDs.
- Generated water tables use full cells; no partial surface cell is emitted when the analytic level falls between rows.
- Cave-system counts are descriptor intersections, not exact connected-component measurements.
- The preview deliberately hides underground content, so it communicates surface character rather than total seed richness.

## Verification

- Native release build: passed without compiler warnings.
- CTest `koalasand_core_probe`: passed.
- `tests/p05_world_quality.gd`: `154/154` passed.
- `tests/benchmark_p05_world_quality.gd`: passed.
- Contact-sheet capture: four sheets passed.
- Full repository suite: `TEST_SUITE_PASS scripts=30 elapsed_seconds=43.843`.
- `git diff --check`: passed.
- No commit, push, tag, or release performed.
