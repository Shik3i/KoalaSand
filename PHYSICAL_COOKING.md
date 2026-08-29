# Physical Cooking

Phase 12 adds a minimal cooking proof, not survival gameplay. There is no hunger, consumption effect, inventory stack or recipe queue.

## Iron Pot

Structure `35`, Iron Pot, is a 9×6 open vessel. Its sides and bottom are solid structure geometry; the 7×5 cavity contains ordinary world cells. Water can enter, settle, overflow and escape as Steam. Removing a non-empty Pot is rejected, so Water/Food cannot be silently destroyed. Blueprints copy only the Pot structure.

The generic thermal-vessel bridge transfers energy between the external cells below the vessel and its cavity through material coefficients:

| Vessel | Conductivity | Specific heat | Transfer coefficient |
|---|---:|---:|---:|
| Iron Pot | 192 | 56 | 16 |
| Ceramic test fixture | 24 | 80 | 2 |

The Ceramic fixture exists only to prove conductivity behavior. With identical geometry, source and Water, two ticks produced Iron Water `1492` versus Ceramic Water `1231` quarter-kelvin.

Boiling is not Pot code. Once real Water receives sufficient enthalpy, the existing Water→Steam phase transition runs; Steam then rises through the open top using the existing gas solver. Overflow and boil-dry behavior emerge from cell capacity and phase conservation.

## Food reaction

Raw Mushroom (`25`), Cooked Mushroom (`26`) and Burnt Food (`27`) are finite physical granular materials. A reactive Food cell accumulates deterministic `uint16 ReactionProgress` from temperature exposure:

- Raw Food at/above `1372` and below `1972` quarter-kelvin advances toward Cooked Food;
- Raw/Cooked Food at/above `1972` advances toward Burnt Food;
- below activation temperature, no hidden timer advances.

Immersion works because hot Water transfers actual heat to the Food cell. Direct heat or a boiled-dry Pot can exceed the burn threshold. The reaction is geometry-independent and uses the same optional state as Wood pyrolysis, so the Pot never owns an ingredient list or recipe timer.

## Scope

Implemented: physical ingredient, Water bath, conduction comparison, boiling/Steam escape, Cooked and Burnt states, conservation/removal tests, aggregated statistics. Deferred: eating, hunger, buffs, health, farming, recipes, cookware inventories and save/load.
