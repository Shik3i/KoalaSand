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
found a sixth instance I had not: see below.

---

## 3. Research that charges for an effect the player cannot receive

Found by the sweep above, then traced. This one is **not fixed**, because both repairs are
design decisions.

`is_physical_processor()` is true for exactly four structures -- the same four dev fixtures. So
`native_physical_processing.cpp` in its entirety -- heaters, screens, magnets, wet sluices -- is
reachable only through machines excluded from the catalog. Every research node whose effect
lands there is inert in a normal game:

| Node | Cost (Glass / Iron / Gold) | Effect reaches |
| --- | ---: | --- |
| `furnace.fuel_economy_1` | 1200 / 30 / 0 | `furnace_fuel_units()`, dev furnace only |
| `furnace.throughput_1` | 2200 / 80 / 0 | heater divisor + `STRUCTURE_FURNACE` cadence |
| `logistics.high_throughput_handling` | 3500 / 180 / 0 | `STRUCTURE_MAGNETIC_SEPARATOR` cadence |
| `processing.precision_screening` | 4000 / 250 / 1 | `STRUCTURE_SIEVE` process id |
| `processing.concentrate_recovery` | 6000 / 400 / 2 | furnace branch of `process_machines()` |
| `thermal.cookware` | 900 / 60 / 0 | gates only the Iron Pot, itself a `DEV_TYPE` |

`split_into_ledger()` -- the function the composable geometry actually runs -- reads no research
at all. `is_processing_machine()` returns true only for the Research Bank, so the furnace branch
`processing.concentrate_recovery` upgrades is dead code.

`processing.concentrate_recovery` is the most expensive node a player can see, and two of the
others are prerequisites on the path to it.

The two repairs are different games: retire the nodes, or re-point their effects at
`split_into_ledger()` and `process_component_processing()`. That is an owner call. The wording of
every node was corrected in this pass; the economics were not. The single remaining text surface
that still names a dev fixture (`thermal.cookware` -> "Unlock Iron Pot") is pinned in
`tests/build_flow.gd` as a known exception, so it cannot be forgotten and no second one can
appear beside it unnoticed.

---

## 4. What a stranger sees that the owner does not

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

## 5. What was verified rather than assumed

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

## 6. Left for an owner decision

- **The research economics above.**
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
- The three P1s carried from earlier passes: Factory Mode offering brushes its capability table
  forbids, four Experiments that can never complete, and the `benchmark_phase95` gate sitting on
  its own boundary.

---

## 7. Gates

| Gate | Result |
| --- | --- |
| `scripts/test.ps1` | `TEST_SUITE_PASS scripts=36` |
| `scripts/benchmark.ps1` | `BENCHMARK_SUITE_PASS scripts=30` |
| `tests/build_flow.gd` | 100 checks |
| `tests/fault_guard.gd` | 21 checks |
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

The `benchmark_phase95` gate that fails roughly one run in three passed this time. That does not
make it a sound gate; see KNOWN_ISSUES.md.

Manual playtest coverage remains required and cannot be replaced by any of this: controls,
readability, audio balance and whether the first hour is worth anyone's time are not measurable
from here.
