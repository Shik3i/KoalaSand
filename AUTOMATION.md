# KoalaSand Automation

Phase 6 adds deterministic factory control without electricity, fluids, temperature gameplay, hidden-geology sensing, or programmable computers.

## Signal model

- Signals are signed native `int32_t` values. Boolean false is `0`; any nonzero value is true.
- Native authoritative records: `AutomationComponent` and `AutomationConnection`. IDs are stable `uint64_t`; ports are stable numeric IDs.
- A directed connection maps one output port to one input port. Outputs support fan-out. Each input accepts at most one source.
- Components and wires occupy no material cell and have no construction cost after research.
- Tick `N` reads inputs committed by tick `N-1`, computes `next_output`, then commits all changed outputs together. Downstream components wake for tick `N+1`. Graph order therefore cannot change results and cycles cannot recurse in one tick.

## Scheduling and graph storage

`automation_dirty_` contains nodes woken by changed inputs, configuration, watched cells, or watched machine state. `automation_scheduled_` contains only timers that currently need simulation-tick work. Changed outputs traverse only their outgoing adjacency list. Idle wires are never visited. Adding/removing an edge updates the source adjacency and target input-source index locally; no connected-component rebuild is required.

The measured direct record footprint for 50,000 components plus 50,000 connections is `8,800,000` bytes: `144` bytes per `AutomationComponent` and `32` bytes per `AutomationConnection` on this 64-bit build. This figure excludes allocator, hash-index, adjacency, and watched-cell storage overhead.

The native/GDScript boundary exposes coarse create/remove/configure/query/serialize operations. Rendering uses one component `MultiMesh` and one wire-segment `MultiMesh`; no Node, `Line2D`, `Area2D`, or Timer node exists per automation record. Wire geometry rebuilds only when topology or the visible region changes.

## Components and stable ports

| Type | Stable ID | Inputs | Outputs | Semantics |
|---:|---|---:|---:|---|
| 1 | `manual_switch` | 0 | 1 | Persistent player-controlled `0/1` |
| 2 | `material_sensor` | 0 | 1 | `PRESENT`, `COUNT`, or one-tick `PULSE` |
| 3 | `level_sensor` | 0 | 1 | `COUNT`, `FILL_PERCENT`, `ABOVE_THRESHOLD`, `BELOW_THRESHOLD` |
| 4 | `not` | 1 | 1 | `input == 0` |
| 5 | `and` | 2 | 1 | both inputs nonzero |
| 6 | `or` | 2 | 1 | either input nonzero |
| 7 | `comparator` | 1 | 1 | `>`, `>=`, `<`, `<=`, `==`, `!=` an `int32` constant |
| 8 | `machine_state_sensor` | 0 | 1 | configured native machine-state predicate |
| 9 | `timer` | 1 | 1 | `DELAY`, `PULSE`, `REPEATING` in simulation ticks |
| 10 | `latch` | 2 | 1 | `SET`, `RESET`; RESET wins |
| 11 | `conveyor_control` | 1 | 0 | unconnected enabled; connected `0` stops transport |
| 12 | `machine_control` | 1 | 0 | unconnected enabled; connected `0` pauses intake/progress |
| 13 | `control_gate` | 1 | 0 | `0` closed, nonzero open |

## Sensors

Material probes are normalized to `1×1`, `1×3`, `3×1`, or `3×3` and rotate from their anchor with component orientation. They compare only the visible material ID; provenance, mineral signatures, constituent flags, and regional geology never enter their output. Native watched-cell lists wake only affected sensors. `PULSE` records a matching-material entry event per watched cell, so a crossing still pulses when another matching cell leaves the probe in the same tick.

Level probes support bounded regions up to `64×64`. `FILL_PERCENT` is integer `0..1000`, where `800` means 80.0%. Storage Bin interiors use their bounded physical cavity as the watched region. Occupancy changes wake the sensor; unchanged regions are not scanned.

Machine sensors attach to one native machine ID and wake on state transitions. Supported numeric states cover `RUNNING`, `IDLE`, `NO_FUEL`, `INPUT_STARVED`, `OUTPUT_BLOCKED`, `DISABLED`, and Research Bank `REJECT_BLOCKED`.

## Actuators

Conveyor ENABLE is cached in the high bit of the existing `uint8` structure record. This adds zero bytes per cell and keeps the hot path to one compact flag read. A disabled Conveyor remains solid support.

Machine ENABLE is cached in `MachineEntity`. Disabled machines retain input/output/fuel buffers, consume no new input, and make no progress.

Control Gate is physical structure type `9`. Open gates are excluded from collision. A close request on an occupied gate cell keeps the gate open with `CLOSE_BLOCKED`; the cell watcher retries after evacuation. State changes wake granular neighbors across chunk boundaries and dirty structure rendering.

## Wiring UI

`Y` toggles Wiring Mode. Shift+`1..9` places basic components, left-click selects output then a free input, right-click deletes a nearby wire, `Esc` cancels, `Delete` removes the selected component, and `Enter` toggles a selected Manual Switch. The compact inspector shows current inputs/output and configuration. Normal play hides wires and subdues component markers; Wiring Mode exposes orthogonal direction paths and selected live values.

Research Tree cards use reusable grid positions, wrapped effect text, selected focus, wheel zoom, middle-button pan, orthogonal dependency edges, and clipped panel contents.

## Research

| ID | Prerequisites | Glass | Iron | Gold | Unlock |
|---|---|---:|---:|---:|---|
| `automation.basic_sensing` | `foundation.basic_industry` | 800 | 15 | 0 | wire, switch, Material/Level Sensor |
| `automation.logic_control` | Basic Sensing | 1600 | 50 | 0 | NOT, AND, OR, Comparator |
| `automation.machine_control` | Logic Control, Dry Separation | 2800 | 140 | 0 | telemetry, Machine/Conveyor ENABLE |
| `automation.timed_control` | Logic Control | 2400 | 100 | 0 | Timer, Memory Latch |
| `automation.advanced_routing` | Logic Control, Machine Control | 4200 | 220 | 1 | physical Control Gate |

Measured Phase-5 profile `3564` estimates: Basic Sensing `4.55 s`, Logic Control `13.66 s`, Timed Control `27.32 s`, Machine Control including Dry Separation `43.26 s`, Advanced Routing `67.16 s`.

## Persistence boundary

`serialize_automation_state()` stores schema version, next IDs, component type/position/orientation/configuration, committed inputs/output, timer/latch state, actuator target and all edges. Deserialization validates types and endpoints and rebuilds watcher/adjacency indexes. No pointer is serialized. Full world saving remains out of scope.

## Diagnostics and measured scale

Diagnostics expose components total/awake, wires, dirty nodes, changed signals, sensor/logic evaluations, actuator changes, circuit milliseconds, topology-build milliseconds, and record bytes.

- Idle: 10,000 sensors + 10,000 logic + 30,000 actuators + 50,000 wires; `0` visited/evaluated/changed, `0.000380 ms/tick` circuit average.
- 10k signal storm: sensor `2.979 ms`, logic `7.459 ms`, 30k actuators `7.503 ms`.
- 2,000 physical sensors: `0.103 ms/tick` measured overhead.
- 50k-wire render: OFF `0.270 ms/frame`; ON `0.374 ms/frame`; one-time 150k-segment topology build `127.850 ms`; steady rebuilds `0`.
- Representative 1080p factory: `473.1 FPS`, `2.116 ms` average frame, `2.778 ms` p95, `4.233 ms` p99, `16.632 ms` worst; automation `0.0167 ms/tick` average.

## Phase 6.5 command/UI integration

The circuit graph and one-tick semantics are unchanged. Wiring is a focused tool in the shared factory HUD; the overlay ID `AUTOMATION` is reserved in the generic selector. Future multiplayer serializes automation mutations through the same ordered `WorldCommand` boundary rather than transmitting graph memory opportunistically.

## Phase 7 Water sensing and dams

Level Sensor `FILL_PERCENT` sums liquid mass: two half-full cells equal one full-cell equivalent before normalization to `0..1000`. Existing Material Sensor modes keep solid semantics; Water adds `MASS` (`mode = 3`) returning bounded raw `uint8` mass sum. A Gate closes only into an empty target; occupied Water yields `CLOSE_BLOCKED`, never deletion. The showcase uses `Level Sensor -> Comparator -> Gate Control` with the unchanged one-tick signal model.
# Phase 8 fluid controls

Stable automation IDs `14..17` add Pump Enable, Valve Control, Flow Meter, and Pipe Fill Sensor. Components watch their target cell; transfer/control/topology changes wake only affected graph nodes. Flow and fill are local integer signals. Existing Comparator/Timer/Latch wiring can regulate Pump flow and Reservoir level without polling a Pipe network.

## Phase 8.75 Blueprint and alerts boundary

Automation components, configuration and wires serialize with Blueprint-relative IDs and remap only after new world IDs are allocated. One ordered batch contains their placement and links. Pipette may copy safe sensor configuration but never latch/timer runtime state. Alert observation reads compact exceptional state only; it does not add an automation signal or tick dependency.

## Phase 9 thermal automation

Component `18` reads world-cell temperature. Component `19` reads local Pipe temperature. Component `20` reads local Pipe pressure. Component `21` actuates a Thermal Switch using the normal committed-signal schedule. All values are deterministic integers and all targets remain spatial cells; there is no global thermal network. `SET_THERMAL_SWITCH` is an ordered replayable command. Overtemperature and Pipe breach alerts observe compact exceptional state without changing simulation order.

## Phase 10 Power integration

Automation and Power are separate networks. Automation continues carrying signed `int32` control signals; electrical cables carry abstract energy allocation. Component `22` reads network satisfaction/generation/demand/surplus/storage, component `23` reads real shaft milli-RPM, and component `24` opens/closes a Power Switch through the committed-signal schedule. Machine sensors also expose Turbine/Generator states. No Automation wire carries energy. See `POWER_ARCHITECTURE.md`.
