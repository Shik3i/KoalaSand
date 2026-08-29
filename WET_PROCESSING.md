# Physical Wet Processing

Phase 8 adds the `Wash Sluice` (`type_id=17`) as open world geometry, not an input/recipe/output machine. Its `18x6` trough and four riffle positions share the normal cell simulation with Water and mineral grains. It owns no grain inventory, Water tank, fractional yield, or random recovery roll.

Each active tick samples only the Sluice interaction rectangle. No Water leaves material jammed. Local Water mass below `48` cannot mobilize grains. Fine/light grains move at `72`; a blocked route can hop only with at least `180`. Heavy, iron-bearing, or coarse grains require `330`. At riffles `x=4,8,12,16`, heavy grains under flow `420` settle and remain in the physical trap. Stronger flow can carry heavy grains through. These integer thresholds turn Water layout and flow into topology rather than a percentage upgrade.

Classification occurs only at a physical boundary:

- captured Raw Sand may become Heavy Concentrate in its riffle cell;
- exiting Raw Sand may become Fine Sand at the physical Sluice exit;
- one input grain remains one output/captured grain with unchanged provenance and mineral signature.

Water is never consumed by the Sluice. It remains dynamic world Water and can fall into a player-built settling basin. An upper Intake can draw from that actual basin, a Pump can return it through local Pipes, and an Outlet can release it upstream. The 5,000-tick Phase-8 loop moves mass through both boundaries while preserving the exact world-plus-pipe total.

Dry processing remains useful: Screens handle size classification without Water, Overbelt Magnets directly remove susceptible grains, and Radiant Furnaces physically heat passing material. Wet and combined routes improve heavy/Gold concentration and reduce downstream Furnace load at the cost of Reservoir, Pump, Pipe, Sluice, settling-area, and automation footprint.

Automation examples are physical feedback loops:

```text
Flow Meter -> Comparator -> Pump ENABLE
Level Sensor -> Comparator -> Valve OPEN/CLOSED
```

No contamination, chemistry, manual cleaning minigame, abstract settling machine, Steam, phase change, or hidden Water reset is present.
