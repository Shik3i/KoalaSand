# Alpha Release Audit

The last pass before a public alpha. Everything below was checked against a running build or a
built package, not read off the source. Where a claim is about the game's behaviour, the
experiment that established it is named.

Scope: what breaks, what lies to the player, and what a stranger sees that the owner never does.

---

## 1. The failure a public alpha cannot afford

**An exception inside the simulation took the whole process down, silently.**

C++ that throws through a GDExtension boundary calls `std::terminate`. There is no Godot error,
no line in `user://logs/godot.log`, no crash dialog. The window closes. That is the entire
player-visible symptom, and it is what the New Game crash looked like before it was found last
session -- six reproductions produced nothing but an absent process.

This matters more for strangers than it did for the owner. A player who hits it has nothing to
send, and a report that says "it closed" cannot be acted on. There are 89 `.at()` call sites
across the native sources, each keyed by ids written by a different subsystem; the New Game
crash was one stale id in one of them.

`step()` -- the one call that walks every registry, every tick -- now catches:

```cpp
int32_t NativeSandWorld::step() {
    if (faulted_) return 0;
    try {
        return step_simulation();
    } catch (const std::exception &error) {
        enter_fault("step", error.what());
    } catch (...) {
        enter_fault("step", "unknown exception");
    }
    return 0;
}
```

The fault is recorded with the stage and the tick, pushed to Godot's error stream so it lands in
the log file, and the world refuses to step again. It does not retry: whatever id was stale is
still stale, and a fault re-thrown every frame buries its own first and only useful message.

On the game side the clock stops, the HUD says the world is safe, and the diagnostics archive is
written without being asked -- the player who hits this is exactly the player who will not go
looking for the export button.

`tests/fault_guard.gd` injects a throw and asserts the process survives it. That test reaching
its own print statement *is* the assertion; without the guard the interpreter is gone. Observed:

```
ERROR: Simulation stopped in step: injected simulation fault (tick 0)
   GDScript backtrace (most recent call first):
       [0] _test_a_thrown_exception_does_not_take_the_process_down
PASS: 21 fault guard checks
```

The backtrace is a bonus: Godot names the GDScript caller, so a fault report now points at the
call that triggered it.

This does not remove the 89 `.at()` sites. It converts them from silent process death into a
frozen world with a written reason.

---

## 2. Text that promises machines the player cannot build

Last session found this in the second objective. It is not one mistake; it is a seam.

`COMPOSABLE_PROCESSING.md` retired the Radiant Crude Furnace, Vibrating Screen, Overbelt
Magnetic Separator and Wash Sluice to dev fixtures and replaced them with geometry built from
ordinary Components. `ComponentPresentation.DEV_TYPES` hides all four from the catalog. The text
layer was never brought along, and it was still sending players to all four.

| Surface | Said | Actually |
| --- | --- | --- |
| Objective 3 | "Research Dry Separation to unlock the Vibrating Screen" | Mesh Screen + Vibration Actuator |
| Objective 6 | "Route Water to a Wash Sluice" | Riffles, with Water beside them |
| `processing.dry_separation` | "Unlock Vibrating Screen" | Unlocks Mesh Screen, Vibration Actuator |
| `processing.ferrous_separation` | "Unlock Overbelt Magnetic Separator" | Unlocks Electromagnet, Metal Plate |
| `processing.wet_separation` | "Unlock Wash Sluice" | Unlocks Riffle |
| `foundation.basic_industry` | "...Research Bank, Furnace and Harvest" | No player-facing Furnace exists |

The research rows are the worse half: that is the text a player reads while deciding how to
spend Glass, Iron and Gold they had to earn.

**Both routes were run before the text was rewritten.** A Vibration Actuator placed beside a Mesh
Screen fractionates Raw Sand dropped onto the Mesh, and the `first_concentrate` milestone the UI
displays is the one the simulation sets. A Riffle with Water beside it processed a grain on
tick 1; the same Riffle, same grain, no Water, did nothing for 60 ticks. That second observation
is why the criterion now states the Water condition instead of leaving the player to find it.

Both plans already exist in the blueprint library -- `basic_screen` and `basic_wet_sluice` -- and
the objectives now name them.

`tests/build_flow.gd` asserts both mechanics fire, and then sweeps every objective criterion and
every research description and reward line for the display name of any `DEV_TYPE`. That sweep
found a sixth instance I had not, and pulling on it found something wording could not fix: see
below. The sweep now has to come back empty.

---

## 3. Research that charged for an effect the player could never receive

Found by the sweep above, then traced.

`is_physical_processor()` is true for exactly four structures -- the same four dev fixtures. So
`native_physical_processing.cpp` in its entirety -- heaters, screens, magnets, wet sluices -- is
reachable only through machines excluded from the catalog. Every research node whose effect
landed there was inert in a normal game, and `split_into_ledger()`, which is what the composable
geometry actually runs, read no research at all.

`processing.concentrate_recovery` is the most expensive node a player can see, at 6000 Glass, 400
Iron and 2 Gold, and two of the other dead nodes are prerequisites on the path to it.

Each node now lands on the route that does the work its own description names. Two of them did
not need a new design at all: `processing_result()` still spells out what those upgrades meant
when processing ran through machines, so the same distinction simply moved to the geometry.

| Node | Cost (Glass / Iron / Gold) | Was | Now |
| --- | ---: | --- | --- |
| `processing.precision_screening` | 4000 / 250 / 1 | dev sieve process id | A Mesh Screen sends the heavy mineral to the concentrate instead of letting it dilute the fines |
| `processing.concentrate_recovery` | 6000 / 400 / 2 | dead furnace branch | The thermal route recovers a concentrate's heavy fraction as Iron rather than residue |
| `logistics.high_throughput_handling` | 3500 / 180 / 0 | dev magnet cadence | A Processing Component buffers twice as much while its outputs are blocked |
| `furnace.throughput_1` | 2200 / 80 / 0 | dev heater divisor | Refractory geometry reacts a second cell in the same tick |
| `furnace.fuel_economy_1` | 1200 / 30 / 0 | dev furnace fuel | Thermal Insulators stop conducting heat across themselves |
| `thermal.cookware` | 900 / 60 / 0 | gated a hidden fixture | Unlocks the Iron Pot, now in the catalog |

Two of those deserve their reasoning stated.

**The Insulator.** Every structure from 37 to 44 bridges heat across itself between its two
opposite neighbours, which is how a hot enclosure bleeds into whatever it stands next to. The
coefficient is `conductivity / 16` with a floor of 1, and the Insulator's conductivity is 2 --
already at that floor. Halving it would have done nothing, which is exactly the kind of upgrade
that looks implemented and is not. The researched Insulator does not bridge at all; the cells
either side still exchange heat with everything else normally.

**The Iron Pot.** Retiring `thermal.cookware` was the other option. `PHYSICAL_COOKING.md`
documents the Pot as an implemented vessel with a thermal bridge, a cavity of ordinary world
cells and a rejection rule against removing it while full, and the research node for it already
existed. It was sitting in `DEV_TYPES` next to the Ceramic Test Vessel, which really is a
fixture and stays hidden. Putting the Pot in the catalog makes the node's existing promise true
rather than deleting a feature that works.

`tests/research_effects.gd` runs each scenario twice against the same seed and the same cells,
once without the research and once with, and asserts the numbers move. A test of only the
researched run would pass just as well if the effect were unconditional. It also pins two things
that keep the upgrades honest: Concentrate Recovery must leave unconcentrated Raw Sand exactly
alone, and both splitting upgrades must move mass between channels without creating or
destroying any.

Getting those measurements to mean anything took three corrections to the test itself, each of
which was the simulation being right and the scenario being wrong: a grain dropped on a Mesh
Screen falls straight through, because a deck is permeable by design; a grain with an empty cell
below and to one side runs diagonally away before the component looks at it; and a long run
measures the buffer depth both configurations share rather than the rate that separates them.

---

## 4. Components the game unlocks and never offers

Fixing the Iron Pot exposed the mechanism behind it. The Build Catalog is a **hand-written list**
in `factory_hud.gd`; the structure table it is meant to mirror lives in `native_sand_world.cpp`.
Nothing connected the two, so a Component could be defined, gated by its own research node, and
simply never listed. Three were:

- **Iron Pot** (35) -- `thermal.cookware`, 900 Glass and 60 Iron, unlocked nothing placeable.
- **Control Gate** (9) -- `automation.advanced_routing` costs 4200 Glass, 220 Iron and 1 Gold and
  its reward line reads "Unlock Control Gate". The Gate was not in the catalog either.
- **Conveyor Left** (1) -- and this one is not about research at all.

The last is the worst of the three. `_place_conveyor_drag()` reads the belt's direction straight
off the selected type:

```gdscript
"direction": -1 if build_structure_type == 1 else 1,
```

The catalog offered a single entry called "Conveyor", type 2. Type 1 was not selectable by any
means. **Every belt a player could build in this factory game ran to the right.** The entry is now
"Conveyor Right" with "Conveyor Left" beside it, and `tests/build_flow.gd` builds one of each and
watches a grain travel the correct way along both -- a second name for the same structure would
have passed a weaker check.

`tests/build_flow.gd` also now asserts that every structure `is_player_facing()` accepts appears
in the catalog, which is the rule the catalog was supposed to follow and the drift that let all
three through. The catalog is 72 cards, and the responsive layout test reports no overflow at any
of the twelve resolution and scale combinations it covers.

---

## 5. What looking at it found

Everything above came from reading code and running tests. None of it involved looking at the
game. Six screenshots of the real UI produced four more defects, which is the honest measure of
how much of the presentation layer had been reviewed: none of it.

**The Processing tab of the Build Catalog was empty.** `_canonical_category()` sorts a Component
into a tab by testing substrings in order, and it tested `"component"` before `"processing"`.
Every entry the catalog called a "Processing Component" -- Mesh Screen, Grate, Riffle, Vibration
Actuator, Electromagnet, Blower -- matched the first test and filed under Structures. Nothing
else in the catalog contained the word "processing", so the tab was empty in every world, in
every mode, from the first launch. A player following the objective to a Mesh Screen and
reaching for the obvious tab was told "No Components match this search."

**The research cards were drawing their text on top of itself.** Row positions were fixed offsets
multiplied by the zoom, while every font size had a floor of eight or nine pixels. Below about
0.7 zoom -- and the tree opens fitted, which on a tree this wide is the 0.34 minimum -- the rows
kept moving together while the glyphs stopped shrinking. It was survivable while every effect
was one short line. Section 3 above rewrote those effects, some of them now wrap, and the cards
turned to mush. Rows are now ranked rather than truncated from the bottom: name, then cost, then
what it unlocks, and the state label last, because the border colour already carries it.

**The first thing the game points at was clipped.** `GuidedHighlightLayer` sized its label box at
eight pixels per character and then drew the text at font size 14, so `draw_string()` clipped to
the box it had been handed. The tutorial arrow pointing at the Build button read "Open Catal".

**And it labelled itself with an identifier.** The same label came from prettifying the step id,
so the first thing a Character Mode player was shown said "Character Intro". Every onboarding
step now carries the words the arrow says, and `tests/build_flow.gd` asserts none of them is a
raw identifier again.

A fifth thing looked like a defect and was not, which is worth recording because the check is the
interesting part. The world preview on the New World screen showed a ruler-straight vertical
contact through every stratum -- exactly the artefact `WORLD_GENERATION_V5.md` says the province
dither exists to prevent. Probing the actual world at five depths found the transitions at
different x at every depth, so the world was fine. `v5_fill_column()` samples the province once,
at one y, because in the world it is called per chunk and the next chunk down probes again; the
preview solves a column once and draws two hundred cells of depth from it. The portrait was
wrong, not the geology. It now samples per pixel.

---

## 6. The performance and physics gate

Measured, not reasoned about. The question was where a frame goes on a world that has been
played in for a while, so the probe was an **idle** world: chunks resident, nothing active, no
matter moving.

| Resident chunks | Cost of one idle tick |
| ---: | ---: |
| 16 | 0.029 ms |
| 400 | 1.11 ms |
| 900 | 2.39 ms |
| 1600 | 4.16 ms |

Linear at about `2.6 us` per chunk per tick, for a world in which nothing is happening. It
matters because `evict_pristine_outside()` only evicts chunks that are **pristine**: anything the
player has dug, built in or spilled on stays resident for the rest of the session. Residency
therefore grows with everywhere they have been, and this cost grows with it -- slowly, over an
hour, which is exactly the shape of problem a benchmark never catches and a playthrough always
does.

Three things came out of it.

**The chunk order was rebuilt about ten times a tick.** `step()` and its subsystems walk every
resident chunk to build the active list, merge `next_active`, release liquid planes and run
thermal, and each walk allocated a vector and sorted the whole map to arrive at the same order.
The order only changes when a chunk is created, evicted or the world is cleared, so it is cached
and those three places invalidate it.

**One of those walks was quadratic.** Collecting fluid-active chunks asked `std::find` whether
each candidate was already in the movement list -- a linear scan of a list that grows with the
world. `active_chunks` had just been built from exactly the chunks whose activity bitmap is
valid, so `!chunk->active.valid()` is the same question, asked in constant time.

**And `get_statistics()` was being called every frame.** It walks every resident chunk itself and
then merges the fluid, generation, structure, pipe and wet-processing dictionaries, several of
which walk the map again. On a 1600-chunk world **one call measures 5.50 ms**. It was called by
the renderer every frame for two pixel counters, by the status line every frame for a panel that
is hidden, by the audio mixer for one movement count, by the alert manager for the tick, and --
worst -- by `_submit_brush_batch()` on **every brush stroke**, which is the exact path the
frame-rate collapse was originally reported on.

`get_tick()` costs `0.033 us` and `get_frame_counters()` costs `1.17 us`. Both exist now, the
callers that only wanted a number use them, and the status line assembles the full picture below
its own early return instead of above it.

What the benchmarks say, against the same suite run before the change:

| Dense Megafactory, 50k active belts | Before | After |
| --- | ---: | ---: |
| `avg_sim_ms` | 13.346 | **12.293** |
| `worst_sim_ms` | 27.669 | **24.937** |
| `avg_logistics_ms` | 9.737 | **8.930** |
| `hash` | `549667b4` | `549667b4` |

The identical hash is the point. The simulation is bit-for-bit what it was; it just costs less.
Brush drag worst-case frames improved too -- `13.09` to `11.32 ms` at 40 cells a frame, `11.11`
to `8.94` at 80 -- while the means did not move, which is what removing an occasional expensive
call rather than a per-frame one looks like.

**What is left, and why I stopped.** The idle tick is still linear at ~2.6 us per chunk: about
ten full walks of the chunk map remain, and removing them means iterating a maintained set of
chunks that have something to do rather than all of them. Four of those walks also clear
`next_active` as they go, and `next_active` is set by wake-ups that can reach a chunk outside any
list built earlier in the tick. Getting that wrong drops a wake-up, which is the failure that
produced the dead Conveyor two sessions ago and is invisible until a belt silently stops. That is
a change to make with a fresh head and its own test, not one to land the evening before a
release.

---

## 7. What a stranger sees that the owner does not

**The build shipped the default Godot icon** -- taskbar, window and executable. A public download
that looks like an untitled Godot project reads as unfinished before it opens. There is now an
original mark: a 16x16 pixel grid, scaled only by whole numbers, so the 16px taskbar entry is the
original pixels rather than a downsample. Loose grains over a settled pile, in the theme's own
amber on the world ink. It is deliberately plain and meant to be replaced.

**The window could be resized until the game was unusable.** No minimum was set. The top and
bottom bars alone occupy 160px of the 1280x720 layout -- the smallest the responsive tests cover
-- so a dragged-down window leaves no world and overlaps HUD nobody has measured. The floor is
now 1280x720.

**The executable declared no copyright.** Now set.

---

## 8. What was verified rather than assumed

- **The release package builds and runs.** `scripts/package_playtest.ps1` produced a 39.5 MB
  archive. Launched from the package directory with an isolated profile, the exported build
  reached the main menu, held it for 20 seconds and wrote `user://logs/godot.log`.
- **The GDExtension has no runtime dependency a player would lack.** `objdump -p` on the shipped
  DLL lists `KERNEL32.dll` and the `api-ms-win-crt-*` UCRT stubs and nothing else. No
  `libstdc++-6`, `libgcc_s_seh-1` or `libwinpthread-1` -- the classic MinGW failure where a build
  runs on the developer's machine and nowhere else does not apply here.
- **The correct export template was used.** The shipped exe is 109,071,360 bytes against the
  109,212,160-byte release template; the debug template is 103,122,944.
- **File logging works in the exported build**, so `push_error` from the fault guard reaches a
  file a player can attach.

---

## 9. Left for an owner decision

- **Release identity.** `config/version` still reads `0.1.0-playtest.5`, the package is named
  after it, and `README-PLAYTEST.txt` opens with "Owner first-play build". It also asks for bug
  reports without naming anywhere to send them -- there is no channel yet.
- **`LICENSE` grants a recipient nothing.** It reserves all rights and permits no use, which is
  right for the source but is also what ships beside the binary as `LICENSE-KOALASAND.txt`. A
  public build normally carries explicit permission to download and play it.
- **Godot's own third-party notices.** `THIRD_PARTY_NOTICES.txt` covers Godot and godot-cpp by
  MIT, but Godot's `COPYRIGHT.txt`, which lists the engine's own bundled dependencies, is not in
  the package.
- **`PLAYTEST_CHECKLIST.md` ships inside the package.** An internal checklist in a public
  download.
- **The character avatar is a placeholder** -- a grey circle, a green rectangle and two stick
  legs -- and it is what a Character Mode player looks at for the whole session.
- **Component icons repeat.** Storage Bin, Reservoir Wall, Structural Wall, Iron Pot and Thermal
  Insulator all draw the same rectangle glyph, so the catalog is read by name rather than by
  shape.
- **Research node names truncate** at the zoom the tree opens at: "Ferrous Separati",
  "High-Throughpu", "Concentrate Rec". The footer shows the full name once a node is selected.
- The three P1s carried from earlier passes: Factory Mode offering brushes its capability table
  forbids, four Experiments that can never complete, and the `benchmark_phase95` gate sitting on
  its own boundary.

---

## 10. Gates

| Gate | Result |
| --- | --- |
| `scripts/test.ps1` | `TEST_SUITE_PASS scripts=37` |
| `scripts/benchmark.ps1` | `BENCHMARK_SUITE_PASS scripts=30` |
| Megafactory state hash | `549667b4`, unchanged across the optimisation |
| `tests/build_flow.gd` | 184 checks |
| `tests/fault_guard.gd` | 21 checks |
| `tests/research_effects.gd` | 21 checks |
| `scripts/package_playtest.ps1` | archive produced, exported build launches |

The complaint that started this run of work -- painting dropped the game to zero frames -- was
re-measured on this build and stays fixed. The cost is flat in how fast the hand moves, which is
the property that was broken:

| Drag speed | Frame mean | p95 | Worst | Rate |
| ---: | ---: | ---: | ---: | ---: |
| 4 cells/frame | 6.91 ms | 8.17 ms | 8.44 ms | 145 fps |
| 16 cells/frame | 6.92 ms | 7.80 ms | 7.91 ms | 145 fps |
| 40 cells/frame | 6.94 ms | 8.43 ms | 13.00 ms | 144 fps |
| 80 cells/frame | 6.88 ms | 10.36 ms | 10.82 ms | 145 fps |
| 160 cells/frame | 6.90 ms | 8.97 ms | 10.68 ms | 145 fps |

The benchmark suite is not a dependable gate once it has been running for a few minutes. Two
consecutive full runs failed Phase 9, Phase 9.5 and Phase 11 -- all timing gates on large
workloads, all late in the run. Phase 11 measured `5.09` and `3.53 ms` against a `< 3.0` gate on
identical work; run on its own straight afterwards it measured `2.16`, `2.15` and `2.30 ms`,
three times, and three earlier full-suite runs the same day had passed it at `2.06`-`2.13 ms`.
Nothing in the simulation changed between them. The suite measures a hotter machine as it goes
and several gates sit close enough to flip; see KNOWN_ISSUES.md.

Manual playtest coverage remains required and cannot be replaced by any of this: controls,
readability, audio balance and whether the first hour is worth anyone's time are not measurable
from here.
