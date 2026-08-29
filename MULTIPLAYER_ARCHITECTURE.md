# Future Multiplayer Architecture

No networking runtime exists in Phase 6.5.

## Room model

`Create Room` returns a short room code. A friend joins as `PLAYER` or `SPECTATOR` without an account requirement. One peer is the authoritative `SIMULATION HOST`.

The host validates proposed `WorldCommand` messages, assigns canonical tick/order, broadcasts that order, publishes periodic hashes, and supplies localized snapshots or chunk deltas after mismatch. Routine traffic is commands, not millions of sand cells.

## Service and transport

The central service handles only room-code lookup, minimal room metadata, peer discovery, WebRTC signaling, and optional host liveness. It never simulates room physics.

Primary transport: WebRTC DataChannels, peer to peer when NAT traversal succeeds. STUN discovers routes; TURN relays encrypted traffic when direct connectivity fails. Relay is forwarding, not authority or physics.

A future `SessionTransport` boundary exposes `connect`, `disconnect`, `send_reliable`, `send_unreliable`, `peer_joined`, and `peer_left`. Planned backends: browser WebRTC, native WebRTC, local loopback, and test/replay transport.

## Synchronization and recovery

Initial snapshot + ordered command stream + periodic authoritative hashes + localized chunk resync. No rollback netcode. Initial host disconnect may close the room; command history and snapshot ownership must not prevent later host migration.

## Spectators and trust

Simulation spectators run snapshot + command stream locally. Lightweight spectators receive periodic state/chunk deltas. Browser measurements will decide the default. Spectators have free camera and submit no authoritative commands.

Host cheating is accepted for initial cooperative private rooms. No ranked or anti-cheat system is planned.

## Fluid-state implication

The selected fixed-mass representation is compatible with the existing host-authoritative model: ordered `WorldCommand` input, fixed simulation ticks, deterministic integer updates, periodic hashes, and localized chunk resync. Worker count is not part of authoritative state. Future snapshots can include material plus optional chunk-local mass planes; routine replication remains commands rather than per-cell liquid traffic. Phase 6.75 adds no networking or fluid replication.

Phase 7 hashes include material, liquid mass, Water temperature, provenance, and mineral signature, but exclude active queues and worker ordering. Fluid transfers remain deterministic derived state; future multiplayer can exchange commands, periodic hashes, and chunk resyncs instead of every transfer.
# Phase 8 replay boundary

Construction, device changes, and local damage use canonical `WorldCommand`s (`PLACE_PIPE_LINE`, `SET_PIPE_DEVICE`, `DAMAGE_PIPE`). Future peers replay commands and derive every local transfer. Pipe state is included in periodic physical hashes; spatial pipe-region correction remains possible. No networking was implemented.

## Phase 8.5 thermal implication

Future thermal authority remains command input plus deterministic derived state. Temperature/phase energy belongs in snapshots and periodic hashes; active fronts, render pages, worker scratch, and job order do not. Heat-source enable/disable mutations require versioned commands. The candidate proves worker-count parity only on current Windows fixtures; it does not claim deployed cross-platform multiplayer parity.

## Phase 8.75 batch boundary

A future host receives one canonical `CommandBatch`, validates schema, capability, `actor_id`, sequence and explicit validation mode, then orders it at the authoritative tick. It does not receive thousands of unordered placement packets. Relative Blueprint IDs map deterministically after allocation. Spectators may inspect Info/Statistics but cannot submit build, deconstruction, configuration or Research mutations. Subsurface packets and stable linked IDs are snapshot/hash state; active queues and render batches are derived. No networking is implemented.

## Phase 9 authoritative thermal state

The earlier candidate paragraph is historical; production thermodynamics now extends the physical hash with material ID/amount, temperature, phase progress/direction, Ice/Water/Steam and molten states, Pipe Water/Steam state, Thermal Switch state and the signed rounding reservoir. `SET_MATERIAL_STATE`, `SET_PIPE_FLUID` and `SET_THERMAL_SWITCH` are canonical ordered commands. Thermal/gas active spans, worker scratch, queue order, render pages and shader time remain derived and are never network payloads. Worker `[1,2,4,8]` parity and replay `[1,8]` are locally validated; networking itself remains unimplemented.

## Phase 10 Power state

Future snapshots include shaft rotational energy, Accumulator charge, port configuration, switch state and stable entity IDs. Connected-component caches, satisfaction ratios, render records and allocation scratch are derived. Power topology mutations use WorldCommand IDs `21..23` and authoritative tick ordering; peers never transmit per-tick electron/voltage state. Automation signals remain separate commands/state. Worker-count parity and the physical hash are locally validated; networking itself remains unimplemented.

## Phase 11 player/team preparation

`ControlMode.SPECTATOR` is read-only and generation-budgeted. Discovery is keyed by stable `VisibilityOwnerID`; `VisibilityPolicy.TEAM` exists as a schema value but no sharing/network behavior is implemented. Future snapshots can combine exact `WorldIdentity`, authoritative Character fixed-point state, owner discovery bits, and last-known pages. Live visibility, render pages, FOV scratch, camera state, and InterestRegion queues remain derived/local.
