# Development

## Prerequisites

- Windows PowerShell.
- Godot `4.7.1.stable.official.a13da4feb` and matching `4.7.1.stable` Windows export templates.
- CMake and a MinGW C++20 compiler available on `PATH`.
- Git for the pinned `godot-cpp` dependency.

`scripts/godot.ps1` discovers the exact executable in the sibling `Godot` directory or on `PATH`. `KOALASAND_GODOT` may point to the exact console executable. Other Godot versions are rejected.

## Clean build

```powershell
.\scripts\build_native.ps1 -Clean
```

The first build clones `godot-cpp` into ignored `.deps/godot-cpp/`, checks out commit `5ed72a0dc2517a8082598a950895c6b24e8aa282`, configures Release, builds and runs native `ctest`.

## Import and run

```powershell
.\scripts\godot.ps1 --headless --editor --path . --quit
.\scripts\godot.ps1 --path .
```

Never run the Godot executable directly for this repository.

## Canonical gates

```powershell
.\scripts\test.ps1
.\scripts\benchmark.ps1
.\scripts\benchmark.ps1 -IncludeRuntime
.\scripts\package_playtest.ps1
```

All scripts return nonzero on a failed required subprocess. `scripts/test.ps1 -Quick` is for iteration only; it is not the final gate.

## Generated state

Do not commit `.deps/`, `.godot/`, `.godot-runtime/`, `.runtime-captures/`, `native/build/`, `native/bin/`, `artifacts/`, `BUILD_MANIFEST.json` or `.safety-snapshots/`. The package script recreates its manifest and archive.

## Source boundaries

- `native/src/`: authoritative hot-path GDExtension systems.
- `native/core/`: engine-independent prototypes, portability and native probes.
- `core/`: GDScript domain, commands, persistence, UI, modes and player composition.
- `rendering/`: presentation adapters and batched rendering.
- `debug/`: composition root, developer fixtures and capture/diagnostic controls; production systems do not depend on raw developer UI.
- `tests/`: correctness, regression, adversarial and benchmark entry scripts.
- `scripts/`: reproducible build/test/benchmark/package/capture tooling.

## Change discipline

- Preserve deterministic hashes and exact mass/energy accounting.
- Keep Godot objects on the main thread.
- Validate untrusted save/Blueprint/command input before allocation or state mutation.
- Add bounds and work caps at native/GDScript boundaries.
- Report realistic and pathological performance separately.
