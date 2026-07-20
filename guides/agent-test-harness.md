---
title: Agent test harness — MCP-driven in-editor playtest automation
slug: agent-test-harness
date: "2026-07-13"
updated: "2026-07-20T12:00:00-04:00"
lanes:
  - tooling-environment
  - ai-assisted-workflow
tags:
  - testing
  - mcp
  - agent-workflow
  - tooling
summary: >-
  The architecture for letting an agent (or CI) drive the live s&box editor:
  compile-gate, spawn, play, inject input, read telemetry, screenshot, assert,
  and gate a merge on the numbers — with no human at the keyboard.
verifiedOn: "26.07.15a"
sourceRev: 0bae76b10a15
relatedFixes:
  - first-play-compile-checklist
  - dotnet-build-misses-razor-errors
  - editor-hotload-expectations
  - stale-assembly-hotload
  - agent-file-ownership-discipline
  - ai-agents-build-game-in-a-day
unverified: false
changelog:
  - { date: "2026-07-20", note: "Added coarse-telemetry trap to operational checklist" }
---

The method for letting an agent (or CI) drive the live s&box editor: compile-gate,
generate/spawn, play, inject input, read telemetry, screenshot, assert, and gate a
merge on the numbers — with no screen control and no human in the loop.

Official docs cover the editor and custom tooling but say nothing about a
test-automation architecture. The editor MCP server is engine-shipped but
undocumented for this use. This guide is the synthesis; the fix layer holds the
trap atoms.

## Architecture

Three independent projects converged on the same shape:

```
tools/<runner>.py  (JSON spec suite, verdict table, non-zero exit)
   │  stdlib-only HTTP client
   ▼
s&box editor MCP server  http://localhost:<port>/mcp         [engine-shipped]
   │  meta-tool layer: call_tool → the real tools
   ▼
project [McpTool]s  (Editor assembly)                       [you write these]
   │  post commands / read reports
   ▼
static Bridge facade (game assembly)                        [you write this]
   │  consumed per-tick
   ▼
play-mode Pilot component                                   [you write this]
   │  injects INPUT INTENTS through the same seam a player uses
   ▼
your actual game code (controller / generator / systems)
```

Two halves, deliberately decoupled: the **python side** (client + runner + specs)
works with no C# landed and degrades gracefully (`--dry-run` validates specs
offline — the CI-safe gate); the **C# side** (tools + bridge + pilot) is built
against a **frozen interface contract** written down first. The runner's known
metrics set is the machine copy of the telemetry table — change one, change the
other in the same commit.

## 1. Endpoint discipline (before anything else)

The editor MCP port is **one global s&box preference** — the last editor to start
wins it, so with several projects' editors on one machine the port number is a
*hint, never an identity*.

- Drive the URL from an **env var** or `--url` flag, never a committed default.
- **Identity-probe before any mutating call**: `editor_status` must return your
  project name, AND your project-prefixed tools must be listed via `search_tools`
  — only your project's Editor assembly defines them, so their presence is proof
  beyond the project name. Bake the probe into the runner's `preflight()`.
- If the probe lands on another project: STOP. That editor belongs to another
  session.

## 2. The client (port it — don't rewrite it)

Python **stdlib only** (agents can run it anywhere). What it encodes:

- **The s&box MCP surface is two-layered**: `tools/list` exposes only entry-point
  meta-tools (`editor_status`, `read_console`, `search_tools`, `call_tool`, …);
  every real tool (`compile_status`, `play_start`, `editor_camera_screenshot`,
  your project tools) is invoked THROUGH `call_tool {"name":…,"arguments":…}`.
  The client wraps this — callers just name the tool.
- Transport: stateless HTTP POST, JSON-RPC `tools/call`, no session/initialize
  handshake; handles both SSE-form and plain-JSON answers.
- Server conventions: vectors/angles are **comma strings** (`"x,y,z"`), units are
  inches (×39.37 from meters), +z up, degrees. Tool failures return `isError`
  results, not protocol errors.
- Windows: run under `PYTHONUTF8=1` / `PYTHONIOENCODING=utf-8`.

## 3. Project `[McpTool]`s (Editor assembly)

Custom tools live in the editor assembly, so **no game-whitelist constraints**.
Conventions that held across projects:

- **Every tool takes ONE string arg** (`argsJson`) containing JSON, and returns a
  JSON string. The s&box tool layer does not marshal rich parameter objects
  reliably — a string arg named exactly `argsJson` is the proven shape.
- Tool inventory shape: one **status** tool (read-only), one **act** tool per
  domain, one **audit** tool (re-run invariants on demand), plus comparison
  primitives (content hashes).
- Return the machine-readable **census/report object**, not prose: counts,
  hashes, timing, audit lines, and an `Error` field that is null on success.

## 4. The Bridge (editor↔play-mode command bus)

Editor-assembly tools cannot call into a running play session directly; the
bridge is a **static command/report facade** in the game assembly: the McpTool
posts a command, the play-mode Pilot consumes it per tick and writes telemetry
back.

Two load-bearing rules:

1. **Session-reset the statics** in the boot singleton's `OnEnabled` — static
   state survives Play→Stop→Play, and a leftover flag makes the first command of
   the new session no-op against last session's state. If a run's telemetry looks
   like the *previous* run's, suspect a missing session-reset.
2. **No `System.Threading`** (`Volatile`/`Interlocked`) in the game assembly —
   whitelist. A plain **monotonic `int` token** compare is torn-read-proof on x64
   and is the handshake primitive.

## 5. The Pilot (input intents, never forces)

The play-mode director **injects input intents through the exact seam a player
uses** — it never applies forces or teleports the thing under test. One nullable
override property on the controller is the harness's entire footprint: when set,
`ReadInput` consumes it instead of keyboard/gamepad — so pilot and human drive
the identical path.

Give the pilot a **ConVar on-ramp** so suites run from a console command with no
MCP at all, plus a rebuild-path const for fully headless runs.

Decomposition once it grows: keep the pilot a thin orchestrator and make each
scripted test its own object behind an interface + name registry, so adding a
test is a new file + one registry line, not a pilot edit.

## 6. Verdict grammar (make the log greppable)

One machine-parseable line per unit, one roll-up line per suite:

```
[test] SCENARIO <NAME> PASS|FAIL <details>
[test] SUITE DONE passed=P failed=F total=N
```

Rules: a distinct prefix per producer; the roll-up is THE assertion (`SUITE DONE
… failed=0` ⇒ green); **audits are standing target-0 invariants that run on every
mutating step for free**. Failure details must name the exact diverged
expectation. Console buffer holds ~2000 entries and rolls — read promptly.

## 7. The spec runner (JSON suites + the live loop)

Specs are committed JSON files, one per test; the runner executes all of them and
exits non-zero on any failure. The live loop:

```
1. identity-probe
2. compile gate     compile_status must be Success + Errors=0 — REFUSE to run
                    on a stale/wedged compile. dotnet build is NOT this gate.
3. play_start       (generation-only suites skip play mode)
4. act              spawn / drive / generate
5. poll             status every 0.5 s until done (error fails immediately)
6. evaluate asserts against returned telemetry / census / hash
7. play_stop
```

Assert primitives worth stealing:

- Metric asserts against a **frozen telemetry contract** — an unknown metric is a
  *dry-run error* (spec-drift guard); a missing metric at live time is a *run
  failure*, not a skip.
- Hash asserts (`equal|differ`) for byte identity, naming the diverged sub-array
  on a miss.
- Screenshot-pair diffs with exposure-normalization.

**Test transitions, not just snapshots.** Fresh-generation snapshots are
structurally blind to state-transition bugs. Sequences mutate → regenerate →
verify after EVERY step, and assert return-to-start byte-identity — the strongest
stale-state detector.

Compile-gate traps: `compile_status` has no flat fields — parse `Compilers[]`;
the **compiler wedge** signature is `Success=false` + 0 diagnostics +
`NeedsBuild=false` → bump a source file's mtime to dirty it; a stale assembly
silently runs old code — mtime-bump + recheck proves the hotload path.

Traps: see [first-play-compile-checklist](first-play-compile-checklist),
[dotnet-build-misses-razor-errors](dotnet-build-misses-razor-errors),
[editor-hotload-expectations](editor-hotload-expectations),
[stale-assembly-hotload](stale-assembly-hotload).

## 8. Screenshot judging (the part everyone gets wrong)

- **Judge look ONLY from a locked-exposure game camera**: the edit viewport's
  tonemap/auto-exposure adapts over wall-clock frames, so two shots of a
  byte-identical world can differ by 26% right after a bright→dark regen. Settle
  before capture, and **exposure-normalize** the pixel diff.
- Canonical poses come from the generator so shots are pixel-comparable across
  code changes — determinism is what makes screenshot regression possible at all.
- If the editor is in **play mode**, editor-camera screenshots capture a stale
  frozen clone — check `editor_status.IsPlaying`, `play_stop` first.
- Edit-mode physics for runtime-built colliders is not reliably queryable —
  trust screenshots and play mode over edit-mode `scene_trace`.
- **A DATA gate cannot see a RENDER bug.** Any visual feature needs a
  screenshot A/B with a pixel-diff as its OWN acceptance step, distinct from
  the metric gate. "The hash is right" does not mean "it looks right." When
  building the visual A/B: (1) capture pristine and changed at the SAME camera
  and actor pose -- for a pinned/staged actor that means mid-hold (start the
  run non-blocking, sleep into the hold); (2) set the editor camera BEFORE the
  run -- a mid-run `set_editor_camera` loses to the game camera; (3) the
  cleanest matched pair is change-then-shot, repair/reset in place, then shot
  again so only the feature differs. Add a permanent per-object
  "did-it-actually-change" counter at the deform site so an invisible change
  self-announces without a screenshot at all.

## 9. Feel-as-metrics (the maneuver-battery specialization)

"Feels right" made checkable *before* a human plays:

- A battery of **scripted maneuvers** each measuring objective values.
- **Per-class bands grounded in real-world references** — with *deliberate
  deviations documented*.
- **Feel heuristics encoded as metrics**: catchability = yaw-impulse response
  settling without overshoot; "planted" = lateral-g rise time; "bouncy" =
  per-wheel contact-loss % + settle time.
- The loop: edit dials → compile gate → run battery → diff metrics vs bands AND
  vs last run → adjust. Owner sign-off = battery green ×N consecutive; owner
  feedback re-enters as **adjusted bands with a reason**, never silently ignored.

**Closed-loop maneuvers are marginally stable -- treat them differently from
open-loop ones.** A maneuver whose pilot is a feedback controller (a
position-locked pure-pursuit weave, a yaw-settle J-turn) can sit near its
stability boundary on grip-marginal configurations:

- **Determinism is per-attractor, not global.** Open-loop maneuvers (launch,
  brake, topspeed) are byte-identical run to run. A marginal closed-loop one
  has a first-run warmup perturbation from inherited state, then converges to
  the clean attractor on repeat. Gate rule: treat a single closed-loop FAIL as
  needing a confirming re-run; measure the converged attractor, or add a
  spawn-settle phase before the measured segment.
- **Full-precision geometry hashes off a DRIVEN approach are not
  byte-identical**, even with fresh-play-per-run. A multi-tick run-up
  accumulates drift that can cross triggers a tick early/late. Hash the STABLE
  decision (attributed part + rounded contact), or PIN the interaction
  (teleport-to-contact at fixed velocity) rather than driving up to it.
- **A recovery maneuver re-hits its own wall unless backup > drive distance.**
  Schema-valid but geometrically self-defeating. Fix the params AND add
  flips/fallThroughs==0 asserts so a glitched run FAILs loudly.
- **A band the target cannot reach is grip, not gain.** Before re-anchoring a
  red, prove it is grip-limited not controller-limited.
- **Do NOT reach for a derivative (yaw-rate) damping term to "stabilize" a
  weave.** A slalom *wants* sustained yaw; subtracting steer proportional to
  yaw rate fights the rotation the weave needs. The pure-pursuit gain-backoff
  already gated above every stable configuration's yaw peak is sufficient.

## 10. The in-game scenario harness variant (no MCP needed)

For testing game *systems* (NPC vision, pickups, day/night) rather than
generation/physics, run scenarios inside a normal Play session:

- `ITestScenario` (Setup → Tick → Assert → Teardown) + a queue created by
  Bootstrap only when the ConVar/const gate is set.
- Scenarios spawn into **throwaway GameObjects far from the real world** and
  destroy them on teardown.
- **Assert through the public surface only.** Where driving a beat headlessly
  would need a private setter, assert every reachable observable and
  **PASS-by-skip the driven half with a NAMED handoff** — skips are visible work
  items, not silent holes.
- Whitelist-safe by construction: no reflection, no `System.IO`, engine
  `Time`-driven, deterministic variation only.

## 11. The seeded stress-roam lane (bug generator, not regression gate)

When scripted point-repros keep passing while players still get stuck "somewhere
out there", add a **hyperactive-player emulation lane** — a seeded autonomous
roamer that exercises the world surface at scale:

- **Seeded and replayable, never random**: every decision (route order, jump
  cadence, reversal rolls) hashes from `(runSeed, decisionIndex, streamSalt)` — a
  failure's seed IS its repro, and every log line carries the seed. Expect physics
  drift between replays: the same seed re-finds the same *classes* at the same
  *geometry*, not the identical timeline — anchor triage on positions, not
  timestamps.
- **Bias the route toward features, not open ground**: sample targets from the
  world data the placers already expose (cliff faces, tree bases, water-margin
  blocks, drop-off lips), and alternate engagement modes per target (run-at-wall vs
  jump-at-wall) so every code path gets exercised.
- **Derive failure markers from observable state** (position, velocity, state enum)
  — observable re-derivation is whitelisted-safe and removes telemetry coupling.
  Patterns: position-freeze window, back-snap-against-input clustering (eject
  loops), below-surface at own XY AND below last-grounded z (sustained burial),
  climb-that-never-exits.
- **Events recover-and-continue** (teleport to the next target + detection-free
  grace) so one bad spot yields one event instead of wedging the whole run; cap
  events per run.
- **Calibrate detectors against the engine's own containment**: transient conditions
  the engine resolves within its containment window (e.g. a 4-tick eject) need a
  persistence gate, and states the driver deliberately parks in (pressing up at a
  climb-top latch) must be excluded from generic freeze watchdogs and owned by a
  state-specific detector.
- A run counts as signal when it surfaces a NEW event class or verifies a fix; stop
  the loop when consecutive fresh seeds yield only known-parked classes.

## Operational checklist

| Symptom | Cause / fix |
|---|---|
| Endpoint refuses / wrong project answers | Port stolen — env-var URL + identity probe |
| Green build, wrong runtime behavior | Stale assembly — mtime-bump + `compile_status` recheck |
| `Success=false`, 0 diagnostics, `NeedsBuild=false` | Compiler wedge — mtime-bump to dirty |
| First command of a session no-ops | Bridge statics not session-reset |
| Screenshots identical when they shouldn't be | Play-mode stale clone — `play_stop` first |
| Return-to-start screenshot differs, hash equal | Viewport auto-exposure — settle + normalize |
| Agent waits forever on a battery | Poll `read_console` for the suite's last line |
| Progress metrics read 0 mid-run | Autopilot metrics are state-gated |
| Run tokens missing from `read_console` | Per-tick telemetry floods the console ring -- read the editor log file with a flush delay, or grep for your exact token |
| Dent/damage hash flakes despite fresh-play | A driven crash run-up isn't byte-identical -- inject a pinned synthetic impact through the real damage path instead |
| Just-spawned component hook no-ops on first tick | `OnStart`/bind hasn't run -- gate on bound state + settle-tick floor |
| Recovery maneuver re-hits the wall / flips | Don't reverse-then-drive -- teleport the damage-preserving object to a clean lane, zero velocity, then measure |
| New maneuver "unknown" / stale logic in live editor | `static readonly` dict value migrates across hotload -- rename the field to force a fresh dict |
| Face-load/jounce A/B reads ~98-99% retention on both variants | Telemetry too coarse (~2 Hz) for a curvature-discontinuity transient a couple of ticks wide — use a finer trace or jounce proxy (suspension load / G-trace) |

Get the compile gate and identity probe right and everything else is iteration.
Parallel agents need an [ownership map](agent-file-ownership-discipline) before
they share a harness.
