# V5 Polish and Release-Readiness Pass

Follow-up to `WORLD_GENERATION_V5.md`. This pass closes the weaknesses that report listed as
open, then audits and fixes the player-facing surface: world presentation, HUD, menus, panels
and settings.

Nothing was committed, pushed, tagged or released.

---

## Part 1 — World-generation weaknesses closed

Every item in `WORLD_GENERATION_V5.md` §43 was measured before and after. Numbers are from
`tests/benchmark_v5_worldgen.gd` over 1,000 analytic seeds unless noted.

### 1. Relief at gameplay zoom

The 4096-cell relief figure looked healthy while a single screen still read as flat ground, so
a `local_relief_256` metric was added: the surface range inside each 256-cell window, which is
roughly what one screen shows.

The fix was contrast, not uniform bumpiness. A ridged band, a new 320-cell meso band and the
existing 704/176 bands were all raised, and their roughness gate was steepened from
`0.32 + 0.68·roughness` to `0.14 + 0.86·roughness`. A plain therefore gets *less* than before
and a highland considerably more, which also protects buildable ground and Sand deposits.

| local relief over 256 cells | before | after |
| --- | ---: | ---: |
| p10 | 8 | 12 |
| p50 | 23 | 31 |
| p90 | 51 | 73 |
| p99 | 85 | 124 |

### 2. Climate space used unevenly

The diagnostic found the real cause. `basinness` was driven by a smoothstep gate, so it was
bimodal: median `-0.74`, jumping to `+1`. Half the biome table sat in a region of climate space
the world essentially never visited. Deriving it from continentalness directly
(`-1.15·continental + 0.45·basin - 0.08`) makes it inherit that field's spread, and the profile
centres were refitted against the measured distribution.

| field | median before | median after |
| --- | ---: | ---: |
| basinness | −0.74 | −0.02 |

Coverage stayed balanced across all five biomes and the terrain/biome correlation is now
visible on the contact sheet: highlands sit on raised ground, wetland in depressions.

### 3. Province contacts interfinger

Each candidate distance in the Voronoi solve is perturbed by a shared fine-scale field times a
per-site sign. That only changes the outcome where two sites are nearly equidistant, so a
contact interleaves over tens of cells while the interior of a province is untouched.

### 4. Composition: one decoder instead of two

This turned out to be worse than "the packing is narrow". `composition_for()` — the
**authoritative conserved-mass path** — and `get_geology_profile()` — the **reported
composition** — decoded *different, overlapping bit windows of the same 16-bit id*. The number
a player was shown and the number the conservation ledger used were not the same quantity.

V5 worlds now share `v5_profile_fractions()`: one decoder producing six fractions that sum to
exactly one full cell, with a power response on the silica field so a carbonate can read as
quartz-poor. V1–V4 keep their original decoding untouched. Conservation tests pass unchanged,
which is expected: the ledger balances sums, and the sums still balance.

### 5. Surface entrances

Breach probability `0.44 → 0.66` of the biome bias and the eligible gap widened from
`(24, 210)` to `(18, 268)`. Surface-connected components per 10×12-chunk region rose from
`0.63` to `1.46` mean, p50 `1`, p90 `3`, and entrances are now visible on the surface sheet.

### 6. Jigsaw structures

Implemented, and now stamped on the surface as well as underground. Five room pieces (`hall`, `chamber`, `shaft`, `vault`, `cell`) carry connection
ports; a seeded builder walks open ports, attaches a piece offering the matching port, and
rejects anything overlapping what it has already placed. The assembly depends only on the
candidate region coordinate, so it is identical for every chunk that can see it and needs no
shared state.

Rooms rasterise as hollow interiors joined to the carve buffer plus a masonry shell recorded
separately, so a cave system crossing a ruin cannot eat its walls.

Surface ruins are placed on ground flat enough to have been built on and sunk fully below the
surface, so they are found by digging rather than dropped on the skyline. `get_structure_candidates()`
previously reported *zero* surface ruins, because it drew candidates from a 2-D region lattice
while the generator anchors them to the ground — the depth filter rejected essentially every
one. Both now share the same surface-anchored rule.

### 7. Ore clumping

A 2×2 grid window accepted 4 of 4 coal fields in half of all seeds. A rank filter against the
eight neighbours (a field must out-rank at least three of them) breaks up the saturation
without thinning isolated deposits, with base acceptance raised to compensate. It stays a pure
function of the grid cell, so it cannot depend on which chunk asked.

| coal clumping (max fields in a 2×2 window) | before | after |
| --- | ---: | ---: |
| mean | 3.47 | 3.20 |
| p50 | 4 | 3 |
| min | 1 | 2 |

### 8. Deep facies progression

Bed packages now thicken with depth (`base + base·index/14`), and `v5_deep_facies()` grades the
sequence from sedimentary cover into gneiss and then granite basement. The deep world stops
repeating its shallow formation order.

### 9. Two more cross-chunk determinism bugs

Enabling surface ruins surfaced a Sand cell resting on nothing. Tracking it down found a
second instance of the bug class the first pass fixed, and then a third.

**Entrance descriptor rows.** A surface entrance runs from its system all the way to the
surface, so its extent is not bounded by the descriptor reach that every window is sized from.
The first pass fixed the *anchor bounding-box* test but not the **grid-row range**: a chunk
containing the surface computed its row window from its own depth span plus reach, and so never
scanned the deeper rows whose entrances reach up into it. Chunk `(109, 0)` gathered 34 capsules
where chunk `(109, 1)` gathered 49, and the shaft simply stopped at the boundary. Both now
gather 61.

**A test that could actually catch it.** The plug-density heuristic from the first pass was too
weak — it looks for one-cell plugs and this produced a larger cap. `get_worldgen_debug_chunk_view()`
asks two neighbouring chunks the same question about the same cell, and the suite now asserts
they agree across 144 boundary cells per seed. A content hash structurally cannot catch this:
a chunk that silently omits a feature still agrees with itself.

**A Sand backstop rather than a fourth support rule.** Surface deposits, cave floors and
authored rooms each reason about support from a different angle, and each rule was individually
defensible. The generator now ends with a sweep over the finished materials: a Sand cell with an
open cell beneath it becomes host rock. It is the invariant itself rather than another
approximation of it.

---

## Part 2 — Release-readiness audit of the player-facing surface

Found by capturing all 30 player surfaces across `1600×900 / 1920×1080 / 2560×1440` at
`100 / 125 / 150 %` and reading them.

### Release blockers found and fixed

**Character mode spawned buried in rock.** `get_character_spawn()` returned the *V4* surface
height for a V5 world. The character began inside solid ground with only a small discovered
pocket visible — Character mode was unplayable on any new world. A sweep of every remaining
`generation_version >= 4` dispatch found three more stale paths (architecture reporting, pass
hashing, debug sampling).

**A prototype showcase light rendered in every player view.** An unreferenced orange
`PointLight2D` pinned to one world coordinate washed a large warm glow across the terrain in
the first frame of every mode. Removed, along with its now-unused gradient sub-resources.

**A developer beacon marker rendered in every player view.** A crosshair drawn at a fixed
world cell. It now appears only alongside the other chunk-debug overlays.

**The release package could not be built at all.** `scripts/package_playtest.ps1` used three
PowerShell 7-only APIs — `[System.IO.Path]::GetRelativePath`, `[SHA256]::HashData` with
`[Convert]::ToHexString`, and `Set-Content -Encoding utf8NoBOM`. Only Windows PowerShell 5.1 is
present here, every other script in the repository runs under 5.1, and nothing documented a
PowerShell 7 requirement. The script had evidently never been executed in this environment.
Rewritten against APIs both versions have, preserving the manifest digest and the BOM-free
manifest bytes. It now produces the export end to end.

**Streaming deadlocked after loading a save.** `reset()` stops the generation workers and only
restarts the render pool, so a restored world had no thread able to drain the generation
queue: the first chunk streamed after a load blocked `flush_generation()` forever. Reproduced
on V4, so it predates the V5 work. Fixed in `deserialize_world_snapshot`, with a regression
check in the V5 suite.

### Presentation and QoL fixes

**Rock read as flat paint.** A bed covering a whole screen was one uniform colour. Added
laminae — a few-cell horizontal grain warped along x — plus a coarse mottle and the existing
per-cell grain. Mid-frequency structure, not more static.

**The New World preview was a geological column, not a landscape.** It sampled 700 cells of
underground with the horizon squeezed into the top quarter, and it re-solved a full column for
each of 83,000 pixels. Rebuilt as a landscape postcard: sky gradient, parallax ridge, real
surface relief against a fixed datum, canopy where the biome supports it, surface water and the
shallow geological column — with one column solve per preview column.

**The preview text named a province from the V2 macro sample**, unrelated to the world the
player would get. Added `get_world_preview_summary()`, which reports the spawn biome, terrain
character, surface water and bedrock province in player language. Caves, ore and groundwater
stay undiscovered.

**The overview map was 55% empty and its legend named markers nothing drew.** The map now
fills the panel and the camera region and world centre are actually drawn on it.

**Pause buried the exit actions.** Save / Save and quit to menu / Save and exit were at the
bottom of a long settings scroll; leaving the game required discovering a scrollbar. Session
actions now sit directly under Resume. The world-name field had only a placeholder, so once a
world had a name it read as an unlabelled text box — it now has a label. Volume sliders gained
numeric readouts.

**Check states were unreadable.** `CheckBox` and `CheckButton` had no authored theme at all,
so they inherited the Button slab and Godot's stock icons: an unchecked box rendered with *no
visible box*. Added authored styling with drawn box and tick icons at every UI scale, so state
survives a monochrome read.

**The Inspector painted everything one colour.** A failing machine set the whole label to
warning amber — title, section headers, explanation and every state value. Rebuilt as rich text
so the type hierarchy survives while the failure is still marked.

**The Codex printed its summary twice** whenever an entry repeated it as the first section.

**The Research tree clipped cards at its default framing** and a drag could lose the tree
entirely. Added content-bounds clamping that centres the tree when it fits and never pans past
its edges, and lowered the default zoom so more of the tree is visible.

**Food specimens floated in the sky.** Vegetation placed a specimen on the first empty cell
above *anything*, including tree canopies. It now requires ground beneath it.

---

## Measured after the pass

100 seeds, `7 × 20` chunk region each: `0` unstable, `0` over the void budget, `0` without Sand,
`14` with no Water in the sampled region (dry table regions are intentional).

| Metric | mean | p50 | p90 | p99 | min | max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Generation per chunk (ms) | 0.962 | 0.963 | 0.994 | 1.022 | 0.905 | 1.073 |
| Sand cells | 1560 | 1392 | 2271 | 3238 | 645 | 3420 |
| Water cells | 21201 | 18377 | 41008 | 59398 | 0 | 87003 |
| Ore cells | 3032 | 2888 | 5103 | 6626 | 469 | 6704 |
| Shallow void fraction | 0.056 | 0.049 | 0.093 | 0.125 | 0.016 | 0.131 |
| Deep void fraction | 0.093 | 0.078 | 0.168 | 0.254 | 0.016 | 0.283 |

Cave topology over 24 seeds: `21.9` components, largest-component fraction `0.264`, median
component `866` cells, median passage width `8`, flooded fraction `0.302`, surface-connected
components `1.46`.

Generation cost rose from `0.843` to `0.962 ms/chunk` (`+14%`) for the extra meso terrain band,
province contact dithering, jigsaw assembly and deep facies grading. Against V4 on the same
traversal fixture:

| Metric | V4 | V5 | Change |
| --- | ---: | ---: | ---: |
| Average chunk generation | `3.9584 ms` | `1.0054 ms` | `-74.60%` |
| Traversal wall time | `495.566 ms` | `163.858 ms` | `-66.94%` |
| First simulation tick | `0.5190 ms` | `0.2030 ms` | `-60.89%` |
| p99 per-chunk latency | `8.16 ms` | `1.41 ms` | `-82.7%` |

## Verification

- Native release build: clean, no compiler warnings.
- CTest `koalasand_core_probe`: passed.
- Full repository suite: `TEST_SUITE_PASS scripts=31`.
- `tests/v5_worldgen.gd`: 237 checks passed.
- `tests/benchmark_v5_worldgen.gd`: passed.
- `scripts/capture_phase139b.ps1`: 30 player-surface captures, no layout failure.
- `scripts/capture_v5.ps1`: 13 worldgen contact sheets plus the climate-space diagnostic.
- `scripts/package_playtest.ps1`: export produced, `39,477,591` byte archive, build id
  `local-a16c9937cb90`.
- Owner package smoke: `new_character build save exit continue codex settings planning_pause
  factory creative diagnostics` all pass.
- No commit, push, tag or release performed.

## Accepted as designed

- **Not every region has a natural cave entrance.** Confirmed as intended: a player digs
  toward a system and it opens up. Surface-connected components average `1.46` per 10×12-chunk
  region, so natural entrances exist where the terrain supports them.

## Still open (owner decisions, not defects)

- **Subjective checks remain owner-only.** Audio balance, controller feel and whether the game
  is fun cannot be established by capture and assertion; `PLAYTEST_CHECKLIST.md` still applies,
  and the audio note in `KNOWN_ISSUES.md` asks for a first listen at low system volume.
- **Disclosed synthetic stress debt.** The 50k-active-Conveyor and one-million-active-Sand
  ceilings remain above frame budget. They are scalability probes, not gameplay fixtures, and
  predate this work.

Everything else previously listed as open is closed:

| Was open | Now |
| --- | --- |
| Research tree clipped its rightmost column | Fits to content on open, clamped so a drag cannot lose it |
| Deep coal locally dense | Rank requirement scales with fertility: fewer, larger deposits |
| Composition packing narrow | Verified: silica spans `0.053`–`0.870` across the rock table |
| Surface ruins not stamped | Stamped, buried, and reported by the candidate API |
| No natural cave entrance in some regions | Accepted as designed |
