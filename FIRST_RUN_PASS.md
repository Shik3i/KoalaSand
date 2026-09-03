# First Run Pass

The owner reported two things: that a Conveyor still could not be placed, and that nothing about
the game is understandable the first time. Both turned out to be the same disease. The game
knows exactly what it is doing and says none of it out loud.

---

## 1. A chosen Component could never be placed

The catalog is a modal. `_pointer_over_ui()` returns true for the **whole screen** while any
modal is open, and picking a Component out of the catalog did not close it.

So the sequence a player naturally follows —

1. press `B`, the Build Catalog opens
2. click the Conveyor card, it highlights as selected
3. click in the world

— ends with the click being swallowed. The Conveyor is selected. The cursor shows a placement
preview. Nothing can ever be built, and nothing says why. There is no wrong move to correct:
the path the UI invites you down is a dead end.

Choosing a Component now closes the catalog, which is what "I want to place this" means.

## 2. Every refusal was silent

The build validator produces exact reasons — `OUT_OF_RANGE`, `UNKNOWN_AREA`,
`BLOCKED_INTERACTION`, `COLLIDES_WITH_TERRAIN`, `COLLIDES_WITH_MATERIAL`, `TECH_LOCKED` — and
`_place_conveyor_drag()` threw them away:

```gdscript
if not _character.can_build_cells(cells):
    _structure_dragging = false
    return                      # no sound, no message, no mark on the cell
```

The same silent return sat in the single-Component path, the Pipe drag and the Subsurface
Channel drag. And a command the simulation itself rejected was never reported either.

This matters most for the rule nobody expects. In every other factory game a belt is placed
**on** the ground. Here a Conveyor occupies the cell itself, so it needs empty space and has to
go *above* the ground. A player aims at the ground, clicks, and gets nothing at all — no
feedback, no rule learned, no reason to try one cell higher.

Refusals now say what is in the way, in words that name the next action:

| Validator | What the player reads |
| --- | --- |
| `OUT_OF_RANGE` | Out of build range · move closer |
| `UNKNOWN_AREA` | You have not explored that area yet |
| `BLOCKED_INTERACTION` | Something solid is in the way |
| `COLLIDES_WITH_TERRAIN` | That space is solid · dig it out first |
| `COLLIDES_WITH_MATERIAL` | That space is full of material · clear it first |
| `TECH_LOCKED` | Locked · research it first |

Factory and Creative Mode build without a character, so there the reason is read from the world
directly: an occupied cell, an existing structure, or terrain that has not finished generating.

## 3. Nothing the game says was on screen

This is the whole of what a first-time player could read after starting a Factory game:

```
FACTORY        Objective · Move physical material ▸
Glass 0 · Iron 0 · Gold 0     Research   Plan   More ▾   View ▾   ?
Tools ▾     ◀ ▶ 1/10     Build [B]   Plans
```

The objective, what counts as progress, the mode's opening hint and the link into the Codex all
exist — `Factory Mode: plan and build anywhere. Research remains active. B opens Components.` is
computed on every frame — and all of it lives inside a popup that started **closed**. The only
way to reach it was to guess that the Objective chip in the top bar is a button.

The popup now starts open while hints are enabled. `Dismiss hints` and the chip both still close
it, and the choice is remembered.

## 4. A toolbar mostly made of things the game refuses

The quickbar was filled by slicing the catalog in its declared order, which gave a new Factory
player **six locked Pipe entries out of ten** on the first page. A toolbar that is mostly things
the game will not let you place teaches the wrong thing about the game.

Tools the player can use now come first; order is otherwise preserved. The first page is now ten
usable entries, with the Conveyor in slot 1.

While checking that, one entry turned out to be lying: Subsurface Channels are gated by
`logistics.subsurface_1/2/3` research, but nothing ever set their `locked` flag. They showed as
available, sat on the first page after the reordering, and would have refused in silence. The
unlock rule already existed in native and only needed exposing.

## 5. The objective never moved, for the whole game

The objective in the top bar is meant to walk the player through the arc: move material,
deposit into a Research Bank, separate by physical properties, recover Iron, and so on. It is
driven by a list of milestone keys held in `debug_world.gd` alongside the list native actually
publishes from `get_milestone_state()`.

Seven of the ten keys had drifted apart:

| The UI looked for | The simulation publishes |
| --- | --- |
| `first_material_moved` | `first_material_flow` |
| `first_separation` | `first_research_deposit` |
| — | `first_concentrate` |
| `first_automation` | `automation` |
| `first_water` | `water_processing` |
| `first_steam` | `steam` |
| `first_power` | `electricity` |
| `stable_power` | — |

The loop stops at the first unmet milestone, and the very first key was wrong, so the lookup
always missed, the loop always broke on step one, and the objective read **Move physical
material** forever no matter how far the player got. Nothing the player did was ever
acknowledged.

Keys, titles and criteria now travel together in one table, and `tests/build_flow.gd` asserts
every key in it is one the simulation publishes and that the count matches exactly. Reintroducing
a single drifted key fails that check.

The criteria were also `Build · Observe · Improve` on every step, which says nothing. They now
describe what the simulation actually measures — and the first one is the rule that was costing
the owner the most:

> **Move physical material**
> Place a Conveyor in open air above the ground · Drop matter onto it · Watch it travel

## 6. Reaching a milestone was never acknowledged

`_last_milestones` was recorded on every frame and read by nothing. So the arc the objective
walks the player through was also completed in silence: you do the thing the game asked for, the
objective quietly changes to the next one, and nothing tells you that you succeeded.

Reaching a milestone now says so. The first observation of a session is skipped, so loading a
save does not replay the whole run as a burst of notifications.

## 7. Three help links pointed at nothing

The objective table in §5 carries a Codex id for its "Open objective help" button, and three of
the seven ids I first wrote did not exist -- `concept:separation`, `concept:wet_processing` and
`concept:thermal`, against the real `concept:screening`, `concept:wet_separation` and
`concept:heat`. That is the same defect as §5, introduced by the fix for §5, which is a fair
illustration of why the boundary needs a test rather than care.

`tests/build_flow.gd` now gathers every Codex id referenced anywhere under `debug/`, `rendering/`
and `core/` **from the source files themselves**, and asserts each one resolves to an entry. It
cannot pass by agreeing with a list this test also wrote.

## 8. Half the Experiments can never be completed

Auditing the name boundary more widely — every dictionary key GDScript reads against every key
native publishes — turned up the same defect in the Experiments feature. Four of the eight wait
on a counter that **nothing anywhere produces**:

| Experiment | Waits on | Published by |
| --- | --- | --- |
| Heavy Things Settle | `heavy_captured` | `get_wet_processing_statistics` |
| Air Changes Fire | `charcoal_produced` | `get_organic_statistics` |
| Build a Vessel | `steam_generated` | `get_gas_statistics` |
| Contain the Gas | `steam_mass` | `get_pipe_statistics` |
| Wet Sand, Dry Sand | `wet_then_dry_events` | **nothing** |
| Material Matters | `vessel_material_comparisons` | **nothing** |
| Starve the Flame | `oxygen_starved_events` | **nothing** |
| Iterate the Furnace | `modified_furnace_temperature_gain` | **nothing** |

A player can chase those four forever. I have not invented the counters, because three of them
need the simulation to measure something it does not currently measure and the definition is a
design call, not a wiring fix:

- *Wet Sand, Dry Sand* needs "a grain that was wet and then dried" to be a tracked event.
- *Material Matters* needs a comparison between two vessel wall materials to be recorded.
- *Iterate the Furnace* needs a baseline furnace temperature to improve on.

*Starve the Flame* is the closest to mechanical — the combustion branch already gates on
`oxygen >= oxygen_mass`, and the pyrolysis branch already gates on `oxygen < LOW_OXIDIZER` — but
those are two different lessons ("the fire stalls" versus "you made Charcoal"), and the second
duplicates *Air Changes Fire*. Guessing would teach the player the wrong physics.

`tests/build_flow.gd` now pins both halves: the four wired counters must stay published, and the
four missing ones must stay missing. Implementing one makes the test say so.

## 9. A Conveyor could not be started by dropping matter onto it

Following the game's own first instruction did not work.

`should_collect_matter_changes()` decides whether a granular or fluid move reports the cells it
touched to the serial barrier. Every term in it asks whether a subsystem that could care
*exists* — except the belt term, which asked whether any belt was already **awake**:

```cpp
return ... || !active_belts_.empty() || ...;
```

That is circular. A sleeping belt is woken by `activate_belts_near()`; `activate_belts_near()`
is only reached through these notifications; and the notifications were switched off precisely
because no belt was awake. A Conveyor could therefore never be started by matter falling onto
it.

It looked like it worked, which is why it survived. `set_cell()` wakes belts itself, so painting
matter *directly into* the cell above a belt starts it. Dropping matter from one cell higher —
which is what "drop matter onto it" means, and what a player does — left the matter sitting on a
dead belt forever:

| Matter placed | Belts considered | Moves | Milestone |
| --- | ---: | ---: | --- |
| directly in the cell above the belt | 12 | 1 | reached |
| one cell higher, allowed to fall | 0 | 0 | never |

Belts existing is the condition, not belts already running. `tests/build_flow.gd` now follows
the printed instruction literally — place the Conveyor in open air, drop Sand from four cells up,
step — and asserts the matter travels and the milestone is reached. It drops from a height on
purpose: painting into the adjacent cell would pass through the `set_cell()` path and prove
nothing.

---

## Verification

`tests/build_flow.gd` walks the path a player actually takes — open the catalog, pick a
Conveyor, click in the world — and asserts each step. Before the fix it failed four of its
checks: the catalog stayed open, world input stayed blocked, the click was swallowed, and the
refusal said nothing.

| | Result |
| --- | --- |
| `tests/build_flow.gd` | 74 checks |
| `scripts/test.ps1` | `TEST_SUITE_PASS scripts=35` |
| `tests/phase139_ftue.gd` | 329 checks |
| `tests/phase139b_layout.gd` | 237 checks |
| owner package smoke | all eleven flows `1` |

---

## Open, and needing an owner decision

**Factory Mode offers tools its own capability table forbids.** `GameModeCapabilities` declares
`creative_paint`, `creative_erase` and `world_edit` as Creative-only, and Factory Mode runs with
`ProgressionMode.NORMAL`. Yet the Factory quickbar offers raw material brushes — Wood, Charcoal,
Smoke, Raw Sand — and nothing enforces the capability anywhere in the command path. A player can
paint any matter into existence in a mode whose whole point is that matter must be processed for
real, which makes the Research economy optional.

Either the capability table is wrong or the catalog is. I have not guessed which: enforcing the
table as written would also remove the brush from Factory Mode, and the brush may be the only
way to excavate there, since Factory Mode has no character to dig with. That is a balance
decision, not a defect fix.

**Four Experiments need counters that do not exist**, described in §8. Each needs a decision
about what the simulation should measure before it can be wired.

**The quickbar is ten unlabelled glyphs.** They carry numbers and tooltips, and the Conveyor is
in slot 1, but nothing on the first screen connects "press 1" to "place a Conveyor".
