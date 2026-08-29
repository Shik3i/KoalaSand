# Physical steam power architecture

Phase 10 implements the authoritative chain:

```text
Pipe Steam mass + enthalpy + pressure
  -> Steam Turbine
  -> cached mechanical Shaft component
  -> Generator
  -> cached Power Pole component
  -> priority consumers / Accumulator
```

The Turbine and Generator are separate physical machines. A Generator never consumes Steam. A Turbine admits finite Steam from its inlet `PipeSegment`, emits exactly the same mass into its exhaust `PipeSegment`, extracts bounded enthalpy, adds mechanical energy to its shaft component, and sends conversion loss into nearby material heat. Backpressure, missing Steam, full exhaust, startup, running, overspeed, disabled and no-load states are native state, not scripted outcomes.

## Canonical units and cadence

- Thermal, mechanical and electrical energy use the same signed `int64` game-energy quantum.
- This is a conservation unit, not a claim that one quantum equals one SI joule.
- Power is energy quanta per authoritative Power tick.
- Mechanical and electrical cadence is `30 Hz`, derived from every second `60 Hz` world tick.
- Authoritative speed is integer milli-RPM. `speed = integer_sqrt(2 * energy * 10^9 / inertia)`.
- Allocation, efficiencies, governor values and satisfaction use integer per-mille arithmetic.
- Float values are presentation/benchmark values only.

`get_energy_accounting()` exposes cumulative thermal input, mechanical production/consumption, electrical production/consumption/storage/discharge, Turbine losses, Generator losses and storage losses. Quantization remainders remain in the existing signed thermal rounding reservoir.

## Mechanical network

Shafts are non-solid one-cell infrastructure. Turbine, Generator and Flywheel expose oriented mechanical member cells. Native N/E/S/W connected components use the smallest stable member ID as network ID. Components cache members, inertia, rotational energy, speed, requested output, delivered output and friction loss. Topology work occurs only after construction, removal or switching; idle ticks do not traverse shaft cells.

Split/merge conserves existing component energy by deterministic inertia-weighted member shares. Integer remainder goes to the smallest member ID. A Flywheel adds inertia and stores no separate hidden fuel; spin-up is slower and stored rotational energy is part of the same component.

Mechanical friction is deterministic (`energy / 200000` each Power tick). Turbines add energy before Generators request load. Generator electrical capacity scales continuously with real shaft speed. Ten-percent rated speed is the startup cut-in; above it the speed factor remains continuous.

## Steam Turbine

The default Turbine has a physical inlet at local `(-1,1)`, exhaust at `(6,1)`, and shaft coupling at `(5,2)`. Admission is bounded by inlet mass, exhaust capacity, throttle, rated flow and the integer inlet/exhaust potential difference. Governor throttle rises below 98% target RPM and falls above 110%; `max_throttle`, `target_millirpm` and enable state are configurable.

For admitted mass:

```text
moved_enthalpy = inlet_enthalpy * admitted_mass / inlet_mass
extractable = max(0, moved_enthalpy - steam_floor_enthalpy(admitted_mass))
mechanical = extractable * turbine_efficiency / 1000
waste_heat = extractable - mechanical
exhaust_enthalpy = moved_enthalpy - mechanical - waste_heat
```

No Steam mass disappears. A full, incompatible or sufficiently pressurized exhaust produces `EXHAUST_BLOCKED` or `BACKPRESSURE`. Exhaust remains ordinary Steam for Pipe transport, cooling, condensation and return pumping.

## Electrical network and brownouts

Power Poles auto-connect to the four nearest compatible poles within 24 cells using stable distance/ID tie-breaking. A pole covers consumers within 12 cells. `CONFIGURE_POWER_PORT` may pin Generator, Accumulator or consumer supply to an explicit stable `pole_position` without moving the machine; an invalid position clears the pin and falls back to nearest coverage. Cached connected components aggregate demand by `CRITICAL`, `HIGH`, `NORMAL`, `LOW`, generation, delivery, surplus and storage. Automation wires remain a separate directed `int32` signal graph and never carry energy.

Allocation order is fixed:

1. actual Generator output constrained by shaft energy, speed, capacity and efficiency;
2. Accumulator discharge during shortage, bounded by charge/rate/efficiency;
3. consumer classes from critical to low;
4. one fixed-point satisfaction ratio inside each class;
5. Accumulator charge from remaining supply;
6. residual surplus.

Consumers resolve their cached network/class satisfaction on demand. Stable 100k-node grids do not rewrite every consumer each tick. Physical Resistive Heaters alone remain active consumers because delivered electrical energy becomes local world heat. Pump, Screen and Overbelt Magnet retain their unpowered baseline and scale their optional electric improvement by `0..1000` satisfaction.

Power Switches connect two otherwise separate pole components and are controlled by WorldCommand or Automation. Opening/closing invalidates topology once. Alerts cover brownout, Generator overload, Turbine overspeed and backpressure.

## Storage

An Accumulator stores authoritative electrical energy with finite capacity, charge/discharge rates and separate integer efficiencies. Charge can only come from network surplus. Discharge can only reduce a shortage. Losses are counted; storage never creates energy. A Flywheel is the corresponding mechanical buffer and changes the physical component inertia.

## Transformer decision

Transformer port/state structs, schema boundary and serialization hooks are prepared but the structure is deliberately not exposed in Phase 10. With the current 24-cell pole auto-link rule, poles placed at the two sides of a compact Transformer would also connect directly and silently bypass it. Shipping that would be a fake boundary. A later voltage-domain or explicit-circuit assignment design must make the two sides genuinely distinct before the Transformer enters the catalog. No Transformer benchmark or gameplay claim is made.

## Automation, commands and persistence

Automation types `22..24` are Power Network Sensor, Shaft Speed Sensor and Power Switch Control. Network sensor modes report satisfaction, generation, demand, surplus or storage fraction. Machine sensors can observe Turbine/Generator state. Commands `21..23` configure switch, priority and Power port state through the existing ordered command boundary.

Blueprint/config serialization includes stable entity configuration such as Turbine governor and switch state. It explicitly excludes RPM, rotational energy, live generation, satisfaction and Accumulator runtime charge. Connected-component caches, render batches and allocation scratch are derived. `authoritative_physical_hash()` includes `power_state_hash()`; worker `[1,2,4,8]` parity is a required gate.

## Rendering and platform

Godot receives compact visible records only. Machines are one MultiMesh; shared shader `TIME` animates a rotor from native speed data. Shafts, pole markers and cables are one optional POWER-overlay MultiMesh. Normal view avoids cable clutter. No per-shaft, per-pole or per-consumer Node exists.

The repository has no audio bus, authored sound assets or existing machine-audio subsystem. Phase 10 therefore exposes native speed/load/state hooks only; Turbine hum, Generator load tone, overspeed warning and switch transient are deferred rather than synthesized as misleading placeholder audio.

The implementation uses C++20 fixed-width state, integer authoritative math and the GL Compatibility presentation path. Native GDExtension remains the current desktop authority. Web requires the custom Web-capable extension/template path already described in `PLATFORM_ARCHITECTURE.md`; networking remains unimplemented.
