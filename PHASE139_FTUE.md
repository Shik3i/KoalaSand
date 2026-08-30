# Phase 13.9 — First-Time Player Experience

Scope: player guidance and complete UX coverage only. Phase 14 systems are not started.

## Implemented

- one central rich-tooltip layer with Codex links, disabled reasons, live state and current bindings;
- complete help records for every player-facing Component, all 27 non-empty materials and all 24 Automation components;
- reusable control-attached guided highlights and per-mode knowledge paths;
- persistent/resettable/disableable guidance with safe schema-1 migration;
- compact live Controls panel and gameplay-help settings;
- centralized bounded/collapsing INFO, SUCCESS, WARNING and ERROR toasts;
- first-use Research legend, exact locked/affordability labels and unlock notifications;
- editable example-Blueprint guidance for Screen, Sluice, Furnace and Vessel geometry;
- readable physical blocker explanations in Inspector;
- actionable empty states for saves, Blueprints and production statistics;
- explicit Factory, Character and Creative mode descriptions.

## First-session review

Character reveals movement, Jetpack, Dig, Catalog/build range, Inspector, Research, Blueprints, Planning Pause and optional Sprint/Hover in sequence. Factory contains no Character instruction and teaches camera, building, planning and observation. Creative explicitly removes progression friction while retaining full physics, and omits Research guidance.

Guidance never freezes play, places no invisible helper structure and never prescribes coordinates. A player may ignore every hint.

## Automated gate

`tests/phase139_ftue.gd` validates representative tooltip content, Component/material/Automation coverage, disabled explanations, Codex deep links, dynamic rebinding, mode sequence completion, persistence, reset, disable, legacy migration, highlight input transparency, Reduced Motion, bounded toasts, icon-only controls, viewport clamping and the capture contract.

Final gate: `316` checks. The generated audit contains `148` rows: `136` shipped player-facing surfaces pass and `12` explicitly excluded developer-only surfaces remain out of the player build. Coverage includes all `40` shipped player-facing Components (`46` Component rows including `6` developer-only entries), `27` non-empty materials and `24` Automation definitions.

The final representative smoke ran Factory Mode for `599.983 s`, completed `36,020` ticks and exited `0` at `333.6 FPS`; frame p95 was `3.333 ms`, worst frame `16.664 ms`, simulation worst `5.606 ms`. Character, Factory, Creative and Realistic Maximum all remained above the `100 FPS` target.

Captures are produced sequentially and silently by `scripts/capture_phase139.ps1`. `scripts/create_phase139_contact_sheet.ps1` creates the visual review sheet.
