# Platform Architecture

## Boundary

`koalasand_core` is a standard C++20 static target with no Godot headers. It currently owns fixed-width grain-size, constituent, susceptibility, hashing, and worker-policy primitives. `koalasand_native` owns GDExtension binding, Godot containers, scene-facing queries, rendering caches, and the current world façade.

This is an incremental boundary, not a claim that the whole simulation is engine-independent. Remaining migration work: chunk containers, scheduling, command application, serialization, and generation noise still use Godot types in `NativeSandWorld`.

## Phase 10 power portability

Power authority is native C++20 with fixed-width integer energy, milli-RPM and per-mille ratios. Component IDs, ordering and hashes do not depend on render frames. The current GDExtension desktop build is validated; Web still requires a matching custom Web-capable extension/export template. No compute shader or GPU simulation is required.

## Browser / WebAssembly target

The long-term renderer target is Godot Compatibility. Two viable integration paths remain:

1. Build a Web-capable `wasm32` GDExtension and use matching custom Godot Web export templates.
2. Link `koalasand_core` into a custom Web-capable Godot build if benchmarks show better compatibility or performance.

No choice is locked before native/Web measurements.

## Build probe

Run `./scripts/portability_audit.ps1`. It:

- rejects Windows-only, nondeterministic RNG, and filesystem APIs in `native/core`;
- builds and executes `koalasand_core_probe` natively;
- builds the same probe with `emcc` when Emscripten already exists.

On 2026-08-26 the native probe passed. The WASM compile was not run because `emcc` is not installed. No global SDK was installed.

## Threading

`WorkerBackend` defines `SingleThread`, `NativeThreads`, and `WebThreads`; deterministic job ordering is backend-independent. The portable probe executes the single-thread backend. Existing generation/render worker plumbing is still confined to the GDExtension façade and must migrate behind this policy before a production Web build.

Threaded browser exports require WebAssembly threads, `SharedArrayBuffer`, cross-origin isolation (`COOP`/`COEP`), and compatible hosting. Single-thread fallback remains a required correctness mode.

## Determinism

Authoritative values use fixed-width integers. Cross-platform golden hashes cover world generation, grains, processing, automation, magnetic lift, screening, and command replay. These artifacts prepare comparison across Windows, Linux, macOS, and WebAssembly; only Windows has been measured, so cross-platform determinism is not yet claimed.

## Phase 6.75 fluid-kernel implications

The experimental fluid core uses fixed-width integer state and deterministic job/merge ordering. It has no authoritative floats, Windows APIs, GPU compute, architecture-dependent reductions, or thread-scheduling inputs. Native worker counts `[1,2,4,8]` produce identical fixture hashes. `SingleThread` remains the correctness fallback; a future threaded Web build may map the same jobs to Web workers only when `SharedArrayBuffer` and cross-origin isolation are available.

`portability_audit.ps1` compiles the fluid prototype into the native core probe and would compile it with `emcc` when available. Current result: `WASM build: NOT_RUN — emcc unavailable`. Windows is measured. Linux, macOS, and Web/WASM remain architecture-compatible targets, not validated builds.

## Phase 7 production portability

Water mass, mixing, phase selection, and hashes are integer-only. Desktop defaults to at most 8 simulation workers to retain render/main-thread headroom. Emscripten without pthreads uses one worker with identical 3x3 phases. Compatibility rendering uses `R8` plus CanvasItem shader; no compute shader is required.
# Phase 8 portability

Pipe authority uses fixed-width integer POD state and a deterministic serial active set. No native thread affinity, pointer serialization, float pressure solve, or RenderingDevice dependency was added. Single-thread and future WASM execution remain valid; Godot CanvasItem `MultiMesh` presentation is non-authoritative.

## Phase 8.5 portability

Infrastructure pages use `RGBA8`/`RG8` `ImageTexture` data and CanvasItem shaders; no compute shader is required. The thermal candidate is standard C++20 fixed-width integer code using the existing executor and identical single-thread fallback. A threaded Web export still requires WebAssembly threads, `SharedArrayBuffer`, and cross-origin isolation; `emcc` is unavailable locally, so Web/WASM remains architecture-audited but unbuilt.

## Phase 8.75 portability

CommandBatch/Blueprint serialization uses stable scalar IDs and canonical arrays. `MaterialPacket`, `PermeabilityRule`, `PhysicalFieldSource` and linked endpoints are fixed-width native records with no pointer serialization. Subsurface simulation and production rings require no GPU or OS API. Route/Info batching uses GL-Compatibility CanvasItem/MultiMesh paths. Core native portability probe passes; Web/WASM remains `NOT_RUN` because `emcc` is not installed.

## Phase 9 portability

Thermodynamics, latent transitions, gas motion, Pipe heat/pressure and automation use C++20 fixed-width integers and the existing platform-neutral persistent executor. No GPU compute, OS thread API, floating-point authoritative state, or Godot physics server participates. Thermal/gas activity and scratch are derived. Future save/network formats must persist stable material IDs, amount, temperature, phase progress/direction, Pipe fluid state, Thermal Switch state and the signed rounding reservoir, then rebuild caches locally.

## Phase 9.5 portability

Gas and Pipe fast paths remain standard C++20 integer code. Single-thread output is identical to workers `[2,4,8]`; Pipe output is independent of worker selection. Persistent scheduler vectors, the immutable mass-scale lookup and render pages are derived and non-serialized. RGBA/R8/RG8 pages use GL Compatibility CanvasItem APIs with no compute requirement. Future mechanical/electrical authority is specified as fixed-width integer state with 30/15 Hz tick derivation; no solver exists. Web/WASM is architecture-audited only because `emcc` is unavailable locally.

## Phase 11 portability

V2 generation, validation, Character collision, FOV, discovery masks, and deterministic corrections are standard C++20/fixed-width data with single-thread fallback. Character motion and mode/player state are scalar schema records. Discovery pages use the existing GL Compatibility texture path and require no compute shader or OS input scan code. Spectator/Team/Light remain data boundaries only. Web export and multiplayer remain explicitly unimplemented.
