# Rendering Scalability Architecture

## Phase 8.5 decision

Dense infrastructure is rendered as native-built `64x64` cell pages. Sparse Conveyors and individual machines remain `MultiMeshInstance2D` batches. Pipes always use pages; a Conveyor page switches to the page path at `512` infrastructure cells. This hybrid keeps sparse construction cheap while bounding dense visible work by pages rather than instances.

The renderer is presentation-only. Authoritative material, Pipe, health, fill, connection, and flow state remain native simulation data.

## Why the Phase-8 path failed

The old 20k-Pipe stress drew every Pipe through a visible-record query and a GDScript-built MultiMesh. The legacy double-draw profile additionally left the same cells in the general structure MultiMesh. Controlled 20k profiles:

| Path | FPS | Frame avg | p95 | CPU prepare | Upload |
|---|---:|---:|---:|---:|---:|
| Legacy Pipe MultiMesh only | 127.4 | 7.762 ms | 25.300 ms | 3.5373 ms | 0.2023 ms |
| Legacy double draw | 84.0 | 11.844 ms | 49.906 ms | 4.2507 ms | 0.2331 ms |

The bottleneck was per-revision visible-record collection, per-instance GDScript transform/color/custom-data writes, and redundant draw preparation. One global MultiMesh also cannot cull individual instances; [Godot recommends spatially splitting MultiMeshes](https://docs.godotengine.org/en/latest/tutorials/performance/using_multimesh.html) when only local regions are visible.

## Page contract

`NativeSandWorld.get_infrastructure_render_page(chunk_coordinate)` returns a cropped occupied rectangle:

- `topology`: `RGBA8`; structure type, cardinal connection mask, orientation, occupancy.
- `dynamic`: `RGBA8`; fill, signed flow, flags, health.
- count, Pipe count, dimensions, and world-cell position.

`StructureRenderer` owns one `Sprite2D` and two textures per visible nonempty page. Byte caches compare topology and dynamic payloads independently. Unchanged textures are not uploaded. A visibility change hides retained pages instead of destroying them. Flow/tread animation uses shader `TIME`; it causes no per-frame CPU state rebuild.

The shader uses nearest sampling, per-cell Pipe/connectivity geometry, fill/flow/health coloring, and derivative-based far LOD. Page coordinates follow native `64x64` chunk coordinates. The Phase-8.5 benchmark fixes the local streaming window at one stable `6x6` page region; oscillating visibility bounds are forbidden because they trigger avoidable rebuilds.

## Final 1920x1080 matrix

Godot `4.7.1`, GL Compatibility, NVIDIA GeForce RTX 4080 SUPER, `120` benchmark ticks:

| Fixture | Total | Visible | Pages | FPS | Avg | p95 | p99 | Worst |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Pipes | 2,000 | 2,000 | 4 | 719.2 | 1.386 ms | 1.515 ms | 1.515 ms | 1.799 ms |
| Pipes | 20,000 | 20,000 | 8 | 559.8 | 1.782 ms | 2.381 ms | 2.778 ms | 6.656 ms |
| Pipes | 50,000 | 50,000 | 16 | 407.4 | 2.446 ms | 2.778 ms | 3.918 ms | 11.713 ms |
| Conveyors | 20,000 | 20,000 | 8 | 711.3 | 1.405 ms | 1.515 ms | 1.667 ms | 2.081 ms |
| Conveyors | 50,000 | 50,000 | 16 | 633.0 | 1.579 ms | 1.667 ms | 1.852 ms | 3.344 ms |
| Combined | 40,000 | 40,000 | 16 | 541.5 | 1.845 ms | 2.381 ms | 2.381 ms | 2.778 ms |
| Culling | 100,000 | 2,000 | 4 | 745.2 | 1.342 ms | 1.389 ms | 1.389 ms | 2.148 ms |

The 100k culling fixture places 98k Pipes outside the visible region. Visible work remains at 2k/4 pages. The 20k gate improves from the Phase-8 `92.5 FPS` baseline to `559.8 FPS`.

## Temperature visualization

`NativeSandWorld.get_temperature_render_page(Rect2i)` emits one visible `RG8` page containing little-endian authoritative `uint16` temperature. `MapOverlayRenderer` uploads it only when bytes change; a CanvasItem shader performs the color mapping. Dense-physical comparison: overlay off `406.0 FPS`; overlay on `361.3 FPS`; visible update `0.217 ms`, upload `0.065 ms`, `851,968` bytes, CPU draw `0.000 ms`.

## Memory and platform

Persistent authoritative memory is unchanged. Render-page textures are optional GPU/presentation caches and may be discarded/recreated from native state. Worst visible CPU payload is `8 bytes/cell` for topology plus dynamic state; temperature adds `2 bytes/cell` only while its overlay is active. The path uses `ImageTexture`, CanvasItem shaders, and GL Compatibility; no compute shader, GPU authority, or RenderingDevice dependency is required.

Captures: `artifacts/phase85/phase85-dense-pages.png`, `artifacts/phase85/phase85-megafactory.png`, and `artifacts/phase85/phase85-temperature-overlay.png`.

## Phase 8.75 route, info and Overview LOD

Subsurface routes use one `MultiMesh`; depth pattern and endpoint marks execute in a CanvasItem shader. Close views add Roman numerals, while dense/far views avoid one CPU line or label per lane. Six hundred crossing routes measured `771.9 FPS` and `0.0010 ms` CPU overlay draw.

Info Mode uses one badge `MultiMesh`; close views may draw compact state numbers only below a bounded visible count. Overview automatically hides subpixel machine/material detail and retains paged topology. The 100k-Conveyor Overview fixture measured `653.5 FPS`; it does not change simulation state or cadence.

## Phase 9 thermal presentation

Ice, Steam, molten Glass and molten Iron extend the native material palette. Steam alpha is derived from finite local amount; hot molten phases use high-readability emissive color without becoming light/simulation sources. Material pages remain one cached RGBA value per cell. Temperature visualization uploads cropped `RG8` visible pages (`2 bytes/pixel`). Dense infrastructure retains two cropped RGBA8 pages (`8 bytes/visible pixel/page pair`). Phase state, temperature and Pipe content come from authoritative native snapshots; animation time and color ramps never enter hashes.

## Phase 9.5 visible material batching

Native dirty regions still rebuild in the persistent render pool, but GDExtension now crosses once per cropped visible RGBA page rather than once per dirty chunk. One `Sprite2D` replaces the native material chunk-sprite set; the old path remains a compatibility fallback. Neighbor palette sampling reads chunk-local cells directly and hashes only boundary neighbors. Water remains a separate `R8` amount shader; unchanged pages are skipped. Temperature pages update on the authoritative 30 Hz thermal cadence, not every 60 Hz world tick.

Measured at 1080p GL Compatibility: Thermal Factory `229.3 FPS`; Temperature Overlay `188.9 FPS`; stable full-view Steam `305.3 FPS` with zero steady upload; historical Megafactory `490.8 FPS`.

## Phase 10 power presentation

POWER provider ID `13` now consumes native `get_visible_power_elements()` records. One MultiMesh batches poles, edges and mechanical members; network pattern and real milli-RPM drive shared shader presentation. Turbine/Generator machine records carry real mechanical speed into the existing machine MultiMesh. Normal view hides cable clutter. POWER mode rebuilds only on native power/mechanical revision and creates no per-segment Nodes.

## Phase 11 discovery presentation

`VisibilityRenderer` uploads one cropped owner-filtered RGBA page only when the visibility revision or visible chunk rectangle changes. Live cells remain transparent; stale discovered cells show patterned dim last-known material; unknown cells show a separate opaque pattern. The native page never contains provenance, mineral signature, Gold concentration, or hidden geology. Factory/Creative bypass this layer through `OMNISCIENT`.

## Phase 11.5 player presentation

The shared authored theme and container-based HUD remain presentation-only. World Map pages are generated from either owner-filtered discovery state or safe macro preview state; no map shader receives hidden Character data. Modal panels, contextual Inspector, onboarding, warning badges, Blueprint ghosts, Info Mode badges, overlays, and Overview retain existing batched/native page paths. Phase-11.5 UI refresh measured at most `0.004658 ms` across normal/Catalog/Statistics samples; Map open measured `4.6730 ms`.
