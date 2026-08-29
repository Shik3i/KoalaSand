# KoalaSand Design System

Runtime source: `rendering/koalasand_theme.gd`.

## Direction

Industrial slate, brass selection, restrained teal information, warm physical danger. The world remains brighter and more detailed than its frame. Panels are translucent, compact and tactile; no stock Godot surfaces are used on primary player screens.

## Canonical tokens

- Surfaces: world ink, HUD, elevated and modal panels.
- Semantics: accent, warning, danger, success, information, selection, unknown, stale and live.
- Spacing: `4 / 8 / 12 / 16 / 24 px` before UI scaling.
- Radius: `4 / 7 / 10 px`.
- Icons: `18 / 28 / 42 px`.
- Motion: `80 / 120 / 180 ms`, quadratic ease-out.
- Type: Display `38`, screen title `25`, section `17`, body/numeric `14`, secondary `13`, caption `11` before scaling.

## Icon language

Repository-owned procedural line art. One consistent amber stroke, dark field and functional internal geometry. Component silhouettes combine shape, pattern and direction: perforations for Mesh, ridges for Riffle, impeller for Pump, gate for Valve, coil for Heater, field/poles for Magnet, brick/tile/rivet treatments for wall families.

## Modes

- Factory: cool information accent, strategic HUD.
- Character: green mobility accent, local discovery and compact mobility state.
- Creative: amber sandbox accent, unlocked construction tools.

The layout, typography, surfaces and icon grammar remain shared.

## Accessibility

Theme generation supports `0.75–2.0` UI scaling. Important state never relies only on hue: text, silhouette, pattern, line weight and opacity reinforce it. Reduced Motion bypasses presentation tweens and reduces nonessential world feedback.
