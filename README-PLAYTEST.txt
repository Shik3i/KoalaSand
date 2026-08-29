KOALASAND 0.1.0-playtest.2

KoalaSand is a deterministic physical factory sandbox. Matter, heat, fluids, gases,
fire, pressure, mechanical power and electricity interact in one editable world.
Machines are built from ordinary Components; Example Blueprints have no hidden
recipe identity.

STATUS
Owner first-play build. Saves and simulation are deterministic; balance,
presentation and compatibility still need hands-on feedback.

RECOMMENDED MODE
Factory for the clearest first session. Character adds local discovery, movement,
Jetpack, Hover and physical build-range constraints. Creative is a player sandbox,
not Developer Debug.

BASIC CONTROLS
All controls come from the in-game InputMap and are shown in tooltips/HUD.
Use the Build Catalog and Quickbar for Components. Permanent actions live in the
action toolbar. Open the Physics Codex in-game for principles, not recipes.
Planning Pause freezes authoritative physics while camera, Inspector, Codex,
construction, Blueprints, Research and map remain available.

SAVES
Stored in the standard Godot per-user application-data directory, outside this
portable package. Removing the package does not remove saves. The Save Browser
shows schema/version and offers explicit atomic-backup recovery.

DIAGNOSTICS
Use Pause > EXPORT LOCAL DIAGNOSTICS or the Save Browser. A local
KoalaSand-diagnostics-YYYYMMDD-HHMMSS.zip is created. Nothing is uploaded;
KoalaSand contains no analytics or telemetry.

KNOWN LIMITATIONS
- Windows x64 only for this candidate.
- No installer or code signing.
- Audio is original and procedural; no soundtrack yet.
- Synthetic 100k-cell fire remains a stress case, not representative gameplay.
- Some GPU/driver combinations may show a harmless Windows root-certificate-store
  diagnostic in the current isolated test environment; gameplay uses no network.

BUG REPORTS
Include reproduction steps, mode, seed, what you expected, what happened, and an
explicitly exported diagnostics ZIP. Never attach unrelated personal files.
