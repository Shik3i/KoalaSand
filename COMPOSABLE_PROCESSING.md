# Composable Physical Processing

Player-facing processing is geometry plus single-purpose blocks. Placed example Blueprints have no assembly identity, recipe, inventory, timer or hidden yield state.

## Classification

| Buildable | Classification | Reason |
|---|---|---|
| Conveyor, Funnel, Storage Bin | `KEEP_COMPONENT` | moves/supports physical matter |
| Research Bank | `KEEP_COMPONENT` | explicit terminal Research boundary |
| Pipes, Junction, Intake, Outlet, Pump, Valve | `KEEP_COMPONENT` | one fluid action each |
| Reservoir Wall | `KEEP_COMPONENT` | passive containment geometry |
| Thermal Switch, Heat Exchanger, Heater | `KEEP_COMPONENT` | one thermal action each |
| Turbine, Shaft, Flywheel, Generator | `KEEP_COMPONENT` | one energy-domain action each |
| Power Pole, Switch, Accumulator | `KEEP_COMPONENT` | one electrical action each |
| Structural Wall, Metal Plate, Ceramic Wall, Refractory Wall | `KEEP_COMPONENT` | passive physical properties |
| Mesh, Grate, Riffle, Thermal Insulator | `KEEP_COMPONENT` | passive aperture/flow/heat geometry |
| Vibration Actuator, Electromagnet, Blower | `KEEP_COMPONENT` | one physical field/action |
| Crude/Radiant Furnace | `DEV_FIXTURE` | compatibility tests only; hidden from player catalog |
| Sieve/Vibrating Screen prefab | `DEV_FIXTURE` | replaced by Mesh + Vibration Actuator |
| Magnetic Separator prefab | `DEV_FIXTURE` | replaced by Electromagnet |
| Wash Sluice prefab | `DEV_FIXTURE` | replaced by channel walls + Water + Riffles |
| Iron Pot prefab | `DEV_FIXTURE` | replaced by Metal/Ceramic wall geometry |

## Component properties

Structure IDs `37..47` expose generic solidity, permeability, aperture, thermal conductivity, heat capacity, useful-temperature limit and magnetic behavior. Mesh surfaces only screen when separately vibrated. Riffles only separate with nearby real Water. Electromagnets only route existing magnetic constituent mass. Refractory geometry exposes hot sediment to thermal fractionation; it is not a furnace recipe.

## Example Blueprint library

- Basic Screen
- Basic Wet Sluice
- Basic Charcoal Chamber
- Basic Furnace
- Basic Metal Vessel
- Basic Steam Boiler

Every definition contains ordinary structure entries only. Runtime ledger/carry is excluded from Blueprint serialization. Deleting a wall changes containment/oxygen/heat retention; replacing Metal with Ceramic changes conductivity; removing Riffles removes wet capture; closing an air opening changes oxidizer access. After placement there is no “Basic Furnace” or “Pot” identity.
