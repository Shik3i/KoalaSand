# Subsurface Logistics

Phase 8.75 implements three physical finite-capacity hidden transport depths:

| Depth | Structures | Visual identity | Pattern |
|---|---|---|---|
| I | Entrance/Exit `18/19` | Amber, `I` | solid |
| II | Entrance/Exit `20/21` | Cyan, `II` | dashed |
| III | Entrance/Exit `22/23` | Violet, `III` | dotted/triple |

Color is never the only distinction. Normal view shows physical mouths and depth markers. `UNDERGROUND_LOGISTICS` shows batched route geometry and close-zoom Roman numerals.

## Authoritative representation

`LinkedTransportEndpoint` is a stable 40-byte endpoint record. Its stable kind enum reserves `SUBSURFACE_CHANNEL` and future `MATTER_PORTAL`; only Subsurface is executable. Pairing uses a stable `linked_transport_id`, never nearest-endpoint lookup.

Each aligned run is 2..65 cells between mouths and owns 1..64 hidden positions. Horizontal and vertical runs are valid. Every hidden position holds at most one `MaterialPacket`:

```text
uint16 material
uint16 temperature
uint16 provenance
uint16 mineral_signature
```

The packet is exactly 8 bytes. Existing authoritative grain traits are encoded by material/provenance/signature and remain unchanged. Packet backing for 100,032 lane cells is 800,256 bytes.

## Movement and blockage

- Directional Entrance to Exit; one hidden cell per authoritative tick.
- Entrance reads only its physical mouth and refuses input while lane position 0 is occupied.
- Exit writes only its physical mouth. An occupied mouth retains the final packet.
- Backpressure propagates toward the Entrance. Full means no compression, deletion or infinite buffer.
- Empty/stable runs sleep. The scheduler visits active run/range state, not all allocated lane cells.
- Same-depth hidden overlap is invalid. Different depths cross independently without mixing.
- Occupied removal is rejected with `MUST_DRAIN`; empty removal succeeds.
- Save/load stores stable IDs, depth, endpoints, direction and packet array. Active queues/render caches rebuild as derived state.
- Subsurface state participates in logistics and authoritative physical hashes.

## Progression

`logistics.subsurface_1`, `logistics.subsurface_2`, and `logistics.subsurface_3` unlock depths I/II/III in sequence. Depth I is early logistics QoL; costs do not require excessive Gold. Creative capability unlocks all three. Blueprints, Undo, Pipette, Info Mode and Statistics are never Research-locked.

## Measured scale

Native Release, 1,563 runs:

- 100,032 empty lane cells: `0` visited, median `0.0110 ms`, p95 `0.4270 ms`.
- 50,000 packets: median `1.635 ms`, p95 `2.022 ms`, worst `2.513 ms` over 120 ticks; final sampled tick `1,560` runs visited, `10` moves, `1,495` blocked after the deliberately saturated workload backed up.
- Dense overlay: 600 crossing routes, `771.9 FPS`, `1.294/1.389/1.389/1.391 ms` frame average/p95/p99/worst, `0.0010 ms` CPU overlay draw. Routes are one `MultiMesh`; line motifs execute in the shader.

## Future Matter Portal contract

A future portal may ignore geometric distance but must use the same complete packet, finite throughput, finite buffering, stable pair/channel identity and backpressure. It may never become unrestricted global inventory or duplicate resources. No Matter Portal gameplay exists in Phase 8.75.
