# Known Issues

Priorities describe engineering risk for continued owner playtesting, not a release schedule.

## P0

None known after the Phase 13.9 verification gate.

## P1

- **Release identity is still the owner playtest one:** `config/version` reads
  `0.1.0-playtest.5`, the package is named `KoalaSand-0.1.0-playtest.5-windows-x64`, and
  `README-PLAYTEST.txt` opens with "Owner first-play build" and asks for bug reports without
  naming anywhere to send them. All three are owner calls: the version string cascades into the
  package name and `BUILD_MANIFEST.json`, and the report channel does not exist yet.
- **`LICENSE` grants a recipient nothing.** It reserves all rights and permits no use, which is
  the correct posture for the source but is also what ships beside the binary as
  `LICENSE-KOALASAND.txt`. A public build normally carries an explicit permission to download
  and play it. Legal wording is an owner decision.
- **Dense synthetic Megafactory:** intentionally pathological density now measures `59.1 FPS`, `18.750 ms` p95 and `19.737 ms` p99 as the median of four consecutive runs, up from `43.7 FPS` / `25.000 ms` / `27.905 ms`. Single runs of this fixture have measured as high as `79.4 FPS` on an idle host and should not be quoted. It is still reported separately from the realistic maximum-factory gate; see [PERFORMANCE.md](PERFORMANCE.md).
- **Factory Mode offers tools its capability table forbids:** `GameModeCapabilities` declares
  `creative_paint`, `creative_erase` and `world_edit` Creative-only, Factory Mode runs
  `ProgressionMode.NORMAL`, and yet the Factory quickbar offers raw material brushes and nothing
  enforces the capability in the command path. Either the table or the catalog is wrong; see
  [FIRST_RUN_PASS.md](FIRST_RUN_PASS.md). Left for an owner decision because enforcing the table
  as written may remove the only way to excavate in a mode with no character.
- **Four of the eight Experiments can never be completed:** `wet_then_dry_events`,
  `vessel_material_comparisons`, `oxygen_starved_events` and `modified_furnace_temperature_gain`
  are read by `ExperimentTracker` and published by nothing. Each needs a decision about what the
  simulation should measure; see [FIRST_RUN_PASS.md](FIRST_RUN_PASS.md). The gap is pinned by
  `tests/build_flow.gd` so it cannot grow.
- **The benchmark suite fails by position, not by code.** Running the whole suite twice in a row
  produced `FAIL` for Phase 9 (1M active thermal), Phase 9.5 (1M Steam) and Phase 11 (character
  FOV) -- all timing gates on large workloads, all late in the run. Phase 11 measured
  `open_avg 5.09` and `3.53 ms` against a `< 3.0` gate and a p99 of `16.99` and `30.97 ms`
  against `< 5.0`, on identical work (`sampled=16241` in every run). Run on its own immediately
  afterwards, the same script measured `2.16`, `2.15` and `2.30 ms` average and `2.64`, `2.58`
  and `2.85 ms` p99, three times in a row, comfortably inside both gates -- and three earlier
  full-suite runs the same day had passed it at `2.06`-`2.13 ms`. Nothing in the simulation
  changed between the passing and failing runs; only UI drawing code did. So the suite's later
  scripts are measuring a hotter or busier machine than its earlier ones, and several gates sit
  close enough to flip. Deliberately not relaxed: the fix is either a cooldown between scripts, a
  gate stated as a distribution, or accepting that the suite is advisory after the first few
  minutes. All three are owner calls.
- **The 1M-Steam benchmark gate sits on its own boundary:** `benchmark_phase95.gd` asserts the
  eight-worker average is `<= 8.0 ms`, and three consecutive runs on the Phase 13.9 host measured
  `7.79`, `7.92` and `8.00 ms`. It therefore fails roughly one run in three, which makes
  `scripts/benchmark.ps1` unusable as a gate even though nothing is wrong. The measurement is
  memory-bandwidth bound and moves with host state; earlier runs on the same build measured
  `7.52`-`7.68 ms`. Deliberately not relaxed: either the fluid pass earns real headroom or the
  gate is restated as a distribution rather than a single average, and both are owner calls.
- **An idle tick costs about `2.6 us` per resident chunk**, and `evict_pristine_outside()` only
  evicts chunks the player never touched, so residency grows with everywhere they have been. A
  settled 1600-chunk world spends `4.16 ms` a tick on bookkeeping for a world in which nothing is
  happening. About ten full walks of the chunk map remain in `step()`; removing them means
  iterating a maintained set of chunks that have work rather than all of them. Four of those
  walks also clear `next_active` as they go, and `next_active` is set by wake-ups that can reach
  a chunk outside any list built earlier in the tick -- getting that wrong drops a wake-up, which
  is the failure that produced the dead Conveyor in the first-run pass and is invisible until a
  belt silently stops. Deliberately deferred: it needs its own test before it needs a patch.
- **The presentation layer has had no review.** Six screenshots of the real UI produced four
  defects, all of them listed below as fixed. That hit rate is the finding: the simulation is
  covered by 37 test scripts and 30 benchmarks, and what a player actually looks at is covered by
  nobody. Known and unfixed: the character avatar is a placeholder, several Components share one
  rectangle icon, and research node names truncate at the zoom the tree opens at.
- **Manual playtest coverage:** automated captures and state assertions cannot establish subjective controls, readability, audio balance or fun. The owner checklist remains required.

## Fixed in the alpha release audit

- **`get_statistics()` was on three per-frame paths and on every brush stroke.** It walks every
  resident chunk and then merges five dictionaries that walk it again; on a 1600-chunk world one
  call measures `5.50 ms`. The renderer called it every frame for two pixel counters, the status
  line called it every frame for a panel that is hidden, the audio mixer for one movement count,
  the alert manager for the tick, and `_submit_brush_batch()` on every brush stroke -- the exact
  path the frame-rate collapse was reported on. `get_tick()` (`0.033 us`) and
  `get_frame_counters()` (`1.17 us`) now serve the callers that only wanted a number.
- **The chunk order was rebuilt about ten times a tick, and one of those walks was quadratic.**
  Every walk allocated a vector and sorted the whole chunk map to reach the same order, and
  collecting fluid-active chunks asked `std::find` whether each candidate was already in the
  movement list. The order is cached and invalidated at the three places that create, evict or
  clear chunks; the membership question is answered by the chunk's own activity bitmap. The
  dense Megafactory benchmark went from `13.346` to `12.293 ms` average and `27.669` to
  `24.937 ms` worst, with an unchanged state hash of `549667b4`.

- **The Processing tab of the Build Catalog was empty in every world, in every mode.**
  `_canonical_category()` tested `"component"` before `"processing"`, so every "Processing
  Component" filed under Structures and nothing was left carrying the word. A player following
  the objective to a Mesh Screen and reaching for the obvious tab read "No Components match this
  search". `tests/build_flow.gd` now asserts every tab is non-empty and that the Processing tab
  holds the Components the objectives name.
- **Research cards drew their text on top of itself.** Row positions were fixed offsets scaled by
  the zoom while every font size had a floor of eight or nine pixels, so below about 0.7 zoom --
  and the tree opens fitted, at the 0.34 minimum -- the rows collided. Correcting the research
  effect wording made several of them wrap, which turned a latent defect into an unreadable
  panel. Rows are now ranked: name, cost, effect, and the state label last, since the border
  colour already carries it.
- **The tutorial arrow was clipped and labelled with an identifier.** `GuidedHighlightLayer`
  sized its box at eight pixels per character and drew at font size 14, so the first thing the
  game points at read "Open Catal"; and the label came from prettifying the step id, so Character
  Mode opened by pointing at "Character Intro". The box now measures the string, and every
  onboarding step carries the words the arrow says.
- **The world preview drew geology the world does not have.** `v5_fill_column()` probes the
  geological province once, at one y, because in the world it is called per chunk. The New World
  preview solves a column once and draws two hundred cells of depth from it, so every province
  contact became a ruler-straight vertical wall -- the exact artefact `WORLD_GENERATION_V5.md`
  says the dither exists to prevent, on the first image a player sees. Probing the real world at
  five depths confirmed the geology was fine; only its portrait was wrong. The preview now
  samples the province per pixel.

- **Every belt a player could build ran to the right.** `_place_conveyor_drag()` reads the
  direction off the selected type -- `-1 if build_structure_type == 1 else 1` -- and the Build
  Catalog offered a single entry called "Conveyor", type 2. Conveyor Left was not selectable by
  any means: not by rotating, not by dragging leftwards, not from the catalog. It is listed now,
  and `tests/build_flow.gd` builds one of each and watches a grain travel the correct way along
  both.
- **The Build Catalog is a hand-written list that had drifted from the structure table.** Nothing
  connected `factory_hud.gd` to `get_structure_definitions()`, so a Component could be defined,
  gated by its own research node, and never offered. Three were: the Iron Pot, the Control Gate
  -- whose research node costs 4200 Glass, 220 Iron and 1 Gold and promises to unlock it -- and
  Conveyor Left. `tests/build_flow.gd` now asserts that every structure `is_player_facing()`
  accepts appears in the catalog.

- **Six research nodes charged Glass, Iron and Gold for an effect a player could never
  receive.** `is_physical_processor()` is true only for the Radiant Crude Furnace, Vibrating
  Screen, Overbelt Magnetic Separator and Wash Sluice, and `COMPOSABLE_PROCESSING.md` retired all
  four to dev fixtures excluded from the Build Catalog. Every upgrade in the processing branch
  still pointed at them, including `processing.concentrate_recovery` at 6000 Glass, 400 Iron and
  2 Gold -- the most expensive node a player can see -- and two of the dead nodes were
  prerequisites on the path to it. `split_into_ledger()`, which is what the composable geometry
  runs, read no research at all. Each node now lands on the route that does the work its own
  description names, using the definitions the game already had:

  | Node | Now does |
  | --- | --- |
  | `processing.precision_screening` | A Mesh Screen sends the heavy mineral to the concentrate instead of letting it dilute the fines -- the same distinction `PROCESS_SIEVE_PRECISION` always drew against `PROCESS_SIEVE` |
  | `processing.concentrate_recovery` | The thermal route recovers a concentrate's heavy fraction as Iron rather than residue, and only for material that was actually concentrated first -- the distinction `PROCESS_FURNACE_RECOVERY` drew against `PROCESS_FURNACE_RAW` |
  | `logistics.high_throughput_handling` | A Processing Component buffers twice as much while its outputs are blocked |
  | `furnace.throughput_1` | Refractory geometry reacts a second cell in the same tick |
  | `furnace.fuel_economy_1` | Thermal Insulators stop conducting heat across themselves. Their conductivity of 2 was already at the floor of the structure bridge, so stopping the bridge is the only reduction left |
  | `thermal.cookware` | Unlocks the Iron Pot, which is now in the catalog. It is an implemented, documented vessel (`PHYSICAL_COOKING.md`) that was sitting in `DEV_TYPES`, which is what made the node unlock nothing placeable |

  `tests/research_effects.gd` runs each scenario twice against the same seed and the same cells,
  once without the research and once with, and asserts the numbers move -- a test of only the
  researched run would pass just as well if the effect were unconditional. It also asserts that
  Concentrate Recovery leaves unconcentrated Raw Sand alone, and that the two splitting upgrades
  move mass between channels without creating or destroying any.

- **An exception inside the simulation took the whole process down silently.** C++ that throws
  through a GDExtension boundary calls `std::terminate`: no engine error, no line in
  `user://logs/godot.log`, no crash dialog, and nothing for a player to report -- the window is
  simply gone, which is exactly what the New Game crash looked like. `step()` now catches,
  records the reason and the tick, pushes it to Godot's error stream so it reaches the log, and
  refuses to run again instead of retrying a fault that would bury its own first message. The
  game freezes the clock, says the world is safe, and writes the diagnostics archive without
  waiting to be asked. `tests/fault_guard.gd` injects a throw and asserts the process survives
  it; the eighty-nine remaining `.at()` call sites are no longer a silent-death risk.
- **The window could be resized until the game was unusable.** No minimum was set, and the top
  and bottom bars alone occupy 160px of the 1280x720 layout that the responsive tests cover.
  The window will now not go below that.
- **The build shipped the default Godot icon**, in the taskbar, the window and the executable.
- **Three research nodes and two objectives promised machines that cannot be built.** Same cause
  as the second objective, in the surface where a player decides how to spend a scarce resource:
  "Unlock Vibrating Screen", "Unlock Overbelt Magnetic Separator", "Unlock Wash Sluice" and a
  Foundation summary naming a Furnace, plus objectives three and six sending the player to the
  Vibrating Screen and the Wash Sluice. Each now names what the research actually unlocks and
  the plan that builds it, and both routes were run in the simulation first: a Vibration
  Actuator beside a Mesh Screen fractionates Raw Sand, and a Riffle with Water beside it
  processes grains while the same Riffle without Water does nothing.

## Fixed in the first run pass

- **A Component chosen from the catalog could never be placed:** the catalog is a modal and did
  not close on selection, and an open modal makes `_pointer_over_ui()` true for the whole
  screen. Selecting a Conveyor and clicking in the world did nothing, every time, with no
  indication why.
- **Every build refusal was silent:** the validator computes exact reasons and the placement
  paths discarded them. Aiming a Conveyor at the ground -- the way belts work in every other
  factory game, and wrong here because a Conveyor occupies the cell itself -- produced no sound,
  no message and no reason to try one cell higher.
- **Nothing the game says was on screen:** the objective, the progress criteria, the mode's
  opening hint and the Codex link all lived in a popup that started closed behind an
  unmarked chip in the top bar.
- **The objective never advanced:** the milestone keys the UI looked up had drifted from the
  ones the simulation publishes, and the first key was among them, so the objective read "Move
  physical material" for the entire game regardless of progress. Its criteria were also the same
  three generic words on every step.
- **A Conveyor could not be started by dropping matter onto it:** the condition that enables
  movement notifications asked whether a belt was already awake, and belts are woken only by
  those notifications. Painting matter directly into the cell above a belt worked because
  `set_cell()` wakes belts itself; letting it fall -- what the game's own first instruction says
  to do -- left it on a dead belt forever.
- **Reaching a milestone was never acknowledged:** `_last_milestones` was recorded every frame
  and read by nothing, so completing the objective the game asked for produced no message and no
  sound.
- **No discoverable way to dig:** the Excavate brush was bound only to the `E` key on a toolbar
  this UI does not show, and appeared in neither the catalog nor the action row. Factory Mode has
  no character to dig with, so terrain could not be moved at all by any means a player could
  find. The one terrain button that was present was labelled "Dig" and selected the Harvest
  brush, which only affects Coal.
- **The first quickbar page was mostly locked:** six of ten entries were Pipe components a new
  Factory player cannot build.
- **Subsurface Channels claimed to be unlocked:** their catalog entry never set a locked flag
  even though placement is gated by `logistics.subsurface_*` research.

## Fixed in the input and simulation performance pass

- **The game closed itself when a second world was started:** `configure_world()` -- the call
  behind every "New Game" -- cleared `machine_entities_` but left `physical_processors_`, the
  active magnet/screen/heater/sluice sets, the thermal switch and heat exchanger cells and the
  whole automation, power, pipe, organic and phase13 registries holding the previous world's
  ids. The first `step()` of the new world walked a heater id with no machine behind it and
  `machine_entities_.at(id)` threw `std::out_of_range`. An uncaught exception in a GDExtension
  takes the process down with no Godot error, no log line and no crash dialog, so it looked
  like the window had simply disappeared. `reset()` and `configure_world()` now share one
  `clear_world_state()`.
- **Painting collapsed the frame rate to zero:** the editor submitted a separate command --
  each with its own `CommandBatch`, deep-copied payload, full statistics read and serialised
  log entry -- for every cell of every brush stamp. A radius-3 brush dragged 160 cells in a
  frame came to roughly 4,700 round trips and `4,763 ms`. A stroke is now one command.
- **The command log grew without limit:** `WorldCommandBus` kept every command and batch it had
  ever applied. Nothing but the determinism tests reads them, and a minute of painting left
  tens of thousands of serialised commands in memory.
- **Production statistics ran off the right edge of the screen:** the panel's `Label` had no
  wrapping and no vertical fill, so long rows drew straight through the panel and the block sat
  vertically centred instead of starting at the top.
- **A failing test or benchmark aborted its own harness:** Windows PowerShell 5.1 turns each
  stderr line from a native executable into a terminating error under
  `$ErrorActionPreference = 'Stop'`, so `scripts/godot.ps1` reported itself as the fault, the
  suite stopped at the first failure and no summary was printed.

## Fixed in the V5 release-polish pass

- **Character spawned buried:** `get_character_spawn()` returned the V4 surface height for a
  V5 world, so Character mode began inside rock with only a small discovered pocket visible.
- **Prototype showcase light in every view:** an unreferenced orange `PointLight2D` pinned to
  one world coordinate washed a large warm glow across the terrain in all player-facing views.
- **Developer beacon in player views:** the fixed-cell beacon marker now draws only alongside
  the other chunk-debug overlays.
- **Streaming deadlocked after loading a save:** `reset()` stopped the generation workers and
  only restarted the render pool, so the first chunk streamed after a load blocked
  `flush_generation()` indefinitely. Reproduced on V4, so it predates the V5 work.
- **Reported and conserved composition disagreed:** `composition_for()` and
  `get_geology_profile()` decoded different, overlapping bit windows of the same 16-bit
  provenance id. V5 worlds now share one decoder.
- **Unreadable check states:** `CheckBox`/`CheckButton` had no authored theme, so an unchecked
  box rendered with no box at all.
- **Entrance shafts capped at chunk boundaries:** a surface entrance leaves its descriptor's
  reach box, so a chunk containing the surface never scanned the deeper descriptor rows whose
  entrances reach up into it. Neighbouring chunks disagreed about the same cell. Covered by a
  cross-chunk agreement check in `tests/v5_worldgen.gd`.
- **Release package could not be built:** `scripts/package_playtest.ps1` used three PowerShell
  7-only APIs while every other repository script runs under Windows PowerShell 5.1, and no
  document stated a PowerShell 7 requirement. Rewritten against APIs both versions provide.
- **Floating food specimens:** vegetation placed a specimen on the first empty cell above
  anything, including tree canopies, which read as dots hanging in the sky.

## P2

- **Windows root certificate diagnostic:** some restricted Windows sessions print exactly `ERROR: Failed to read the root certificate store.` from `platform/windows/os_windows.cpp`. Local simulation, import, tests and packaging do not use TLS; treat it as nonfatal only when the process exits `0` and no subsequent project error exists.
- **Real-device audio remains owner-verified:** automation deliberately uses Godot's `Dummy` driver after the pre-fix procedural mix produced harsh interference. The new 16-bit/seamless/headroom-limited implementation passes structural tests, but subjective speaker/headphone balance must be verified manually at low system volume first.
- **Long soak coverage:** the Phase 13.7 accelerated soak was stopped after the user-approved 60-minute wall-time boundary with stable live memory. Its four-hour terminal checkpoint was not reached in this gate.
- **Synthetic stress scope:** million-active-cell planes, 50k active Pipes and dense synthetic factories are scalability probes rather than supported gameplay promises. Both million-cell planes are now inside the 60 Hz gate (`7.86 ms` Sand, `9.20 ms` Water at eight workers); the scope note stands because the fixtures still are not gameplay.
- **Platform scope:** Web export and multiplayer are architecture documents only. No runtime networking or browser build exists.
- **Advanced content:** chemistry/clay production, farming/survival/combat and Nuclear are post-MVP.

## Operational constraints

- Use `scripts/godot.ps1`; direct Godot execution bypasses the repository-local profile isolation that prevents the known Windows access-violation environment failure.
- Never run automated tests, benchmarks or captures audibly. Use `-MuteAudio`; benchmark/capture flags enforce `Dummy` audio automatically.
- Generated packages, captures, build trees, dependencies, runtime profiles and the safety snapshot are intentionally ignored. Reproduce them with the documented scripts.
