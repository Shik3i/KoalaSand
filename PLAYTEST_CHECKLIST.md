# KoalaSand 0.1.0-playtest.4 — Manual Playtest Checklist

Record mode, seed, resolution, UI scale, GPU and approximate session length.

## First impression

- [ ] Main Menu and New Game explain Factory, Character and Creative.
- [ ] Current Goal is visible without dominating the playfield.
- Could you tell what the game wanted you to try first?
- Did any UI feel developer-like?

## Building

- [ ] Components come from Build Catalog/Quickbar; actions use the action toolbar.
- [ ] Placement direction, ports, invalid reason, rotation, Copy/Cut/Paste and Undo are readable.
- [ ] Copy an Example Furnace, modify it, and save it as `My Furnace`.
- Which Component icons were confusing?
- Did building physical machines feel rewarding or tedious?

## Physics

- [ ] Build and diagnose a Screen, wet Riffle, heated vessel and Steam-power chain.
- [ ] Break a pressurized Pipe and observe a local physical leak.
- When a design failed, could you understand why?
- Did anything feel like a hidden recipe rather than physics?

## Discoverability / Codex

- [ ] Search `heat`, `steam`, `screen`, `gold`, `oxygen`, `charcoal`, `pressure`, `power`.
- [ ] Follow related links and use Open in Codex from Inspector.
- Could you tell what Components did without external documentation?

## Character

- [ ] Move, Dig, Cut, Ignite, Jetpack, Hover, inspect, Pipette and build at range limits.
- [ ] Verify unknown cells/geology are not leaked by Codex, Inspector or overlays.
- Did movement or build range become annoying?

## Factory / Creative

- [ ] Factory progression uses only player UI; no developer controls.
- [ ] Creative begins ready for sandbox use and does not look like Debug.

## Save / Load

- [ ] Save, exit, continue and verify active physical state.
- [ ] Confirm delete requires intentional confirmation.
- [ ] If offered, explicitly restore a valid backup; primary corruption remains visible.

## Audio

- [ ] Start one game instance at low Windows volume before increasing Master volume.
- [ ] UI, Dig/Cut/Jetpack/Hover, Water/Steam/Fire and core machine feedback are audible.
- [ ] Planning Pause fades world loops while UI remains audible.
- Did audio become repetitive or too dense when zoomed out?

## Performance

- [ ] Test 1600×900, 1920×1080 and 2560×1440; windowed/fullscreen.
- [ ] Test UI scale 100%, 125%, 150%; no critical panel clipping.
- [ ] Test normal and Reduced Motion; record sustained FPS and any spike.

## Bug reporting

- [ ] Pause > Export Local Diagnostics; inspect ZIP before sharing.
- Include exact steps, mode, seed, expected/actual result, screenshot/video if useful.
- Confirm no automatic upload or telemetry occurred.
