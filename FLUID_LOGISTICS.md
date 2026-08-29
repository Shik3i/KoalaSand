# Physical Fluid Logistics

Phase 8 adds enclosed Water transport without adding a network inventory. The authoritative route is always local:

```text
world cell -> Intake segment -> adjacent segment(s) -> Pump/Valve -> Outlet segment -> world cell
```

Every pipe cell owns one compact value record; there is no network object that stores mass and no transfer can skip a neighboring cell.

## Segment record

`PipeSegment` is exactly 16 bytes:

| Field | Type | Meaning |
|---|---|---|
| `fluid_type` | `uint16` | `0` empty, `3` Water; future IDs reject incompatible transfer |
| `mass` | `uint16` | `0..65535` local capacity units |
| `temperature` | `uint16` | absolute quarter-kelvin |
| `pressure` | `uint16` | transported finite Pump head |
| `last_flow` | `int16` | signed most-recent local edge flow |
| `health` | `uint16` | `0..1000`, local failure at zero |
| `flags` | `uint8` | disabled, valve-closed, breached, moving, quiet counter |
| `connection_mask` | `uint8` | N/E/S/W local topology |
| `type_id` | `uint8` | Pipe/Junction/Intake/Outlet/Pump/Valve |
| `orientation` | `uint8` | canonical cardinal direction |

Only pipe-bearing cells allocate records. Empty world chunks and dry chunks without infrastructure pay zero pipe-state cost.

## Deterministic local solver

For an edge from cell `a` toward neighbor `b`:

```text
fill_head(a) = mass(a) * 48000 / 65535
potential(a, direction) = fill_head(a) + pressure(a) + y(a) * 32 + directional_pump_head(a)
delta = potential(a, a->b) - potential(b, b->a)
transfer = min(source_mass, destination_free, rate, abs(delta) / 4)
```

The deadband is `64`. Basic passive rate is `2048` mass/tick. A Basic Pump supplies `8192` head and at most `4096` mass/tick; `fluid.pressurized_transport` raises these to `12288` and `6144`. Head is passed span-by-span, so series Pumps extend lift; it is finite and does not disable elevation. Gravity uses increasing world `y`, therefore passive Water prefers lower Pipes.

Edges use sorted cell keys, canonical N/E/S/W order, and tick-parity reversal for equal alternatives. All authoritative arithmetic is integer-only. Worker count does not affect pipe state; the event-driven pipe solver is intentionally serial because the active-set cost is below the parallel handoff threshold and this preserves the single-thread/WASM fallback.

Changed mass, topology, devices, Intake/Outlet interaction, control signals, and damage wake the affected segment and its neighbors. Eight quiet ticks put an equalized region to sleep. An idle 100k network visits zero segments.

Temperature follows mass. Mixing uses:

```text
mixed_temperature = (temperature_a * mass_a + temperature_b * moved_mass) / total_mass
```

The final unit leaving a segment resets it to `fluid_type=NONE`, `mass=0`, and ambient temperature. A future incompatible fluid is rejected at the local edge; Phase 8 implements Water only.

## Physical boundaries and damage

An Intake reads only its single adjacent forward world cell. An Outlet writes only its single adjacent forward world cell. Both atomically subtract and add the same integer mass and temperature. A full/solid Outlet cell blocks emission and retains upstream mass.

Pipes have local health. Cutting a filled segment causes a breach instead of erasing its contents. Total pressure above `60000`, Water above the reaction-temperature threshold, fire/heater exposure, or an explicit damage command reduces that segment's health. A failed segment disconnects and leaks up to `4096` mass/tick into neighboring world cells in deterministic down/left/right/up order. The emitted mass immediately becomes ordinary dynamic Water; it floods, falls, spreads, wakes sensors, and remains in the exact world-plus-pipe conservation sum. Removing the dry broken remainder is then safe.

This is the project-wide physicality direction: damage and failure should be local and produce visible physical consequences. Phase 8 concretely applies it to Pipes and geometric Reservoir walls; it does not start a general machine-damage, corrosion, or chemistry system.

## Devices and automation

- Intake: adjacent world cell only; no input means `NO_INPUT`.
- Outlet: physical world emergence; blocked cell means `OUTPUT_BLOCKED`.
- Pump: bounded state, finite rate/head, `ENABLE` control, no tank.
- Valve: local connection open/closed; closing never deletes enclosed Water.
- Flow Meter: recent signed local edge movement, no network polling.
- Pipe Fill Sensor: local `0..1000` fill.

Valve closure differs from a world Control Gate: a Valve blocks an enclosed pipe edge without needing an empty matter cell; a Gate changes physical world collision.

## Design research

The production design deliberately avoids two known extremes:

- Factorio's earlier per-fluidbox model exposed construction-order asymmetry and update-order artifacts; stable canonical local order and a two-stage local transfer avoid that class of nondeterminism. [Factorio FFF-416](https://direct.factorio.com/blog/post/fff-416)
- A single contiguous-system inventory is cache-efficient but effectively teleports liquid inside a network and discards route/head gameplay. KoalaSand keeps per-segment distribution and uses sparse activity instead. [Factorio FFF-430](https://www.factorio.com/blog/post/fff-430), [Factorio FFF-442](https://factorio.com/blog/post/fff-442)
- Local fullness-proportional transfer and explicit mixing prevention informed the fixed-point edge rules, without copying implementation code. [Factorio FFF-271](https://factorio.com/blog/post/fff-271), [Factorio FFF-274](https://direct.factorio.com/blog/post/fff-274)

Networking later sends `WorldCommand`s, not every transfer. Periodic physical hashes and spatial pipe-region resync remain possible. No networking is implemented in Phase 8.

## Phase 8.5 thermal boundary

Pipe `uint16` temperature remains local transported state. Production Pipes do not yet exchange heat with walls/world cells. A future implementation must register segment-local heat exchange, wake only neighboring thermal fronts, conserve energy across contained Water and pipe material, and feed over-temperature damage through the existing local breach/leak path. No network-average temperature or hidden furnace inventory is permitted.

## Phase 8.75 integration

Pipe/Pump/Valve placement and configuration can be serialized inside Blueprint/`CommandBatch` data, but Pipe mass, temperature and runtime flow are never copied. Construction Undo uses current-world device removal semantics; it does not restore earlier fluid. Production Statistics records real world-to-Pipe, Pipe-to-world/leak and segment-throughput amounts in fixed one-second rings. Subsurface channels carry granular packets only; they are not fluid Pipes or portals.

## Phase 9 Steam, heat, and failure

Pipe segments carry Water or Steam with local mass, temperature, enthalpy and sparse latent progress. World/Pipe and Pipe/Pipe moves preserve proportional enthalpy. Adjacent physical matter exchanges heat with contents, so enclosed Water can boil and Steam can condense. The solver reports `steam_pipe_throughput` separately.

Steam adds a deterministic temperature-dependent local pressure contribution. Overpressure and excessive temperature damage the affected segment. Cutting or breaking it releases the actual contents through `pipe_to_world`; Steam prefers up/left/right/down and Water prefers down/left/right/up. Only the local segment breaches. See `STEAM_AND_GASES.md` for the exact contract and declared gameplay approximation.

## Phase 9.5 active-Pipe scheduler

The active set retains exact Phase-9 wake membership but reuses sorted/candidate/filter buffers. Connection masks reject absent directions before neighbor-map lookup; known segment references avoid duplicate lookup; unchanged non-breach damage does not wake neighbors. Mass-dependent thermal scales use one immutable `1,048,576`-byte lookup. `PipeSegment` remains `16` bytes.

Production 50k alternating Steam Pipes after the reported construction tick: `3.1736 ms` average, `14.1690 ms` p95, `14.4520 ms` p99. Stress 100k: `11.5619/28.3620 ms` average/p99. Stable 100k: zero active/visited/transfers and `0.3024 ms` whole-tick average. Ruptures still emit exact physical world matter and conserve total family mass/enthalpy.
