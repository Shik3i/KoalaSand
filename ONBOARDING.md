# Onboarding and Player Help

Phase 13.9 uses demonstrated knowledge rather than a forced tutorial script. Guidance may point at a control, but it never pauses play or requires one factory layout.

## Architecture

- `OnboardingState` owns per-save knowledge flags, the active preset path, one-shot contextual hints and schema migration.
- `GuidedHighlightLayer` outlines a live `Control` reference. It never stores screen coordinates and never intercepts input.
- `ContextTooltipLayer` is the single tooltip renderer for HUD and modal controls. It resolves current `InputMap` bindings at display time, clamps to the viewport and can deep-link to the Codex.
- `HelpCatalog` supplies representative Component, material, Automation, property, failure and control explanations. It explains physical behavior, not recipes or hidden geology.
- `ToastCenter` limits the stack to three messages and collapses repeated messages.

## Mode paths and triggers

| Mode | Knowledge flag | Demonstrated by | Highlight target |
|---|---|---|---|
| Factory | `FACTORY_INTRO` | first guidance shown | Build Catalog |
| Factory | `MOVE_CAMERA` | camera pan | current goal area |
| Factory | `OPEN_CATALOG` | opening Catalog or selecting a tool | Build Catalog |
| Factory | `BUILD_COMPONENT` | successful physical placement | Quickbar |
| Factory | `PLANNING_PAUSE` | entering Planning Pause | Plan |
| Factory | `INSPECT` | Info Mode / physical Inspector | Info tool |
| Factory | `RESEARCH` | opening or unlocking Research | Research |
| Factory | `BLUEPRINT` | opening example Blueprints | Blueprints |
| Character | `CHARACTER_INTRO` | movement input | current goal area |
| Character | `JETPACK` | Jetpack input | current goal area |
| Character | `DIG` | contextual progression step | Dig |
| Character | `OPEN_CATALOG` | opening Catalog | Build Catalog |
| Character | `BUILD_COMPONENT` | successful nearby placement | Quickbar |
| Character | `INSPECT` | Info Mode / Inspector | Info tool |
| Character | `RESEARCH` | Research interaction | Research |
| Character | `BLUEPRINT` | example library opened | Blueprints |
| Character | `PLANNING_PAUSE` | Planning Pause entered | Plan |
| Character | `SPRINT_HOVER` | final optional movement help | Controls |
| Creative | `CREATIVE_INTRO` | first guidance shown | Build Catalog |
| Creative | `OPEN_CATALOG` | Catalog opened | Build Catalog |
| Creative | `PAINT_OR_ERASE` | material-tool step | Quickbar |
| Creative | `BUILD_COMPONENT` | successful placement | Quickbar |
| Creative | `PLANNING_PAUSE` | Planning Pause entered | Plan |

All displayed action names come from `InputGlyphs`; rebinding changes the next rendered hint or tooltip without rewriting copy.

## Persistence and migration

The HUD serializes `OnboardingState` with the world session. Schema 2 stores `enabled`, `preset_id`, `completed`, and `shown_context`. A schema-1 save preserves old flags and marks the introductory movement/camera/Catalog knowledge as known, preventing an upgraded profile from replaying every basic prompt. Context failures such as out-of-range construction remain independent one-shot flags.

Settings exposes Guided Tutorial Hints, Reset Tutorial Hints, Tooltip Delay, Reduced Motion, UI Scale, Screen Shake, Hover mode and Controls. Reset clears only tutorial knowledge; world matter, Research and milestones are untouched. Disabling hints hides the current step but does not remove stored completion.

## Accessibility

Highlights use outline, arrow and text rather than color alone. Reduced Motion replaces pulsing with a static outline. Tooltip placement is tested at `1600×900`, `1920×1080`, and `2560×1440`. Icon-only controls require a tooltip specification or accessible description.
