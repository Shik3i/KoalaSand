# Visibility and Discovery

Character knowledge is not simulation allocation.

| State | Lifetime | Meaning |
|---|---|---|
| `GENERATED` | simulation/streaming | Cell/chunk exists; says nothing about player knowledge |
| `DISCOVERED` | persistent per owner | Cell was observed at least once |
| `LIVE_VISIBLE` | transient | Cell is currently observable |
| `LIGHT_LEVEL` | future boundary | Separate from discovery; no full lighting gameplay yet |

`VisibilityOwnerID = 1` is stable for current single-player. The storage/API is owner-based so future team discovery, Survey Beacons, Remote Cameras, or peers can reuse it; none of those gameplay systems exists yet.

## FOV

Native bounded 8-neighbor flood fill starts from the Character's observation cell. Radius is `72` cells. Open connected space is visible. Solid terrain stops propagation, then an inspection shell reveals at most `8` solid cells. Diagonal propagation is rejected when both orthogonal neighbors are solid, closing corner X-ray leaks. This lets the player choose a dig direction without exposing hidden caves through deep Stone.

FOV updates when the Character enters another cell and immediately after Dig; gate/terrain revision hooks remain the extension boundary. It is not recomputed every render frame. Hidden provenance, mineral signature, Gold ppm, and geology overlays are never exposed by the shell.

## Memory and rendering

Each lazily allocated discovered chunk contains:

```text
512 bytes  discovered bit mask
512 bytes  live bit mask
4096 bytes last-known material page
16 bytes   owner/coordinate metadata
= 5136 bytes/chunk in the measured native layout
```

Live masks are cleared only for the previous local live chunk set. Historic discovery does not increase FOV update complexity. Serialization persists discovered bits and last-known material, not transient live visibility.

Presentation has three non-color-only treatments:

- live: current normal material;
- stale discovered: dim/desaturated patterned last-known state;
- unknown: opaque patterned unexplored field.

Remote changes do not update stale last-known material until observed again. Factory and Creative use `OMNISCIENT` and allocate no discovery memory.

The Character Map is a last-known-world view, not a remote camera. Its legend and patterns distinguish `LIVE`, `DISCOVERED / STALE`, and `UNKNOWN`; remote changes remain stale until observed. Factory and Creative use a separate omniscient macro overview.

Current Phase-11.5 benchmark: radius-72 open FOV average/p99 `2.0789/2.3180 ms`; irregular solid-shell average/p99 `0.7695/0.8400 ms`. Updates occur on Character cell changes and Dig/terrain reveal events, not each render frame.
