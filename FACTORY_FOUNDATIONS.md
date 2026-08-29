# Factory Foundations

> **HISTORICAL ARCHITECTURE GATE:** Phase 8.75 origin record. Current construction, Blueprint and logistics contracts are indexed in `docs/INDEX.md`.

Phase 8.75 establishes construction and inspection as production systems. It does not add production thermal simulation.

## Focused research

- Factorio: paired finite underground runs, pipette, copy/cut/paste, Blueprints, planners, Quickbars, ALT information and production statistics are coherent parts of one construction workflow. KoalaSand adopts explicit linked runs, one canonical `CommandBatch`, bounded histories, contextual Info Mode and event-driven statistics. References: <https://wiki.factorio.com/Underground_belt>, <https://wiki.factorio.com/Controls>, <https://wiki.factorio.com/Blueprint>, <https://wiki.factorio.com/Copy_and_paste>.
- Shapez 2: layers, tunnels, large Blueprints and a readable zoomed-out factory view make mass construction understandable. KoalaSand adopts three explicit depth layers and automatic Overview LOD, while retaining a side-view cellular world. References: <https://shapez2.com/>, <https://shapez2.wiki.gg/wiki/Knowledge_Panel>, <https://shapez2.wiki.gg/wiki/Map>.
- Sandustry: routing, Filters, launchers and research confirm the value of physical factory tools and clear progression feedback. KoalaSand implements finite subsurface routing and prepares compact permeability/field contracts; Selective Filters and launchers remain future work. References: <https://wiki.hoodedhorse.com/Sandustry/Research>, <https://wiki.hoodedhorse.com/Sandustry/Filter>, <https://wiki.hoodedhorse.com/Sandustry/Launchers>.
- The Powder Toy: portal channels, powered pipes, heat switches and pressure-driven tools demonstrate reusable material/field interactions. KoalaSand prepares `LinkedTransportEndpoint`, `PermeabilityRule` and `PhysicalFieldSource`; Matter Portals, Fans and Heat Switches are not implemented. References: <https://powdertoy.co.uk/Discussions/Thread/View.html?PageNum=0&Thread=13667>, <https://powdertoy.co.uk/Discussions/Thread/View.html?PageNum=0&Thread=11131>, <https://powdertoy.co.uk/Discussions/Thread/View.html?Thread=23417>.
- Oxygen Not Included: separate plumbing, temperature and automation overlays demonstrate that large simulations need task-specific analysis views. KoalaSand formalizes stable overlay IDs and computes only providers that exist. Reference: <https://oxygennotincluded.wiki.gg/wiki/Overlays>.
- Noita and Sandspiel: local material rules and dense cellular interaction support the physicality-first model; Sandspiel also demonstrates browser delivery of dense cellular play. KoalaSand keeps fixed-width native authority, deterministic local interactions and a single-thread Web fallback. References: <https://noitagame.com/>, <https://noitagame.com/release_notes/20201015/>, <https://github.com/MaxBittker/sandspiel>, <https://experiments.withgoogle.com/sandspiel>.

No source code, artwork, exact UI or exact machine layout was copied.

## Adopted foundation

- `WorldCommand` remains the only gameplay-mutation primitive. `CommandBatch` adds schema, stable batch/actor IDs, sequence, label, explicit order and `ATOMIC`/`BEST_EFFORT` semantics.
- `ConstructionHistory` stores at most 64 forward/inverse batch pairs by default. Undo changes structures now; it never rewinds simulation or restores old matter snapshots.
- Pipette copies build type plus safe orientation/configuration metadata, never runtime buffers.
- Fast replace uses `upgrade_family` and `replace_compatibility`. Upgrade and Deconstruction planners emit one batch.
- Blueprint data is relative, versioned and free of physical material/runtime state. See `BLUEPRINTS.md`.
- Ten Quickbar pages of ten slots are serialization-ready; only the selected page exists in the active UI row.
- Info Mode uses one native query and a batched badge `MultiMesh`; it creates no per-machine `Control` or `Label` nodes.
- Alerts are bounded, source-keyed, rate-limited and position-addressable for camera focus.

## Prepared, not implemented

Matter Portals, Selective Material Filters, Fans/Blowers, Material Launchers, advanced Upgrade Planner policies, Blueprint Books, regional production statistics, and additional Activity/Damage/Pipe-Pressure/Production overlay providers remain explicit future capabilities. Phase 9 subsequently promotes Heat Switches and production thermodynamics; see `THERMODYNAMICS.md`.

## Phase 9.5 Power preparation

Blueprint-safe future field names, port roles, priority IDs and Power Switch commands are reserved in `PowerContract`; they do not create buildable entities. Phase 10 should introduce powered variants/upgrades gradually instead of disabling existing legacy factories. Cables will occupy a non-blocking infrastructure layer and use batched presentation. Physical Turbine inlet/exhaust and local shaft coupling precede the abstract electrical graph. See `POWER_ARCHITECTURE.md`.

## Phase 11 mode reuse

Factory retains the existing omniscient God camera and unrestricted build reach. Character reuses the same Quickbar, Build Catalog, Blueprint/command, structure, Research, and physical simulation paths but validates every selected cell against an 18-cell local interaction/access line with precise rejection reasons. Creative alone receives material paint and erase. No preset adds structure placement costs or alternate factory recipes.

## Phase 13 component foundation

Structure IDs `37..47` are ordinary reusable physical components. The example library builds Screen, Wet Sluice, Charcoal Chamber, Furnace, Metal Vessel and Steam Boiler from those entries. Placed assemblies retain no Blueprint identity. Runtime constituent carry belongs to component/network state and is deliberately excluded from Blueprint copy/paste.
