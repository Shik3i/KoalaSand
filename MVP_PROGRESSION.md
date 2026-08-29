# MVP Progression and Vertical Slice

## Shared arc

```text
generated mixed Raw Sand
→ gravity/conveyance and Research deposit
→ Mesh + Vibration screening
→ Water + Riffle density concentration
→ Electromagnet ferrous concentration
→ Refractory geometry + real heat
→ physical Glass / Iron / Gold
→ automation
→ Water/Steam infrastructure
→ Turbine → Shaft → Generator → electrical loads
→ POWERED FACTORY ESTABLISHED
```

Research unlocks components; placement remains free. Factory and Character share costs, physics and milestones. Character adds discovery, immediate Basic Jetpack, Sprint and Hover. Creative removes progression friction without changing simulation rules.

## Deterministic model checkpoints

`evaluate_mvp_playthrough(minutes, profile)` reports exact modeled quantities for `15`, `30`, `60` and `90` minutes: unlock count/timing, Sand processed, Water moved, Wood/Coal consumed, Glass/Iron/Gold, tailings, travel and idle fractions, build/dig actions, blockage, power shortages and first automation/Steam/electricity. The model uses integer throughput and the same constituent profile contract; it does not grant random yield.

Balance rule: improvement comes from geometry, parallel flow, reduced blockage, water handling, heat control and power satisfaction—not long passive waits.

## Milestones

Milestones latch only from authoritative simulation evidence and persist in saves:

1. First Material Flow
2. First Research Deposit
3. Separate Your First Concentrate
4. Recover First Iron
5. Recover First Gold
6. Use Water Processing
7. Automate a Process
8. Produce Steam
9. Generate Electricity
10. Powered Factory Established

The endpoint requires actual electrical production and consumption, processing throughput and Research completion. Play continues afterward.
