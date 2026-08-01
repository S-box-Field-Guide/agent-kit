---
title: Networking methods — spec replication + host-authority patterns
slug: networking-methods
date: "2026-07-13"
updated: "2026-07-15T00:24:00-04:00"
lanes:
  - writing-gameplay
tags:
  - networking
  - multiplayer
  - host-authority
  - determinism
summary: >-
  Two proven architectures on top of the engine networking primitives:
  replicate the generator spec (not the geometry) for deterministic worlds, and
  retrofit local-only gameplay systems to host-authority without breaking
  single-player.
verifiedOn: "26.07.15a"
sourceRev: methods/networking-methods.md
relatedFixes:
  - owner-simulated-networking
  - saveload-without-drift
  - runtime-world-building-helpers
unverified: false
---

Two proven architectures on top of the engine primitives. Official docs cover
`[Sync]`, `SyncFlags.FromHost`, `[Rpc.Host|Owner|Broadcast]`, `NetworkSpawn`,
and `Networking.*` well — this guide does not re-explain them. What they don't
cover is:

- **Part A** — deterministic multiplayer: replicate the *spec*, not the geometry
  (code-complete + suite-proven; the live cross-machine two-peer join was proven
  end-to-end — see the [P2P peer-hosted servers](/guides/p2p-peer-hosted-servers) guide).
- **Part B** — host-authority retrofit: making a dozen local-only gameplay
  systems host-authoritative without breaking single-player.

Baseline owner-simulated pattern is in
[owner-simulated-networking](owner-simulated-networking).

---

# Part A — replicate the spec, not the geometry

## The idea

If world generation is **fully deterministic** (same spec → byte-identical
world), the host never streams terrain. It replicates the tiny generator input —
a few dozen numbers — and **every client regenerates the identical world
locally**. Bandwidth for the world is constant and tiny regardless of world size.

Prerequisites (they ARE the networking contract, not hygiene):

- No `System.Random` in the gen path; hash noise only; pure functions of
  (seed, x, y).
- One unit conversion at emission; no platform/float-order-sensitive topology
  decisions.
- **Spec fields are APPEND-ONLY** — old and new peers must deserialize each
  other's specs (unknown fields skip, missing fields default).
- A **process-independent content hash** over the generated data — this turns
  "deterministic" from a hope into a checkable gate.

## The decisions

**D1 — replicate the spec as its canonical JSON STRING**, not a networked
record: `[Sync(SyncFlags.FromHost)] public string NetSpecJson` on a scene-owned
session component. A string is the most boring thing `[Sync]` handles; the JSON
round-trip is already battle-tested by save/load; append-only field law makes it
version-tolerant. Serialize with the engine `Json.Serialize` (invariant culture).

**D2 — client regen = observed property change; host regen = direct call.**
Clients watch `NetSpecJson` and on change: validate → regenerate → report hash.
The host NEVER round-trips through its own sync property (self-echo loop;
single-player would depend on net plumbing) — it regenerates directly and
publishes only after a successful local regen.

**D3 — the hash handshake (desync becomes a loud, named failure).** After a
client's regen completes it sends ONE `[Rpc.Host] ReportWorldHash(...)`. Host
compares to its own: match → client marked world-ready; mismatch → log
`DESYNC` with the first differing sub-hash and kick the client to menu —
**never let a desynced client walk a wrong world**. No retry logic: a desync is
a bug to fix, not a condition to paper over.

**D4/D5 — an explicit mode state machine + per-mode UI lockdown.**
`Authoring → Hosting / Joining → Joined` as ONE enum; every UI element declares
which modes it exists in. In a frozen-world MVP the HOST loses editing too — a
host edit would silently desync every client's world. Enforce at the UI **and**
in the mutation entry points.

**D6/D7 — characters ride the standard owner-simulated pattern**: host
`OnActive(Connection)` → clone prefab at a validated spawn →
`NetworkSpawn(connection)`; each player simulates their own character; cameras
strictly local. No server-authoritative movement for a friends-co-op MVP — that's
a deliberate trust-model decision.

## Scope cuts that make it small

- **Frozen-world MVP**: the world locks at launch — no live edit replication.
- **Late join is cheap by construction**: spec + regen + handshake (and,
  post-MVP, replay of the edit log — the [delta-log save](/guides/delta-log-save) format
  is deliberately the same format the wire protocol needs).

## Invite codes / lobby discovery

Verified on engine 26.07.08e, corrected against a live cross-peer test:

- **The lobby must be VISIBLE (`Hidden=false, Privacy=Public`).** A `Hidden=true`
  lobby is structurally excluded from every ordinary `QueryLobbies` — the engine
  appends `q.WithKeyValue("hdn","0")` unless you pass a truthy `"hidden"` filter,
  so a hidden-lobby + metadata-code lookup can never find the host (confirmed by a
  live cross-peer failure). **This corrects earlier `Hidden=true` guidance.**
- **Don't put the plaintext code in metadata** (a visible lobby's `SetData` is
  enumerable). Publish only a **hash** of the code, filter the query by that hash,
  and **verify the real code host-side on the wire** before releasing the joiner.
- `Networking.QueryLobbies(Dictionary filters)` → `LobbyInformation` rows;
  stamp a protocol-version key **and** a separate publish-stamp in lobby data and
  refuse mismatches client-side BEFORE connecting — a routine content republish
  leaves the protocol version identical yet makes peers different builds.
- **A host cannot discover its own lobby** — self-query exclusion holds even for
  visible lobbies. An id-encoded-code fallback is structurally dead; only a
  genuine second peer can verify lobby discoverability.

## Verification ladder

1. Determinism suite on one machine: same spec regenerated N× byte-identical
   (see [/guides/agent-test-harness](/guides/agent-test-harness)).
2. **`-joinlocal` two-peer on one machine** — no publish, no second Steam
   account. Exchange the world hash at join and refuse on mismatch — dev-host
   streaming does NOT send loose data files, so a code-built world can silently
   diverge.
3. A real second peer/account (the only test that settles Steam-backend
   behaviors).

---

# Part B — host-authority patterns: retrofitting local systems for co-op

The situation this solves: a game built single-player-first has a dozen mutable
systems (gates, pickups, NPC AI, progress, day/night, scoreboard, win latch)
that every client would simulate independently — double-consumes, contradictory
NPC targets, multiple winners.

## Load-bearing engine facts

1. **`GameObject.NetworkMode` defaults to `Snapshot`.** **CORRECTED 2026-07-31
   (doc + engine-source verified, engine build 26.07.22):** the original claim
   here, that `[Sync]` / `[Sync(SyncFlags.FromHost)]` fields on `Snapshot`-mode
   objects converge with no `NetworkSpawn`, is wrong. The official
   `sync-properties.md` doc: *"`[Sync]` only works when the GameObject has the
   `NetworkMode.Object` mode. Properties on `NetworkMode.Snapshot` objects are
   never synced after the initial snapshot to anyone, even if marked with
   `[Sync]`."* Engine source confirms the mechanism: the `NetworkObject` that
   carries the sync table is only constructed inside `NetworkSpawn(...)` or on
   receipt of a create message, so a `Snapshot`-mode object never gets one and
   `[Sync]` is inert on it. What looked like convergence on
   deterministically-bootstrapped objects was every peer independently building
   the same starting value, not live syncing - any field that changes on a
   `Snapshot` object afterward will silently diverge between peers and stay
   diverged. **`NetworkMode.Object`, entered via `NetworkSpawn()`, is mandatory
   before `[Sync]` does anything** - not limited to per-owner objects (player
   bodies, transient projectiles) as the retracted claim implied; it is required
   for any object carrying a `[Sync]` field, full stop. **The 2026-07-14
   scope-limit finding still holds and now reads as the general rule, not an
   exception:** a HOST-ONLY singleton created at runtime (`scene.CreateObject()`)
   has NO cross-peer identity unless it is host-`NetworkSpawn()`ed -
   `Network.Active` stays false and its FromHost fields NEVER send - and clients
   must not create a competing local copy
   (`g-game-fromhost-singleton-must-be-networkspawned-not-runtime-snapshot`; see
   the [P2P peer-hosted servers](/guides/p2p-peer-hosted-servers) guide).
2. **The engine does NOT stop a non-host writing a FromHost field locally** —
   the write just gets steamrolled by the next snapshot. The manual guard is
   therefore load-bearing:
   ```csharp
   if ( Networking.IsActive && !Networking.IsHost ) return;   // host-authoritative singletons
   if ( IsProxy ) return;                                     // per-owner objects
   ```
3. Instance `[Rpc.Host]` methods on snapshot-built objects route to the host's
   matching instance. `Rpc.Caller` identifies the requester;
   `using (Rpc.FilterInclude(conn)) SomeBroadcast(...)` narrows a broadcast to
   exactly one client — the confirm/deny-to-caller primitive.
4. `INetworkListener.OnConnected/OnDisconnected` fire **host-only** (for remote
   peers); a joiner learns its own connection completed by polling
   `Networking.IsActive && !Networking.IsConnecting`.

## The per-system recipe

For each mutable system, apply mechanically:

1. **Authoritative fields → `[Sync(SyncFlags.FromHost)]`**; every mutation
   host-gated (fact 2).
2. **Client intent → `[Rpc.Host] RequestX(...)`**. The host validates against
   **its own** state — never against client-sent positions.
3. **First-request-wins via an idempotent latch** (`_opened`, `_consumed`,
   `HolderId != Empty`): the second simultaneous request finds the latch set and
   no-ops. This one pattern kills double-consumption, simultaneous grab, and
   multiple winners.
4. **Confirm/deny to the caller** via `Rpc.FilterInclude(Rpc.Caller)`.
5. **Presentation = a pure function of the synced fields**, run per-client with
   a primed edge-detect, so late-joiners reconstruct state without replaying
   one-shot side effects.
6. **Single-player short-circuit**: `Networking.IsActive == false` takes the
   direct pre-networking code path — byte-identical behavior, no RPC hop.
7. **Disconnect cleanup**: host-side liveness poll of recorded `Connection`s
   each tick.

## NPC AI — decompose, don't rewrite

The biggest anti-double-apply surface is locally-simulated NPC AI. The
structural fix is small and staged: (a) **gate every NPC's `OnFixedUpdate` to
the host** — this alone kills divergent decisions; (b) NetworkSpawn the NPCs +
transform sync + a `FromHost` presentation-state enum; (c) reactions fire
host-side; (d) any vision/targeting that reads a local singleton must scan ALL
players. Do not rewrite the mega-classes — add the host gate and sync at their
public seams.

## Player locomotion stays owner-authoritative (deliberately)

Movement, climb, swing, charge/jump remain owner-predicted with `[Sync]`'d
outputs — prediction is accepted for feel; the host is authoritative over the
WORLD the player acts on, not the player's own body.

## Predict-then-confirm rollback without a rollback API

A denied prediction needs NO callback plumbing **if the sim already reconciles
against the owning object's state every tick**: the deny handler just clears the
object's local flag; the player sim's existing "item gone" path unwinds the
prediction next tick. Look for the existing per-tick reconcile before inventing
a rollback seam.

## Late-join checklist

Walk every host-authoritative bit and ask: does a mid-run joiner reconstruct it?
Open gates, moved NPCs, consumed pickups, progress meters, clock value, run/win
state. Most fall out of `FromHost` syncs + the pure-presentation rule; anything
driven by a one-shot event needs an explicit snapshot. Test by joining a session
where everything has already happened.

## Riskiest interactions — name them in every test plan

Simultaneous grab · double consumption · multiple winners · double
daze/stat-bump · per-client divergent AI targets · late-join divergence. Each
maps to exactly one recipe step above.
