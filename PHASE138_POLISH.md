# Phase 13.8 — Final Player-Experience Polish

Phase 13.8 is the final player-facing pass before the owner's first serious playtest. It does not begin Phase 14 or add a new simulation branch.

## Interaction policy

- One coherent industrial slate, brass and teal theme across menus, HUD, modal panels and diagnostics.
- Modal panels use a `120–180 ms` quadratic entrance and an `80 ms` exit. Reduced Motion makes both transitions immediate.
- `Esc` closes the top visible player surface before it cancels a tool or opens Pause.
- Map, Codex, Blueprint Library and Experiments expose visible close actions and correctly release their modal input lock.
- UI scale and Reduced Motion preferences apply to all themed HUD descendants after settings are accepted or a world is restored.

## Audio safety

- Procedural sound is signed 16-bit PCM at `32 kHz`.
- Loops are periodic, seamless and free of raw white-noise beds.
- UI, Character, Environment, Machines and Music retain fixed safety headroom below the player's volume control.
- Loop gain and pitch change smoothly; new loops fade in from `-60 dB` and inactive loops fade out.
- Every automated test, benchmark and capture routes through `scripts/godot.ps1`; capture and benchmark modes automatically use the `Dummy` driver. `-MuteAudio` is available for every other automated run.

## Native stability

Granular worker jobs no longer mutate the shared reactive-cell hash set. Workers report changed cells; the main thread commits those notifications after the parallel barrier. `tests/native_correctness.gd` covers an eight-worker, multi-region settle/removal fixture that previously reproduced heap corruption.

## Visual review workflow

`scripts/capture_phase138.ps1 -Pass first` creates the first visual pass. `scripts/create_phase138_contact_sheets.ps1 -Pass first` groups UI, gameplay and world/physics surfaces for review. After corrections, repeat both commands with `-Pass final`. Captures are sequential, never concurrent, and explicitly silent.
