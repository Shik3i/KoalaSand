# Physical Processing Canon

## Governing rule

If a process can reasonably be represented as visible physical interaction between simulated matter and structures or fields, KoalaSand uses that representation instead of hidden machine input/output conversion.

Preferred order: geometry and gravity; forces and fields; permeability and collision; temperature and chemistry; bounded machine state only when unavoidable; black-box conversion only as a last resort.

## Current audit

| System | Classification | Production behavior |
| --- | --- | --- |
| Conveyor | PHYSICAL | Moves one visible cell at a time; congestion blocks transport. |
| Funnel | PHYSICAL | Geometry redirects falling matter. |
| Storage Bin | PHYSICAL | Matter occupies visible cells inside physical walls. |
| Control Gate | PHYSICAL | Collision geometry opens or closes safely. |
| Vibrating Screen | PHYSICAL | Stable grain size controls deck permeability; deterministic vibration advances supported coarse grains; fine grains fall through into player-built collection. |
| Overbelt Magnetic Separator | PHYSICAL | Local fixed-point field lifts susceptible grains cell by cell; a capture surface transports them; blockers and pile depth reduce capture. |
| Radiant Crude Furnace | PHYSICAL | A local heater raises the existing per-grain absolute quarter-kelvin `uint16` temperature while matter travels through an open heating bay; threshold reactions occur in place. |
| Research Bank | INTENTIONAL ABSTRACTION | Deposits useful physical material into the global research reserve. This is the sole current meta-progression boundary, not a processing template. |

The former black-box `Vibrating Sieve`, two-output `Magnetic Separator`, and recipe-loop `Crude Furnace` are not production designs and are no longer scheduled by `process_machines()`.

## Vibrating Screen

The 10×5 structure contains a physical deck at local `y=3`. Grain size is a stable function of material, `uint16` geology profile, and `uint16` mineral signature. `FINE`, `MEDIUM`, and `COARSE` are derived without new per-cell allocation and never reroll during movement.

Fine grains may enter a permeable deck cell only while moving downward. Crossing changes `Raw Sand` to `Fine Sand` while preserving profile and signature. Coarse grains remain supported above the deck. A bounded impulse derived from seed, screen ID, tick, cell, and signature agitates deck-adjacent grains laterally. A long, evenly fed deck therefore gives more screening opportunity; overload and blocked collection create visible backups.

## Overbelt magnetic separation

Susceptibility is data-driven by stable material and hidden constituent traits. Iron-bearing grains and iron products are strongly susceptible; heavy minerals are weakly susceptible; silica and gold-bearing constituents are nonmagnetic.

Each magnet registers only its intersected chunks and a compact interaction rectangle. Material changes wake only nearby registered processors. Field strength is integer-valued, attenuates by 180 units per cell from the capture surface, and combines in deterministic processor-ID order. A grain moves at most one cell in a phase because the shared moved flag applies to gravity, fields, belts, and capture transport.

Lift never bypasses collision. Stone, structure walls, another grain, insufficient clearance, or downstream congestion blocks extraction. Captured grains move along the upper physical route and fall naturally after leaving the field. Magnetic `Heavy Concentrate` becomes `Iron Concentrate` only at the physical capture boundary; no grain is created or destroyed.

## Radiant Furnace

The 10×4 furnace is an overhead heating block with an open 8×3 bay. It has no hidden input, output, timer inventory, or teleport port. Each affected moving grain receives deterministic distance-attenuated heat in its existing temperature field. At the current provisional reaction threshold, material changes in the same physical cell and retains provenance and signature.

Fuel combustion, phase changes, liquid metal, casting, molds, and environmental cooling belong to the later Thermal/Fluid phases. Their future implementation must extend the same temperature-bearing physical path; it must not restore an opaque recipe loop.

## Future implementation checklist

Before adding any module:

- Can geometry, gravity, a local force, permeability, temperature, or chemistry make the operation visible?
- Does every grain traverse real cells without teleportation?
- Can blockage, overload, spill, pile depth, or downstream congestion affect the result?
- Are identity, provenance, signature, temperature, and conserved mass preserved?
- Is expensive work spatially registered and asleep when inactive?
- Is any remaining abstraction explicitly justified as a UI/meta boundary rather than copied into processing?

## Phase 7 Water interaction

Water is nonmagnetic; reachable magnetic grains still receive field force. Radiant heat affects authoritative cell temperature, while transferred Water carries and mass-weights its temperature. Furnaces, Screens, and Magnets gain no liquid inventory, wet separation, damage, corrosion, or phase change.
# Phase 8 Wash Sluice

The Wash Sluice is open `18x6` world geometry. Local dynamic Water mobilizes grains; density/constituent/grain size changes the movement threshold; four visible riffles capture heavy material at moderate flow. Classification occurs only at a physical capture or exit cell. Grain count, provenance, signature, and Water mass are conserved. Details: `WET_PROCESSING.md`.

## Phase 8.5 heat-source boundary

Radiant Furnace heating now enters through the generic native heat-source interface, but retains its established local Phase-6.5 behavior. It contains no recipe inventory. Future processing must result from material spending enough simulated time in a temperature field, followed by physical separation, liquid-metal transport, casting, and cooling. The isolated thermal candidate does not activate these transitions.

## Phase 8.75 reusable interactions

The Screen now consumes a compact precompiled 16-byte `PermeabilityRule` covering material mask, grain class, provenance/signature filters and future state flags. Plain solid collision does not call a polymorphic predicate. `PhysicalFieldSource` is a 16-byte registration with stable Magnetic, Airflow, Heat Source, Gravity Modifier and Radiation kinds; only existing Magnet and Radiant Furnace behavior executes.

At the Phase-6.75 architecture gate, Selective Filters/membranes, Fans/Blowers, Material Launchers and Heat Switches were future mechanics. Wet-processing transformations and real machine transforms emit aggregated Production Statistics events without scanning cells.

## Phase 9 thermal processing

The Phase-6.75 future statement above is historical. Thermal Switches and Heat Exchangers are now production structures. The Radiant Furnace deposits energy into its physical region and neighboring Pipe contents. Glass and Iron transform only after sensible plus latent heat is supplied; molten material flows, spills and solidifies through world physics. Cooling/casting uses geometry and heat exchange, never a Furnace inventory, recipe timer or hidden output. Selective fluid filters, Fans/Blowers and Material Launchers remain future work.

## Phase 12 physical fuel correction

The Radiant Furnace no longer creates free heat or deletes a hidden fuel unit. It scans exposed Coal/Wood/Charcoal cells in its open bay, requires ignition temperature, and conservatively transfers configured stored fuel energy into nearby physical matter. Fuel loss, oxygen use, Ash and Smoke remain the generic organic reaction system's responsibility. A low-oxygen Stone enclosure is therefore a physical charcoal kiln; no charcoal recipe or machine exists.
