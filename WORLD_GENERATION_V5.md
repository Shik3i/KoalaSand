# World Generation V5 — Deterministic Infinite-World Architecture

New worlds use `generation_version = 5`. V1–V4 saves keep dispatching to their own generators
and are byte-identical to before this pass.

V4 solved stability. V5 solves world identity: every seed now describes a coherent world
rather than a collection of randomised chunks, and it does so roughly four times faster than
V4 did.

---

## 1. What V4 architecture was retained

Everything structural. V5 changed the content model, not the engine around it.

- Native `64×64` immutable worker buffers, main-thread publication, bounded resident set,
  simulation halos, sleeping active regions, eviction of pristine chunks.
- Coordinate-hash generation with no frame time, worker identity or shared mutable RNG.
- Versioned dispatch in `generate_chunk_data()`; V1–V4 paths untouched.
- Flat native arrays and analytic fields only; no per-cell heap allocation, no Godot object
  or Variant traffic in the hot path.
- The `get_generation_stability_report()` / `get_worldgen_quality_report()` reporting surface,
  extended rather than replaced.
- The load-bearing invariant: **world generation creates equilibrium, player action creates
  chaos.** Freshly streamed ordinary terrain has zero active cells on publication.

## 2. Root cause of the samey V4 contact sheet

Five distinct causes, all confirmed by reading `native_worldgen_v2.cpp` before changing it.

1. **One terrain operator everywhere.** `surface_height_at_v4` was three value-noise bands at
   fixed amplitudes (`0.68 / 0.25 / 0.07 × surface_amplitude`) summed identically at every x.
   Every region therefore had the same statistical silhouette; only the palette differed.
2. **Strata were surface offsets, not strata.** The "geological band" was
   `depth < sediment/3 ? 1 : depth < sediment ? 2 : depth < sediment+12 ? 3 : 4` — four bands
   parallel to the surface by construction. That is exactly why they read as repeated
   sinusoidal stripes: they *were* the surface curve, drawn four times.
3. **Caves were culled per chunk.** `generate_chunk_data_v4` collected candidate cells, sorted
   them, and kept only `floor(band_cells × cap)` of them, then eroded isolated cells — all
   inside one chunk. A feature crossing a chunk edge was cut differently on each side. That,
   not the cave shapes, is what produced the isolated black bars.
4. **Fissures and tunnels were two straight segments.** `CAVE_CRACK` was a single lean vector
   plus one midpoint; `CAVE_TUNNEL` likewise. Two segments cannot curve.
5. **Aquifers were drawn ellipses.** `aquifer_at_v4` was literally an ellipse inequality plus a
   water table cut, so every aquifer was the same oval with a flat top.

A sixth, non-visual defect: V4 tagged stone provenance with `0x8000 | layer | province`, which
collides with the gold field of the 16-bit geology-profile packing. Every V4 stone cell decodes
to at least 2 ppm gold. V5 stores a real profile instead.

## 3. V5 seed and domain architecture

`v5_hash(seed, domain, x, y, salt)` folds a generation-version tag, a per-subsystem domain
constant, both coordinates and a salt through splitmix64. Domain is a separate input to the
mix, so **adding a call inside one system cannot move another system's values.** Negative
coordinates widen through an explicit two's-complement cast, never a sign-dependent shift; all
lattice indexing uses `floor_div`.

26 domains: `warp, terrain, terrace, climate, biome_dither, province, strata, unconformity,
cave_coarse, cave_fine, tunnel, chamber, fissure, cavern, entrance, lake, aquifer, table_warp,
sediment, ore_coal, ore_iron, ore_gold, structure, scene, vegetation, start`.

Primitives: `v5_value1/2` (C2 quintic interpolant), `v5_fbm1/2`, `v5_ridged1`, plus
`v5_expand(v, gain) = vg / sqrt(1 + (vg)²)` — a soft saturation applied to every field whose
distribution matters. Plain fBm of value noise clusters near zero; that clustering is what gave
V4 a single terrain character and what gave the first V5 draft a single dominant biome.

## 4. Generation-version changes

`BuildInfo.GENERATION_VERSION` 4 → 5; `configure_world` clamp 1..4 → 1..5; dispatch gains
`generation_version >= 5 → generate_chunk_data_v5`. Existing saves carry their version in
`world_settings`, so a V4 world stays V4 forever. There is no V4→V5 migration seam and none is
intended for this playtest stage.

## 5. Macro-region design and scales

| Field | Scale (cells) | Contract |
| --- | --- | --- |
| Simulation chunk | 64 | streaming and storage only — never a geological unit |
| Generation halo | 3 | padded carve buffer, makes neighbourhood rules position-pure |
| Continentalness | 4096 | basins, plains, uplands |
| Domain warp | 2560 (±430) | breaks the sampling lattice |
| Orogenic uplift | 1792 | highland belts, mesa regions |
| Ruggedness | 2304 | selects which landform operators run |
| Ridge / hill / micro | 448 / 704 / 176 / 52 | meso relief, gated by ruggedness |
| Temperature / moisture | 3584 / 2432 | independently warped climate |
| Geological province sites | 968 × 616 | warped Voronoi, absolute coordinates |
| Bedding package | 68–172 per bed | absolute-y bedding planes |
| Cave descriptors, coarse | 224 × 176, reach 286 | tunnels, chambers, fissures, caverns |
| Cave descriptors, fine | 112 × 96, reach 146 | short connectors |
| Coal fields | 236 × 188, reach 150 | bedding-parallel lenses |
| Water-table regions | 1408 (warped ±54) | local water tables + barriers |
| Lake regions | 704 | basin detection |
| Scene candidates | 1216 × 704 | authored natural formations |
| Structure candidates | 768 / 1088 / 2176 | per structure type |

Every scale is coprime-ish with 64 and none is chunk-aligned, so a chunk boundary can never
become a feature boundary.

## 6. Surface terrain algorithm

`v5_terrain_fields(x)` solves the character weights once per column:

```
continental = expand(fbm(4096), 2.35)
uplift      = expand(fbm(1792), 2.20)
roughness   = 0.5 + 0.60 · expand(fbm(2304), 1.90)
highland    = smoothstep(-0.08, 0.66, uplift)
basin       = smoothstep( 0.05, -0.72, continental)
terrace     = smoothstep( 0.28,  0.86, uplift · (1.20 − roughness))
```

`v5_surface_from()` then runs operators *selected* by those weights rather than a fixed stack:
a broad base from continentalness and uplift; a **ridged** band gated by `highland · roughness`
(so ridges only exist on rugged uplands); two meso bands scaled by roughness and suppressed in
basins; a micro band; a basin-lowering term; and a **terracing operator** that quantises height
into flat treads with short risers wherever `terrace` is high, producing mesas and escarpments
that a plain amplitude stack cannot make.

## 7. Climate fields

Four continuous fields, shared with the terrain solve:

- `temperature` — fbm(3584), expanded, minus 0.46 × normalised altitude.
- `moisture` — fbm(2432), expanded, minus 0.42 × highland (rain shadow), plus 0.36 × basinness.
- `ruggedness` — `−0.88 + 1.30·roughness + 1.05·highland`, i.e. derived from the same weights
  the landform operators use. Deriving it from an unrelated noise channel was why the first
  draft never produced a rugged biome.
- `basinness` — `1.75·basin − 0.78 − 0.30·continental`.

Temperature and moisture use their own domain warps so climate boundaries do not lock onto
terrain boundaries.

## 8. Biome-selection algorithm

Weighted squared distance in the 4-D climate space to each profile centre, times a deterministic
patch dither at 53 and 197 cells, argmin wins. `biome_margin` (1 − best/second) is reported for
debugging. The dither makes a boundary interfinger over tens of cells instead of forming a
vertical wall; at 0.22 strength borders flickered (median region 60 cells), at 0.13 with longer
wavelengths the median region is ~310 cells.

## 9. Biome set and transition logic

Five archetypes, all expressed with existing materials:

| Biome | t | m | rugged | basin | Character |
| --- | ---: | ---: | ---: | ---: | --- |
| `temperate_plain` | 0.05 | 0.28 | −0.55 | 0.05 | moderate slopes, deep soil, trees, moderate sand |
| `arid_dunes` | 0.78 | −0.82 | −0.45 | −0.15 | thin soil, thick loose Sand, almost no lakes or trees |
| `rocky_highland` | −0.28 | −0.12 | 0.82 | −0.72 | exposed rock, minimal sediment, most cave entrances |
| `wet_lowland` | 0.26 | 0.84 | −0.70 | 0.86 | thick sediment, lakes, dense vegetation |
| `badlands` | 0.62 | −0.42 | 0.36 | −0.30 | terraced, banded sediment, moderate sand |

No snow or ice: the material and thermal systems would have to carry them, and inventing an
incomplete material to raise a count is not an improvement.

## 10. Geology province system

Provinces are a **warped Voronoi field in absolute world coordinates** (`geology_province_at_v5(x, y)`),
not a floor-divided grid. Two domain-warp fields displace the query point before the nearest-site
search, so contacts are irregular curves and diagonals. Site type is a weighted draw, so karst
and mineralised belts stay rarer than sedimentary basins.

| Province | weight | cave density | horizontal bias | permeability | coal | iron | gold |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `sedimentary_basin` | 1.35 | 1.00 | 0.84 | 0.72 | 1.30 | 0.55 | 0.20 |
| `karst_platform` | 0.70 | 1.55 | 0.66 | 1.00 | 0.45 | 0.45 | 0.25 |
| `granite_massif` | 1.05 | 0.50 | 0.26 | 0.26 | 0.30 | 0.55 | 1.05 |
| `mineralised_belt` | 0.55 | 0.88 | 0.44 | 0.52 | 0.85 | 1.85 | 1.65 |
| `volcanic_terrane` | 0.75 | 0.66 | 0.38 | 0.30 | 0.35 | 1.15 | 0.45 |

Province is sampled once per four rows per column with a per-column phase offset. Sampling it
per chunk produced 64-cell staircases; the phase offset breaks the sampling lattice so a contact
reads as an irregular geological boundary.

## 11. Depth and material rules

Depth below the **local** surface drives soil, packed sediment and the weathering front.
Absolute world y drives bedding planes, provinces and the deep-mineralisation gain. The two are
separated deliberately: the same absolute y inside a mountain and in a valley must not receive
the same near-surface material.

## 12. Stratigraphy algorithm

A global bedding cumulative (`68 + hash % 104` per bed, x-independent) fixes the package order.
Per column, each bedding plane is

```
bed_y(k, x) = cumulative(k)
            + fold(x)                       shared regional warp: 118·fbm(2560) + 34·fbm(928)
            + 12 · fbm(x, control_k)         per-bed irregularity, own control scale per k
            − thinning_k(x)                  per-bed local thinning mask
```

then clamped to lie below the weathering front and below the previous bed. The shared fold makes
beds dip and fold together the way a real region does; the per-bed irregularity and thinning make
them non-parallel, with thickness varying and beds locally pinching thin. Because the boundaries
are absolute-y and the weathering front follows the surface, beds **truncate against an
unconformity**, and which bed subcrops changes along x. That truncation is what makes a section
read as geology rather than as a stack of sine waves. Only the beds inside the chunk's y window
are evaluated; the amplitude bound guarantees the window result equals the full recurrence.

## 13. Cave-system architecture

A cave is never "cave pixels". Descriptors are addressed in world coordinates, expanded into
varying-radius capsules and angularly perturbed blobs, and rasterised into a **70×70 padded
buffer**. Because the descriptor set for a world position is identical no matter which chunk
asks, a system crosses chunk boundaries intact.

Volume is controlled **by construction** (descriptor density × province cave density × a depth
gate), not by a per-chunk cull. The stability report's void budget is therefore now a *regional
aggregate* outlier guard (`0.18 / 0.26 / 0.30`), and `void_budget_applies_to` reports which
semantics apply: a single chunk sitting inside a large cavern is legitimately almost all void,
and capping per chunk is precisely what fragmented V4.

## 14. Cave archetypes

- **Directional tunnel** — a correlated heading walk with a restoring force toward the regional
  trend, a province-dependent vertical squash, radius varying along the path and tapering at the
  ends, plus 0–2 branches that keep the system connected.
- **Chamber cluster** — 3–6 overlapping blobs whose outline is perturbed by 2nd, 3rd and 5th
  angular harmonics evaluated through a Chebyshev recurrence (no trigonometry in the inner loop),
  plus 1–3 exit tunnels so a chamber is part of a network rather than a sealed bubble.
- **Fracture** — directionally biased but *stepped*: heading wobble, a lateral jog every third
  step, a `sin^0.55` radius taper that reaches zero at both terminations, and an optional branch.
  This is the direct replacement for V4's straight two-segment fissure.
- **Rare large cavern** — 6–9 large blobs behind an extra rarity gate and a depth floor, with
  2–4 connectors.
- **Surface entrance** — only for a system whose top already reaches the shallow zone, gated by
  the biome's entrance bias, tapering from 4.6 to 2.0 cells. It is the only archetype allowed
  through the roof, which makes an entrance a designed feature rather than an accidental hole.

## 15. Cave connected-component statistics

Real BFS over materialised chunks (`get_cave_topology_report`). 24-seed sample over a 10×12-chunk
region including the surface:

| Metric | mean | p50 | p90 | min | max |
| --- | ---: | ---: | ---: | ---: | ---: |
| Components | 21.4 | 22 | 27 | 12 | 32 |
| Largest-component fraction | 0.273 | 0.254 | 0.437 | 0.152 | 0.627 |
| Median component size (cells) | 822 | 757 | 1265 | 344 | 1464 |
| Median passage width | 8.3 | 8 | 10 | 7 | 10 |
| Isolated fragments (≤6 cells) | 0.92 | 1 | 2 | 0 | 3 |
| Flooded fraction | 0.308 | 0.272 | 0.714 | 0.0 | 0.808 |
| Surface-connected components | 0.63 | 1 | 1 | 0 | 2 |

The report also carries dead-end and junction counts, vertical/horizontal extent distributions
and the chamber-to-tunnel ratio.

## 16. How geology changes cave topology

Province profile drives the archetype weights, the overall cave density and the `horizontal_bias`
that squashes a tunnel's vertical step. Sedimentary basins produce mostly horizontal passages;
karst is 1.55× denser and chamber-dominated; granite massifs are half as porous and
fissure-dominated; volcanic terrane is fissure-heavy with occasional caverns.

## 17. Surface lake algorithm

Resolved **once per candidate region**, never per column: sample the surface at 32 points, take
the basin floor and the lower of the two confining rims, require ≥6 cells of relief, and set the
waterline one cell below the spill. A region only carries a lake when **both of its edge columns
stand above that waterline**, which is what guarantees two neighbouring waterlines can never be
laterally adjacent. Every column in the region uses the same waterline and the same fractional
top-row mass, so the lake is settled by construction. Lake probability scales with the biome's
lake bias.

## 18. Aquifer / water-table algorithm

There are no aquifer shapes. There is a **local water table per region** (1408 cells wide, with a
warped boundary that wanders ±54 with depth), whose depth below the local surface is a function of
province permeability, regional moisture and a hash — clamped to 74–660 cells. About 64% of
regions are wet; the rest are dry at all depths.

A void cell floods iff it lies below its region's table. **The shape therefore comes from geology
plus cave geometry plus the table**, which is what removes the repeated-oval grammar entirely: a
tunnel gradually submerges, a chamber is half full, a fissure is a flooded slot.

Where two neighbouring regions carry different tables, an **impermeable barrier** suppresses
carving in an 11-cell band on each side of the (irregular, depth-warped) contact, below the
shallower of the two tables. This is the same device Minecraft uses for aquifer separation, and
it is what makes "flooded to a flat level" exactly true rather than approximately true.

## 19. Fractional water handling

`GeneratedChunk` gained an optional `material_amount` plane. The generator records partial cells
during the material pass and builds the plane **after** it, initialised from the finished
materials — building it lazily mid-pass made every full water cell read as mass 0 and woke the
entire body on the first tick.

The analytic waterline is stored in mass units (`level·255 + fraction`), so the row containing the
surface gets `255·(level+1) − table` and every row below is full. Because the level is constant
across a region, all top-row cells share one mass and the free surface is stable by construction.
Cells below 24 mass are emitted as air rather than as a degenerate sliver. Verified: the plane
survives a save round trip and total conserved Water-family mass is unchanged.

## 20. Sediment algorithm

Loose Sand is a deposit, not a painted threshold. A surface deposit needs a locally flat column,
a dune/patch drive above threshold scaled by the biome, **and** both neighbouring columns standing
at or above its base — exactly the condition the falling-sand solver uses to stay asleep. After
cave rasterisation, any column the carve buffer undercuts loses its deposit, because a surface
entrance is allowed to pass straight through one.

Cave-floor sediment is placed where the three cells beneath a void cell are all solid, at a rate
scaled by province permeability, using the padded buffer so the test is position-pure.

## 21. Resource abundance model

Hierarchical, per §24: regional fertility field (fbm at 3072) × province coal richness × a depth
curve (ramp 38→130, taper 900→2400) → candidate acceptance → vein geometry. No cell rolls a
percentage.

Iron and gold are **composition, not materials** — consistent with `MATERIAL_CONSERVATION.md`,
where refined Iron and Gold only exist downstream of processing. Iron follows broad altered zones
(fbm at 768 × province iron richness); gold follows thin **ridged** sheets gated by depth and
province gold richness, which is why it appears as dipping vein-like streaks rather than blobs.

## 22. Vein-generation algorithm

Coal veins are bedding-parallel lenses: a five-node polyline with a shallow dip, thickness
following `sin(πt)` so the lens is thickest in the middle and tapers at both ends. Mineralisation
is a field rather than a polyline, so it forms belts and sheets. Scene lenses (`kind = 1`) raise
the host rock's iron, heavy and gold quantiles in place.

## 23. Provenance and conservation implications

V5 stone stores a **real 16-bit geology profile id**, so `get_geology_profile()` decodes a
meaningful composition for every cell. The quantised silica field doubles as the rock family
identifier (`q_silica >> 1` is unique per rock), which lets the renderer colour a cell straight
from its stored composition — no extra per-cell state, no field evaluation during rendering, and
the section a player reads *is* the material data. Local variation goes into the iron and heavy
channels, which is also where real alteration shows up.

Nothing invents mass. Alteration raises the ore-bearing constituents of the host rock; it never
introduces a new material. Scene "solid fill" may only close an air cell, never a water cell.
The V4 `0x8000` gold collision is gone; the test suite asserts that gold-bearing stone is a
minority of deep stone rather than all of it.

The existing 16-bit packing was kept deliberately. Widening it would express real rock chemistry
better (limestone cannot be represented below 0.68 silica fraction) but would change decoding for
every existing save and touch the processing and conservation pipeline. That is a separate,
riskier change — see §43.

## 24. Structure-candidate architecture

`get_structure_candidates(area, type)`: three types (`surface_ruin` 768, `underground_facility`
1088, `deep_vault` 2176) each with its own domain salt, region size, separation margin, depth
range and rarity. A candidate is derivable from seed + domain + region coordinate alone — no
global scan, no central list — and the suite asserts that a candidate found in a narrow query is
identical in a wide one. Candidates never land inside the protected start core. This is the
placement foundation only; no structure content is placed yet.

## 25. Natural / pixel-scene architecture

`v5_gather_scenes` places authored formations against host constraints (depth range, province,
mirror transform, weighted type draw) using **nothing but the primitives the generator already
rasterises**, so a scene inherits conservation, stability and chunk-order independence rather than
needing its own guarantees. Three implemented:

- `geode_pocket` — a sealed perturbed cavity with a mineralised lining.
- `collapsed_arch` — a wide low chamber left spanned by two rock pillars (solid fill).
- `mineral_exposure` — a bedding-parallel lens of altered, ore-bearing rock.

`get_natural_scene_candidates()` exposes the candidate set for tooling.

## 26. Start-region guarantees

Within the start radius, every sampled seed provides: a buildable surface run, accessible loose
Sand, a shallow coal seam, a reachable water table, an early cave route with its own surface
entrance, and a protected build core (`|x| < 108`, depth < 210) containing no open void.

Crucially the shaping is applied to the **fields**, not the height. A `calm` weight suppresses
ruggedness, highland, terrace and basin near the origin, and climate drifts toward habitable;
nothing is pinned to a fixed elevation. There is no circular tutorial island — the start sheet
shows the start blending into the same geology as everything else, with each seed getting a
different province stack, hydrology and lake presence.

## 27–29 & 34. Determinism tests

- **Chunk order** — four request orders (forward, reverse, and two permutations) over six chunks
  produce identical region content hashes.
- **Worker count** — 1, 2, 4 and 8 generation workers produce the identical hash.
- **Far jump** — a chunk generated after traversing eleven chunk columns equals the same chunk
  generated directly, with nothing between it and the origin.
- **Legacy** — versions 2, 3, 4 and 5 each dispatch to their own generator and produce four
  distinct hashes.
- **No chunk-boundary truncation** — a content hash cannot catch a feature that one chunk clips
  and its neighbour does not, because every chunk still agrees with itself. The suite instead
  measures the density of one-cell solid plugs (solid, void above, void below) on boundary rows
  against interior rows. Measured `0.000` on boundary rows versus `0.028–0.060` on interior rows
  across three seeds.

That test exists because it caught a real bug. The surface entrance is the one shape not clamped
into its descriptor reach box — it runs all the way up to the surface — so rejecting a descriptor
on the reach box alone admitted it for the chunk below and rejected it for the chunk above, and
the shaft was capped exactly on the boundary row. It surfaced as six unsupported Sand cells in one
seed out of a hundred; the underlying defect was a visible seam and the exact failure mode this
generator exists to eliminate.

## 35. Negative-coordinate tests

Left and right of the origin hash differently; fewer than 160 of 399 mirrored column pairs share
a surface height (a truncating divide would make all of them match); the largest surface step
across x = 0 is ≤ 6 cells, so there is no seam; and terrain 2560 cells left of the origin
publishes settled.

## 30. 1,000-seed statistical summary

Analytic sampling, no chunks materialised, 6.0 s for 1,000 seeds. Regenerate with
`tests/benchmark_v5_worldgen.gd`.

`0` seeds without water, `0` without Sand, `0` without caves.

| Metric | mean | p10 | p50 | p90 | p99 | min | max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Surface relief over 4096 cells | 148.0 | 89 | 145 | 210 | 272 | 40 | 307 |
| Mean surface slope | 0.604 | 0.375 | 0.594 | 0.867 | 1.04 | 0.222 | 1.299 |
| Longest flat run (cells) | 1054 | 344 | 872 | 1976 | 3272 | 156 | 4100 |
| Biome region width (cells) | 489 | 32 | 316 | 1192 | 2420 | 4 | 3884 |
| Surface lake columns | 39.5 | 0 | 0 | 138 | 262 | 0 | 383 |
| Sand columns per 1025 sampled | 306 | 88 | 252 | 612 | 823 | 37 | 916 |
| Wet water-table fraction | 0.638 | 0.429 | 0.714 | 0.857 | 1.0 | 0.143 | 1.0 |
| Water-table depth (cells) | 371 | 299 | 371 | 446 | 516 | 195 | 565 |
| Nearest wet region (cells) | 926 | 704 | 704 | 2112 | 3520 | 704 | 4928 |
| Cave systems in window | 15.3 | 11 | 15 | 20 | 24 | 5 | 28 |
| Coal fields in window | 27.3 | 15 | 26 | 41 | 56 | 5 | 65 |
| Shallowest coal depth | 129 | 69 | 115 | 195 | 354 | 47 | 683 |

## 31. Biome coverage statistics

Every biome is reachable at a meaningful frequency; none crowds another out.

| Biome | coverage |
| --- | ---: |
| `temperate_plain` | 35.5% |
| `rocky_highland` | 27.2% |
| `badlands` | 18.0% |
| `wet_lowland` | 11.6% |
| `arid_dunes` | 7.8% |

For reference, the first V5 draft produced roughly 85% temperate and effectively zero
highland, because ruggedness was derived from finite differences of a too-narrow terrain field
and never reached the highland profile centre. That was found by the coverage statistic, not by
looking at screenshots.

## 32. Geology coverage statistics

| Province | coverage |
| --- | ---: |
| `sedimentary_basin` | 31.7% |
| `granite_massif` | 24.2% |
| `volcanic_terrane` | 16.4% |
| `karst_platform` | 15.4% |
| `mineralised_belt` | 12.2% |

## 33–34. 100-seed physical sample

`0` unstable seeds, `0` seeds over the void budget, `0` seeds without Sand, `15` of 100 with no
Water in the sampled `7 × 20` chunk region (dry table regions are intentional).

| Metric | mean | p50 | p90 | p99 | min | max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Sand cells | 1646 | 1500 | 2365 | 3208 | 975 | 3410 |
| Water cells | 20698 | 18177 | 42195 | 59729 | 0 | 81084 |
| Ore cells | 3185 | 3009 | 5314 | 7446 | 469 | 7568 |
| Shallow void fraction | 0.051 | 0.047 | 0.084 | 0.112 | 0.015 | 0.113 |
| Deep void fraction | 0.094 | 0.082 | 0.167 | 0.255 | 0.016 | 0.281 |

## 36. Resource distances and quantities

Shallowest coal p50 `115` cells below the local surface, p90 `195`, min `47`; `27.3` coal fields
per sampled window. Nearest wet water-table region p50 `704` cells from spawn. The guaranteed
start seam sits at depth `36–48` for every seed.

## 37. Contact-sheet artefacts

`artifacts/v5-worldgen/contact-sheets/` — 20 deterministic seeds in a 5×4 grid, sampled at
x = 5824 so the guaranteed start features do not dominate every tile:

`surface`, `shallow`, `deep`, `caves`, `cave-components`, `hydrology`, `biome`, `province`,
`strata`, `sediment`, `resources`, `start`, `start-constraints`, plus the seed-independent
`climate-space.png`, and `manifest.json`.

## 38. Debug-map artefacts

`get_worldgen_debug_field(area, field, stride)` renders fields 0–12: final material section,
biome, temperature, moisture, province, strata, cave archetype, hydrology, sediment, resources,
start constraints, climate space, connected components. Single-seed full-resolution frames go to
`artifacts/v5-worldgen/detail/` via `scripts/capture_v5.ps1 -Detail <seed>`.

`get_worldgen_v5_cell(cell)` answers "why is this cell here?" — biome, climate vector, province,
horizon, bed index, rock, cave roof depth, aquifer region, water table, geology profile, material
and amount. It stores nothing per cell; the cost lives entirely in the inspection call.

## 39. Climate coverage diagnostic

`climate-space.png` draws the biome table itself as a 2×2 panel of temperature-by-moisture slices
at low and high ruggedness and basinness — the equivalent of Factorio's terrain-range
visualisation, so a parameter change that makes a biome unreachable is visible immediately.

## 40. Benchmarks and latency

Same traversal fixture as the P0.5 report: 897 chunk requests, peak 156 resident chunks.

| Metric | V4 | V5 | Change |
| --- | ---: | ---: | ---: |
| Average chunk generation | `3.6929 ms` | `0.8429 ms` | `-77.17%` |
| Measured worst | `6.4850 ms` | `1.4740 ms` | `-77.27%` |
| Traversal wall time | `464.618 ms` | `143.500 ms` | `-69.11%` |
| First simulation tick | `0.4610 ms` | `0.1930 ms` | `-58.13%` |
| Initially active cells | `0` | `0` | — |

Per-chunk latency, 900 chunks generated one at a time on a single worker so the sample is real
latency rather than a throughput average smeared across the pool:

| Percentile | V4 | V5 |
| --- | ---: | ---: |
| mean | `3.4270 ms` | `0.8508 ms` |
| p50 | `3.5220 ms` | `0.8490 ms` |
| p90 | `4.9600 ms` | `1.0110 ms` |
| p95 | `5.4930 ms` | `1.0960 ms` |
| p99 | `8.2180 ms` | `1.2510 ms` |
| max | `10.9380 ms` | `1.4390 ms` |

V5 is faster despite doing considerably more, for one structural reason: V4 evaluated
`cave_type_at_v4` per cell, and each call rescanned a 3×3 descriptor neighbourhood with several
`surface_height_at_v4` evaluations inside it. V5 gathers descriptors **once per chunk** and
rasterises each shape over its own bounding box, so the work is proportional to the void volume
rather than to the cell count. The p99 improving by 6.6× matters more than the mean: that is the
long tail that produces traversal stutter.

## 41. Sand destabilisation test

Locate a supported generated Sand cell, remove one supporting solid cell, simulate 120 ticks.
Result: nonzero movement, and the physical Sand cell count is exactly conserved.

## 42. Aquifer breach test

Locate a generated Water cell adjacent to its containment, open an eight-cell outlet, simulate
180 ticks. Result: nonzero fluid transfers, total conserved Water-family mass unchanged.

## 43. Remaining weaknesses

> Every item below was addressed in the follow-up pass documented in
> `RELEASE_POLISH_PASS.md`, which also records the measured before/after figures and what is
> still open. The list is kept here as the honest state of this pass at the time it shipped.


Stated plainly, in rough order of how much they still show.

1. **The surface silhouette is still gentle at gameplay zoom.** Relief is a p50 of 145 cells
   over 4096, so a single screen of ~200 cells sees only a few cells of change in a plain.
   Highlands, mesas and basins are clearly distinct on the contact sheets, but a player standing
   in a `temperate_plain` will read the ground as flat. Raising this further trades against
   factory buildability and was left as a tuning decision rather than pushed unilaterally.
2. **Climate space is used unevenly.** `climate-space.png` shows `arid_dunes` occupying a large
   region of the temperature/moisture plane while only reaching 7.8% of the world, and
   `temperate_plain` occupying a thin sliver while reaching 35%. Coverage is acceptable but the
   profile centres are not where the sampled distribution actually lives; a proper fit would
   move the centres toward the realised distribution.
3. **Province contacts are razor-sharp.** A contact swaps the whole rock sequence along one
   clean curve. It reads as a fault, which is attractive, but real facies changes are gradual
   and there is currently no interfingering at a province boundary the way there is at a biome
   boundary.
4. **The 16-bit composition packing is too narrow to be honest.** Every rock decodes to between
   0.68 and 0.96 silica fraction, so limestone cannot claim its real carbonate composition. The
   quantised values are internally consistent and drive colour and processing correctly, but the
   absolute fractions are compressed. Widening the packing would change decoding for every
   existing save and touch the conservation pipeline, so it was deliberately not attempted here.
5. **Surface entrances are sparse.** 0.79 surface-connected components per 10×12-chunk region,
   with some regions at zero. Exploration by descending a natural entrance is possible but not
   reliable; most access is still by digging.
6. **Jigsaw/connector structures are not implemented.** Only the candidate-placement foundation
   and the pixel-scene stamping path exist. Structures place no content yet.
7. **Deep coal can be locally dense.** The regional fertility model intentionally produces rich
   belts, and the richest tiles on the `deep` sheet approach a resource wall over a few hundred
   cells. Global quantity is controlled (p99 of 7,446 cells in a `7 × 20` chunk region), but
   there is no upper bound on local concentration.
8. **The deep world below the bedding packages is uniform in kind.** Bedding repeats with a
   fixed period per province, so at extreme depth a section repeats its formation sequence
   rather than progressing into something new.

---

## Verification

- Native release build: clean, no compiler warnings.
- CTest `koalasand_core_probe`: passed.
- `tests/v5_worldgen.gd`: 237/237 checks passed.
- `tests/benchmark_v5_worldgen.gd`: passed.
- Full repository suite: `TEST_SUITE_PASS scripts=31 elapsed_seconds=48.678`.
- Contact sheets: 13 categories + climate space rendered.
- No commit, push, tag, or release performed.

## Fixed in passing

`reset()` stops the generation workers and only restarts the render pool, so a world restored
from a snapshot had no thread able to drain the generation queue: the first chunk streamed after
a load blocked `flush_generation()` **forever**. Reproduced on V4 as well, so it predates this
pass. Fixed by restarting the generation workers at the end of `deserialize_world_snapshot`, and
covered by a regression check in the V5 suite.
