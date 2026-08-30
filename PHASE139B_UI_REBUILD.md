# Phase 13.9B responsive UI rebuild

Phase 13.9B replaces the screenshot-dependent HUD composition with one container-driven player layout. It does not add gameplay or begin Phase 14.

## Layer contract

`UILayoutPolicy` defines the player-facing order:

1. world and batched world overlays;
2. persistent HUD (`100`);
3. contextual panels (`300`);
4. workspace/modal panels (`500`);
5. guided highlights (`900`);
6. tooltips (`1000`).

The top rail and coherent bottom dock are persistent safe regions. The space between them is the workspace rectangle used by Research, Codex, Map, Blueprints and Experiments. Opening a workspace closes the previous workspace and any internal HUD modal. Inspector remains contextual.

## Responsive structure

- The top rail groups selected mode/status, named Research materials, primary Research/Plan actions, secondary More/View menus, context guidance and a compact expandable Goal.
- One bottom `PanelContainer` owns the contextual world-tool strip, primary ten-slot Quickbar with subordinate paging, and secondary Catalog/Blueprint actions. At 1600×900/150% its internal `HFlowContainer` wraps groups inside the same dock instead of leaving the viewport.
- Catalog cards use `CatalogCard`: a fixed icon control, independent name region, independent secondary/lock region, optional `NEW` badge and whole-card hover/selection state. Long names ellipsize; their tooltip retains the full name.
- Catalog columns are calculated from actual available width and UI scale: two to four columns across the supported matrix. Scrolling is preferred over reducing type or card padding.
- Player-facing caption text is at least 12 px at 100% scale. Theme scaling supplies 15 px at 125% and 18 px at 150%.

## Placement and animation

Tooltips start from right, left, below and above orientations. Each orientation is clamped and adjusted against the target, viewport, top/bottom safe regions and modal bounds. Scoring makes target and persistent-HUD intersections hard failures; Catalog tooltips prefer the free workspace alongside the Catalog. Actual post-theme minimum size is used before final placement.

Highlights retain live `Control` references, queue competing guidance, and use the same safe-region placement for their message label. Layout animations change opacity only; they cannot overwrite container positions or minimum sizes.

## Permanent regression gate

`tests/phase139b_layout.gd` recreates the reported failure class with:

- all 67 Catalog entries;
- a full ten-slot Quickbar;
- action and utility groups;
- visible top HUD and Goal;
- active tooltip and modal;
- 1.6× pseudo-localized names.

It runs 1600×900, 1920×1080 and 2560×1440 at 100%, 125% and 150%. It checks screen bounds, top/bottom/workspace separation, bottom-group separation, card icon/name/category/badge rectangles, tooltip target/safe-region/modal avoidance, modal replacement and highlight queuing.

## Visual verification

`scripts/capture_phase139b.ps1` produces exactly 30 required captures, sequentially through `scripts/godot.ps1 -MuteAudio`. `scripts/create_phase139b_contact_sheets.ps1` produces the UI-all, FTUE and responsive review sheets. Generated evidence remains ignored under `artifacts/phase139b/`.

The pre-change tracked snapshot is `.safety-snapshots/pre-final-ui-rebuild.zip`: 435 entries, 1,919,427 bytes, SHA-256 `AD51FE24B829563646ED108DEC0AE9E92C9B8CFD461B452A02D171C80E60B76B`.

## Final verification

- `28/28` correctness scripts pass in `37.171 s`; the dedicated responsive audit passes `237` checks.
- All nine resolution/scale combinations report zero top overflow, bottom overflow and Catalog-card failures.
- The two screenshot-driven passes produced 30 final captures and three reviewed contact sheets with no visible text, icon, control or tooltip collision.
- Character, Factory, Creative and Realistic Maximum render at `308.6`, `477.0`, `414.5` and `179.1 FPS`; all exceed the owner-playtest target.
- Catalog, Research, Codex, Inspector, Map and Production Overlay render at `238.0`, `259.8`, `515.1`, `550.4`, `320.8` and `271.7 FPS`. Measured UI update cost is `0.0086–0.0129 ms/frame`.
- The representative Factory stability run exits `0` after `600.006 s`, `36,020` ticks and `282,380` frames at `470.6 FPS`.
- Clean native Release build, CTest, Godot `4.7.1` import, export and clean-profile owner smoke pass.

The complete historical performance matrix still reports two source-built synthetic stress failures outside the player UI path: Phase 3's 50k-active Conveyor ceiling measures `17.096 ms/tick` against `16.67 ms`, and Phase 7's one-million-active Sand ceiling measures `44.0126 ms/tick` at eight workers. The representative gameplay fixtures and every measured UI surface remain above the required `100 FPS`; the stress failures are retained as disclosed optimization debt.
