# Phase 13.5 Player-facing Inventory Audit

> **HISTORICAL AUDIT:** Preserved as Phase 13.5 evidence. Current UI and status live in `UI_UX.md`, `UX_GUIDELINES.md` and `STATUS.md`.

Authoritative CSV: `artifacts/phase135/player-facing-audit.csv`.

| Category | Records |
|---|---:|
| Components | 46 |
| Action tools | 7 |
| Example Blueprints | 6 |
| Materials | 27 |
| Overlays | 13 |
| Panels/screens | 13 |
| Milestones | 10 |
| Total | 122 |

Twelve records are intentionally not normal player-facing content: six legacy aggregate machines (`Radiant Crude Furnace`, `Vibrating Screen`, `Overbelt Magnetic Separator`, `Wash Sluice`, `Iron Pot`, `Ceramic Test Vessel`) and six overlay providers (`Material`, `Density`, `Fluid Flow`, `Pipe Pressure`, `Activity`, `Damage`). They remain marked `DEV ONLY` or `DEV ONLY · NOT SHIPPED` and are absent from the normal player overlay menu.

Normal gameplay hides raw hashes, chunk coordinates, native IDs, structure IDs, solver counters and benchmark controls. Creative is a player sandbox; diagnostics/debug presentation remains separate.
