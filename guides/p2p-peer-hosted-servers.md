---
title: "P2P peer-hosted servers — from working co-op code to a friend actually joining"
slug: p2p-peer-hosted-servers
date: "2026-07-14T22:30:00-04:00"
updated: "2026-07-17T12:00:00-04:00"
lanes:
  - writing-gameplay
  - publishing-shipping
tags:
  - networking
  - multiplayer
  - lobby
  - p2p
  - publishing
  - join
summary: >-
  The operational recipe for shipping player-hosted (P2P) multiplayer in s&box —
  lobby mechanics, invite codes, the join handshake liveness contract, replication
  traps, and the three-rung testing ladder — covering the layer the official docs
  don't document and where live multi-peer sessions actually break.
verifiedOn: "26.07.15a"
sourceRev: methods/p2p-peer-hosted-servers.md
relatedFixes:
  - dedicated-server-unpublished-package-join-fails
  - owner-simulated-networking
unverified: false
changelog:
  - { date: "2026-07-17", note: "Removed unverified ~60s lobby-directory propagation speculation." }
---

The operational recipe for shipping **player-hosted (P2P) multiplayer**: one player clicks "host", friends join by invite code, no dedicated infrastructure. This covers the layer the official docs don't document — everything below is verified in-engine (26.07.08e) unless marked otherwise.

**Prerequisite:** your game must already work in a same-machine two-peer session before anything here matters. For the networking architecture itself (deterministic spec replication, hash handshake, host-authority patterns), see the [networking-methods](/guides/networking-methods) guide.

## The three hosting modes

| Mode | Who can join | Publish needed? | Use for |
|---|---|---|---|
| Editor dev-host | `-joinlocal` clients + real peers | No | All agent-side testing |
| **Published peer host (this guide)** | Anyone with the game + code | **Yes** | The actual product |
| Dedicated `sbox-server.exe` | Anyone | Yes | Persistent servers |

The wall between column 1 and 2: **an unpublished `local.*` package cannot be joined by any non-editor client** — joiners die at `Package local.<ident> wasn't found!` because only an editor host advertises `dev-host=true`, which lets clients tolerate a missing package and stream assemblies. Real-peer testing requires publishing. A **Hidden** publish is fine — clients resolve a Hidden package by ident, it's only hidden from search. The publish-state enum is **Hidden | Released** (there is no Unlisted state). See [dedicated-server-unpublished-package-join-fails](/fix/dedicated-server-unpublished-package-join-fails).

## Publishing (once, then per-update)

- **Ident** = `org.package` (underscores in the package segment accepted). The org half can change after first publish; treat the package half as permanent.
- A freshly created org may not appear in the editor's publish dropdown until an editor **restart**.
- Publish from the editor title-bar project button, "Publish..". The publish-state enum is **Hidden | Released** — **Hidden** + a direct link is the playtest channel (search-hidden but ident-resolvable).
- **Updates = republish under the same ident.** Every peer must run the same build — see the protocol-version discipline below, because Steam will happily matchmake two peers running different cached builds.

## Lobby + invite code

The verified engine facts that shape the design:

**A `Hidden=true` lobby is structurally invisible to every ordinary `QueryLobbies` call.** The engine appends `q.WithKeyValue("hdn","0")` unless you pass a truthy `"hidden"` filter (engine-source-verified, confirmed by a live cross-peer failure: friend got "no server found for code"). A hidden-lobby + metadata-code lookup can never work. **Fix pattern:** visible lobby + only a **hash** of the code in lobby metadata + host-side verification of the real code on the wire.

**A host cannot discover its own lobby** — self-query exclusion holds even for visible lobbies, so the host can never learn its own `LobbyId`. This kills any id-encoded backup-code scheme, and means a self-query proves nothing about whether real peers can find you.

**Stamp a protocol/build version key in lobby metadata** and refuse mismatches client-side before connecting. Any RPC signature change on the join path must bump that protocol version — shipping a 3-arg RPC while the version still says 2 means the lobby pre-check approves a peer whose RPC schema silently doesn't match (the exact shape of an unexplainable stall).

**Also stamp a publish number** (separate from the protocol version) so a tester is never silently stale. The protocol version only changes on a wire-contract change; a routine content republish leaves it identical, yet the peers are different builds. Add a monotonically increasing `PublishStamp` under a short lobby key (mind Steam's ~128-char aggregate metadata cap), advertise it beside the protocol key, and pre-check it client-side: missing/mismatch means refuse with a human message naming both builds and the remedy. Bump it before every publish.

**Short-code entropy caveat:** a 4-char base-32 code is ~20 bits; an unsalted deterministic hash of it in public metadata is enumerable in seconds. Fine as a friends-convenience code; do not document it as an access-control secret.

## Privacy levels, the hidden-inclusion query, and Steam invites

Engine-source-verified corrections to the lobby privacy model:

- **`LobbyPrivacy` has three levels — `Public`, `Private`, `FriendsOnly`** — each maps to a Steam `ELobbyType`. Steam's `RequestLobbyList` (what `QueryLobbies` calls) **only returns `Public`-type lobbies**; `Private` and `FriendsOnly` are excluded from every list query. So `Privacy=Private`/`FriendsOnly` **kills a metadata-code lookup** — do not use them if code-join must keep working.

- **`LobbyConfig.Hidden` is orthogonal to Privacy.** It only stamps the `hdn` lobby-metadata tag; `QueryLobbies` appends `q.WithKeyValue("hdn","0")` (filters hidden out) **unless the caller passes `filters["hidden"]` truthy**. So **`QueryLobbies({..., ["hidden"]="1"})` includes hidden lobbies** in the results. This corrects the earlier "hidden lobbies are unreachable" finding: they are reachable if you opt in on the query.

- **The winning privacy design for public vs private with a code that always works:**
  - **Public** = `Hidden=false, Privacy=Public` — listed in the browser + code-findable + Steam-invitable.
  - **Private** = `Hidden=true, Privacy=Public` — not listed anywhere, but still code-findable (via the `["hidden"]="1"` query) and Steam-invitable (a `Public`-type lobby is joinable by its id; the unlisted id is the secret an invite/code hands out). Keep `Privacy=Public` in both — flipping Privacy to `Private`/`FriendsOnly` drops the lobby out of the code query entirely.

- **Testability trap — the editor forces lobby privacy to `Private`.** `Networking.CreateLobbyAsync` overrides `config.Privacy = EditorLobbyPrivacy` (defaults to `Private`, `internal` — not settable from game code) when running in the editor. Any editor-host lobby is Steam-Private regardless of what you pass, which means `QueryLobbies` finds nothing. This is the real reason a self-query probe returns nothing on an editor host, not the `hdn:1` tag. The public-vs-private discoverability difference is only exercisable on a **published build**; `-joinlocal` bypasses queries (direct loopback) so it can't test it either.

- **Steam invites — how an accept reaches game code:**
  - **Send:** `Lobby.InviteOverlay()` / `Lobby.InviteFriend(steamId)` are internal menu-layer APIs, not reachable from addon code. The addon-facing `Game.Overlay.ShowFriendsList` only opens the friends modal. The always-available invite path is the **Steam overlay (Shift+Tab) → "Invite to Game"**, which works with zero game code because `SteamRichPresenceSystem` publishes `connect = "+connect <lobbyId>"` for the active lobby.
  - **Accept (game running):** `GameLobbyJoinRequested_t` fires engine-side; the menu subscribes and calls `Networking.Connect(lobbyId)`. Cold start: Steam relaunches with the `+connect <lobbyId>` arg. **Either way the addon never runs its own Join UI, so an invited joiner presents no invite code** — the host's code gate must grant an "invite grace" (accept a code-less join) or every Steam invite is rejected. Trust model: the short code is a convenience secret; the real access control is discoverability.
  - The join intent carry (item 7 above) is for the code path; an invite join has no code to carry, so it rides the reconstruct path and is admitted by the invite-grace. No protocol bump needed.

## The join handshake needs a liveness contract

Live-proven failure mode: joiner connects, sees the host's replicated character — and sits on the loading overlay **forever**, with no Cancel and no diagnostic. Root cause is structural: the join handshake (spec receipt, client regen, hash report, host verify, resolve back) was a one-shot RPC chain with no deadline, no retry, no negative acknowledgement (a host-side null-check branch literally returned without replying), no Cancel control, and no client disconnect listener. Any lost hop means a permanent stuck UI.

The contract every P2P join flow needs:

1. **Attempt ID** minted at join start, carried through every hop.
2. **Receipt logging on the receiving side of every hop** (`Rpc.Caller.Id`, protocol version, attempt id). Never infer wire success from the sender's log — an RPC on a non-networked object runs local-only with zero warning.
3. **Every host branch replies** — positive or negative with a reason. No black-holes.
4. **Client watchdog**: no resolve within a deadline means disconnect, restore the menu state, show the reason.
5. **A working Cancel** on the joining overlay, wired to the same recovery path.
6. **The client's join state must survive the networked-scene handoff.** Connecting reloads the scene on the client, recreating session components — a component-enable that naively resets statics wipes the typed invite code and the joining state machine mid-join. Pattern: reconstruct-not-reset — a component enabling while `Networking.IsActive && !IsHost` preserves join statics, restores Joining, re-arms the watchdog, re-shows the overlay; and only the currently-registered instance may tear statics down (a late old-scene `OnDisabled` otherwise clobbers the reconstruction). Enables can fire twice per handoff — keep the reconstruction idempotent.
7. **The join intent must survive the client's assembly reload, not just the scene handoff.** Item 6 is necessary but insufficient on a published client: `Networking.Connect` loads the host's package (`org.ident#version`), which reloads the addon assembly — so every static resets and the reconstruct has nothing to reconstruct from. Statics survive only for a `-joinlocal`/editor host (same process assembly), so both local rungs mask this. **Fix:** persist the join intent (`{code, attemptId, writtenAtUnixMs}`) to `FileSystem.Data` right before `Networking.Connect`; restore it into the statics in the reconstruct and belt-and-suspenders at hash-report time, gated on a freshness window using `DateTimeOffset.UtcNow` (game `Time.Now` resets on the reloaded instance); delete after use (join/abandon/fail/end) and on any stale read; fail-soft to the clean-NACK path when absent. The reloaded instance mounts the same data folder for the same published ident (engine-source-verified).

**Diagnostic signature:** "joiner stuck on loading but can see the host's character" means connection + snapshot replication is healthy but the world handshake is dead — and it also tells you the host spawns players before validating them.

## The FromHost replication trap

A `[Sync(SyncFlags.FromHost)]` field only crosses the wire if its GameObject is **network-active**. "`NetworkMode.Snapshot` converges with no `NetworkSpawn`" is true for **baked-scene** objects (scene-baked identity on every peer) — it is **false** for an object created at **runtime** (`scene.CreateObject()`), which has no cross-peer identity: `Network.Active` stays false, the `FromHost` field never sends, and every joiner waits forever for a value that never arrives.

**Fix pattern:** the host `NetworkSpawn()`s the singleton (host-owned, same as any host-authored session object), and the joining client does not create a competing local placeholder — it receives the host's proxy and polls that.

Diagnose with a re-fetchable host-side probe reporting `Network.Active` + the `FromHost` field length ("host has the value, carrier isn't networked" is the signature). Client probes structurally cannot see this.

## Join-time ownership traps

**`static Instance` claims behind `if (!IsProxy)` are untrustworthy at creation time.** Components are created before `NetworkSpawn(owner)`, so on the host a joiner's character is momentarily non-proxy and clobbers the host's own singleton — the host camera then follows the joiner forever. Fix: re-resolve the claim at the first `OnFixedUpdate` (earliest point `IsProxy` is trustworthy): a proxy holding the claim releases it, the settled local owner re-claims.

Longer-term: cameras should target an explicitly possessed character, not poll a writable process-global singleton.

## The testing ladder (cheapest first)

### Rung 1 — Determinism suite, one process

Same spec N times, byte-identical output. See the [agent-test-harness](/guides/agent-test-harness) guide.

### Rung 2 — `-joinlocal` two-peer, one machine, no publish

Host in editor play mode, then:

```
sbox.exe -joinlocal +instanceid 1 -sw -720
```

Launch **after** the host is live. Key traps:

- **Verify the host is actually live first** (`networkingActive=true`) — rapid re-host churn during iteration can transiently fail `CreateLobby` (~15–20 s settle clears it), and a client launched against a dead host just gets connection-refused.
- **An invite-code wire-verify rejects the `-joinlocal` peer** — it TCP-connects directly and never runs the code-entry UI, so it presents an empty code. Add a dev-only seam (accept empty code only when `Application.IsEditor` on the host and the caller address is loopback) rather than weakening the shipped gate.
- The client **truncates and rewrites the shared `logs/sbox.log`** — grep the whole current file for client receipts; host evidence must come from re-fetchable probes or the editor console.
- A **failed join permanently wedges the editor's game package mount** — plan an editor restart after every failed attempt.
- Convar-triggered probes are **unreachable on the client**.
- **Eyeball the client window at least once**: host-side probes structurally cannot see a client whose camera/UI is wrong.
- **This rung's blind spot**: a `-joinlocal` peer never enters an invite code, never exercises the assembly reload, and never tests `FileSystem.Data` carry. Bugs that only bite on a real published join are invisible here. Multiple live-proven bugs sailed through green local runs for exactly this reason.

### Rung 3 — A real second peer on the published build

The **only** test that settles Steam backend behavior (lobby visibility, directory propagation, relay transport) and build skew. Verify both peers log the same build/protocol version before debugging anything else.

Practice:

- **Host evidence**: the host's `sbox.log` is intact on this rung (no local client truncates it) — grep hop-tagged lines there. The remote tester's evidence is screenshots of what their client shows.
- `Connection.Address` is `'unknown'` for real remote peers — never gate behavior on it cross-machine (it works only for loopback dev seams).
- **Expect iteration**: publish, friend tests, one named failure, fix, bump stamp, republish. With the liveness contract in place each round costs minutes and the failure names its own hop. Budget for several rounds, not one.

## Voice integration

If the session has voice, the `Voice` component follows the same create-before-`NetworkSpawn` wiring as characters and therefore sits inside the join spawn path. An exception there is a join-killer — wrap and log it like any other hop. See the [voice-proximity-chat](/guides/voice-proximity-chat) guide for the full wiring method.
