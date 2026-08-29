# MVP Recovery and Softlock Audit

Normal recovery must use ordinary construction, Dig, controls, physical flow, or save recovery. Developer tools are never part of an MVP recovery path.

| Failure state | Observable safe state | Normal recovery | Automated evidence |
|---|---|---|---|
| Research Bank output blocked | input remains physical; Bank reports `REJECT_BLOCKED` | clear its physical output area | `tests/phase5_correctness.gd` |
| all electrical power lost | loads become unsatisfied; passive physics and unpowered baseline components remain valid | restore Steam/Shaft/Generator/Pole continuity or shed loads | `tests/phase10_correctness.gd` |
| Pump stopped | Pipe/world Water remains accounted; no hidden drain | re-enable Pump, restore power/control, or open an alternate gravity path | `tests/phase8_correctness.gd` |
| Steam exhaust blocked | finite pressure rises; local Pipe damage/rupture emits the same Steam into world cells | vent, repair the local segment, reduce heat, or add exhaust capacity | `tests/phase95_correctness.gd` |
| Water flood | Water remains normal world matter behind/removing geometry | wall, pump, open drainage, or Dig a gravity outlet | `tests/phase8_correctness.gd` |
| fire | fuel, oxidizer and products remain physical | apply Water, remove fuel, isolate oxygen, or allow burnout | `tests/phase12_correctness.gd` |
| oxygen-starved furnace | exposed fuel/material is retained; low oxygen favors Charcoal | open geometry or add a Blower | `tests/phase12_correctness.gd`, `tests/phase13_correctness.gd` |
| separator output blocked | completed quanta stay in bounded pending carry; processing stops before loss | clear output and resume | `tests/phase12_correctness.gd`, `tests/phase13_correctness.gd` |
| fractional Gold retained during removal | removal returns `CONTENTS_PRESENT`; ledger remains authoritative | drain/reprocess before removal | `tests/phase13_correctness.gd` |
| invalid/blocked Blueprint | atomic `CommandBatch` rejects the placement without a partial assembly | change position/geometry or cancel | `tests/phase875_correctness.gd` |
| Character touched by moving granular matter | loose matter is not an enclosing solid collision; solid Structures remain explicit collision | immediate Basic Jetpack, Dig, or remove the Structure | `tests/phase11_correctness.gd` |
| Character trapped in cave | Basic Jetpack is unlocked at tick zero; local physical Dig is available | Jetpack and Dig a route | `tests/phase11_correctness.gd` |
| save during active fire | reaction cells, heat, oxidizer, carry and products restore | load/continue normally | `tests/phase13_persistence.gd` |
| save during Tree fall | stable-ID Q10/Q16 cluster state restores | load/continue normally | `tests/phase13_persistence.gd` |

Corrupt-primary recovery is automatic and explicit: checksum failure loads the validated `.bak`. Deletion requires confirmation. Snapshot schema migration is versioned. Active Steam/Shaft/electrical state, Research, fire, Tree fall and fractional carry are covered by the production persistence suite.
