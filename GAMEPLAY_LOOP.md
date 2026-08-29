# Gameplay Loop

## Player loop

KoalaSand's shared loop is:

1. read the terrain and physical state;
2. move or position the camera/Character;
3. dig, route, contain, separate, heat, cool, or transport real matter;
4. observe jams, spills, pressure, temperature, power, and throughput;
5. deposit processed Glass/Iron/Gold into Research Banks;
6. unlock a qualitatively new construction capability;
7. expand the same physical factory into newly discovered space.

Buildings remain free after Research. Matter, storage, flow, heat, pressure, power, congestion, and damage remain physical. Character changes embodiment, locality, and knowledge; it does not add inventory, stamina, fuel, hunger, durability, or alternate recipes.

## Fresh Character pacing fixture

`FirstSessionFixture` is a deterministic equivalent-time pacing fixture, not a recorded human playtest. It derives Research availability from physically processed Raw Sand throughput and performs zero `credit_research_material_for_test` calls.

| Milestone | Tick | Equivalent time at 60 Hz |
|---|---:|---:|
| first Raw Sand | 90 | 1.50 s |
| first Coal | 470 | 7.83 s |
| first factory | 2,700 | 45.00 s |
| first Research interaction | 7,200 | 2:00 |
| Sprint | 10,200 | 2:50 |
| first cave | 12,600 | 3:30 |
| Hover | 30,600 | 8:30 |

Measured activity: `1,680` cells travelled, `13,740` moving ticks, `9,540` building ticks, `46` Dig actions, `38` Build actions, and `34` structures. Movement share is `0.36`; factory interaction share is `0.64`. The pacing keeps Basic Jetpack immediate, Sprint within the first few minutes, and Hover before the first serious vertical factory.

## Mode expression

- Factory: fastest global planning, normal Research, omniscient presentation.
- Character: local Build/Dig, immediate Jetpack, discovery, normal Research.
- Creative: global planning, everything unlocked, explicit material paint/erase.

All three use the same seed, matter, structures, Research definitions, and simulation laws. See `GAME_MODES.md`, `CHARACTER_MODE.md`, and `PROGRESSION.md`.

Phase 12 adds an everyday sandbox loop without survival upkeep: discover Tree → Cut → visible fall → physical Wood; dry/burn or oxygen-limit it into Charcoal; route fuel/byproducts; place an open Pot over heat; let actual Water boil and physical Food cook or burn. Outcomes remain recoverable world states rather than inventory rewards or recipe completion.

## Phase 13 vertical slice

Normal launch now enters Main Menu, then New/Continue/Load. The shared arc is physical flow → Research Bank → component screening/wet/magnetic separation → real heat and phase processing → automation → Steam → shaft power → electricity → Powered Factory Established. Pause exposes Save, Save As, autosave, accessibility/settings hooks, Return to Menu and safe exit. Onboarding teaches aperture, vibration, density, geometry and temperature instead of recipes.
