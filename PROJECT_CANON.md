# KoalaSand Project Canon

## Physical-interaction-first principle

If a process can reasonably be represented as visible physical interaction between simulated matter and structures/fields, KoalaSand should prefer that over black-box machine input/output conversion.

Order of preference: physical geometry/gravity; physical forces/fields; permeability/collision; temperature/chemistry; small bounded state only when necessary; black-box conversion only as a last resort. The factory should normally explain itself by visible motion, accumulation, blockage, separation, heating, and reaction.

- 2D side-view, physics-driven factory automation sandbox with Factory, Character, and Creative player presets over one identical physical world.
- Physical resources remain simulated world matter. Gravity, routing, contamination, spills, clogs, and throughput stay relevant.
- One primary cell simulation: background decoration, main simulation layer, and foreground/UI are presentation concepts, not separate physics worlds.
- Direct god/sandbox interaction through mouse tools.
- Buildings are free after research unlock. Glass, Iron, and Gold physically deposited into Research Banks are irreversibly consumed into one global progression ledger; Storage Bins remain physical and separate.
- Branching research should drive redesigned, specialized processing chains rather than simple percentage upgrades.
- Regional geology determines Raw Sand composition. Per-cell random loot/composition dictionaries are prohibited.
- The technical direction is deterministic, data-oriented, persistent, chunked, and scalable.
- Godot Nodes represent presentation and higher-level entities, never individual cells or grains.
- Structures occupy a native layer independent from physical matter. Placement is free after unlock, never silently deletes matter, and physical storage capacity is geometric volume.
- Conveyors move complete physical cell state on the fixed simulation timeline. Jams, belt ends, Funnel backup, bin overflow, and removed support resolve through world physics rather than hidden inventories.
- Geological grains carry immutable `uint16` provenance and `uint16` mineral signature. Separation/recovery reveals deterministic hidden constituents; moving or retrying a grain cannot reroll it.
- Dry processors conserve physical mass. Vibrating Screen permeability, Overbelt magnetic fields, and Radiant Furnace heat act directly on visible grains in real cells. No processing structure owns a hidden grain inventory or recipe timer. Crude Residue remains traceable future feedstock.
- Fresh games begin with Foundation only. Sieve and Magnetic Separator remain visibly locked until their stable research IDs are purchased atomically. Major processing unlocks create new factory topology; secondary global upgrades affect existing machines only for future work.
- Gravity increases world-cell `y`. Stone is immovable; Raw Sand falls down, then one cell diagonally when blocked; Water is divisible integer mass with local falling/spreading activity.
- Enclosed Pipes are spatial 16-byte segment records, never a global network inventory. World/Pipe boundaries are adjacent, atomic, temperature-preserving transfers. Damage is local: cut, overpressure, heat, or fire can breach one segment and its enclosed Water leaks back into the physical world.
- Industrial Reservoir storage is ordinary world Water inside removable walls. Overflow and wall breaches are physical. Wash Sluices use real Water, physical grains, local flow and visible riffles; no hidden process inventory exists.
- Local damage with visible physical consequences is the general design direction. Phase 8 implements Pipe failure and Reservoir-wall breach; general machine damage/corrosion remains outside this phase.
- Simulation traversal and ambiguous granular choices are deterministic for equal seed, initial state, tick count, and input sequence.
- Default visual direction: fine-pixel side-view with small effective cells, restrained per-material variation, readable exposed surfaces, large calm cave fields, and local light islands. Chunk grids and diagnostics are opt-in debug layers, never the normal look.
- Visual noise, surface shading, atmosphere, lighting, and HUD must remain presentation-only. They may not alter material state, traversal, or replay hashes.
## Phase 6 canon

Automation controls the same physical granular world through deterministic integer signals. It does not add electronics crafting, power, fluid flow, thermal gameplay, geological prospecting, or scripting. Those remain future systems with separate architecture gates.

## Phase 7 canon

Water is divisible physical matter in world cells. Reservoirs, dams, waterfalls, flooding, and Sand displacement are local, integer-conserved simulation. Basic belts never transport Water, gates never delete it, and machines are collision geometry rather than liquid black boxes. Pumps, pipes, Tanks, wet processing, Steam, Ice, gases, chemistry, and thermal diffusion are outside Phase 7.

## Phase 8 canon

Pipes, Junctions, Intakes, Outlets, finite-head Pumps, Valves, Flow Meters, Pipe Fill Sensors, physical Industrial Reservoir walls, and Wash Sluices are production systems. Pipe Water is spatially distributed and exactly conserved with world Water. Reservoir and Sluice Water remains normal dynamic Water. Steam, Ice, gases, Oil, Acid, Lava, electricity, chemistry, corrosion, general machine damage, player character, networking, and full save/load have not started.

## Phase 8.5 canon

At the historical Phase-8.5 gate, dense infrastructure presentation used spatial `64x64` native pages with dirty topology/dynamic textures; sparse structures and machines retained MultiMesh batching. Rendering was never authoritative. Thermal work was an isolated fixed-integer candidate with active fronts, deterministic worker merges, material conductivity/capacity traits, and generic heat sources. No production diffusion or phase transition was active; Steam, Ice, molten metal, gas, and Phase 9 had not started.

## Phase 8.75 canon

Construction UX, inspection, planning, copying, replacing and navigating large factories are core gameplay systems rather than late polish. Mass construction routes through canonical `CommandBatch` records; ordinary Undo changes construction in the current world and never rewinds physics.

Matter may travel through visible world space or dedicated finite-capacity logistics spaces such as subsurface channels, but ordinary logistics must preserve material state, spatial route, throughput, blockage and congestion. Three depth-separated Subsurface Channels are physical finite lanes with stable pairs, one packet per hidden position, backpressure and `MUST_DRAIN` removal.

The Radiant Furnace remains a field source, not a recipe black box.

## Phase 9 canon

Heat, cooling, phase change, Steam transport, melting and casting are spatial physical systems. The Furnace adds energy to nearby matter or Pipe contents; it never consumes an input into a timed hidden output. Ice/Water/Steam and Glass/molten Glass and Iron/molten Iron conserve family amount and enthalpy across motion, transition and Pipe boundaries. Provenance and mineral signature survive every transition.

Steam is finite rising matter and may be enclosed in spatial Pipes. Pressure and temperature damage are local. A cut or failed segment leaks its actual contents into the world, where normal gas/liquid/thermal rules continue. Thermal Switches gate local conduction; Heat Exchangers exchange energy between external ports without teleporting matter.

Research unlocks thermal tools, rated infrastructure and sensors, never natural diffusion or phase laws. Steam power, electricity, turbines, nuclear systems, advanced chemistry, scientific CFD, player character, networking and full save/load remain outside Phase 9.

## Phase 10 power canon

The implemented chain preserves heat through Water/Steam, Pipe pressure/flow, Turbine rotor, Shaft and Generator. Steam cannot disappear inside a power black box; blocked exhaust causes backpressure, and condenser loops use ordinary cooling, phase change and Pumps. Mechanical and electrical energy use conserved integer quanta at 30 Hz. Electrical distribution is a cached connected-network abstraction; Automation remains a separate `int32` control network. Existing Pumps, Screens and Magnets retain a functional unpowered baseline. See `POWER_ARCHITECTURE.md`.

## Phase 11 world and player canon

Factory, Character, and Creative are capability presets, never alternate simulation rules. `WorldIdentity(seed, generation_version, generator_settings_hash)` alone selects the world. Character is embodiment/local knowledge, not a survival-stat layer: Basic Jetpack is available immediately, build placement remains free after Research, Dig preserves matter, and discovery never exposes hidden geology. See `GAME_MODES.md`, `WORLD_GENERATION_V2.md`, and `CHARACTER_MODE.md`.

## Phase 11.5 game-feel canon

Normal player UI is world-first, contextual, compact, InputMap-driven, and shared across presets. Character receives responsive fixed-tick movement, bounded camera look, an 18-cell local interaction range, persistent live/stale/unknown discovery, immediate Basic Jetpack, early Sprint, and precision Hover. Convenience, accessibility, cancellation, Undo, Pipette, Blueprints, and readable failure reasons are not artificial Research friction.

Phase 12 fulfills that boundary: Trees fall as deterministic clusters and settle into conserved Wood/Leaves; moisture, oxygen, fire, Smoke, Ash and Charcoal use ordinary world matter and heat. Iron Pots contain real Water/Food cells; boiling and cooking emerge from conduction, phase change and temperature-time exposure. Research unlocks convenience infrastructure, never natural reactions. See `ORGANIC_PHYSICS.md`, `COMBUSTION_ARCHITECTURE.md`, and `PHYSICAL_COOKING.md`.

## Phase 13 conservation canon

Processing yield is deterministic and exactly constituent-conserving. Generation may choose geology; runtime separation may not choose yield with RNG. Fractional material is real authoritative mass included in hashes, saves and deconstruction checks. Screens, sluices, magnets, furnaces, vessels and boilers are ordinary single-purpose blocks plus geometry. Blueprints add convenience only. See `MATERIAL_CONSERVATION.md` and `COMPOSABLE_PROCESSING.md`.
