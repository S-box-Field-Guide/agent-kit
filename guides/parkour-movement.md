---
title: Parkour movement — the trace-mover traversal kit
slug: parkour-movement
date: "2026-07-13"
updated: "2026-07-15T00:24:00-04:00"
lanes:
  - writing-gameplay
tags:
  - movement
  - parkour
  - character-controller
  - gameplay
summary: >-
  The method for feel-first traversal on a kinematic trace-based character:
  coyote-time jumps, double jump, mantle, slide, wall run, node climbing, and
  rope swinging — plus the ground-contact quality work that makes all of it
  read smooth.
sourceRev: methods/parkour-movement.md
relatedFixes:
  - kinematic-movement-startedsolid
  - double-jump-set-velocity-directly
  - trace-kinematic-no-trigger
  - input-config-bindings
unverified: false
---

The method for feel-first traversal on a kinematic trace-based character: coyote
time, double jump, mantle, slide, wall run, node climbing, and rope swinging —
plus the ground-contact quality work that makes all of it read smooth, and the
level-design math that makes it tunable.

The basic kinematic mover (wish-dir from camera yaw, sphere trace + slide-plane
projection) starts with
[kinematic-movement-startedsolid](kinematic-movement-startedsolid). This guide
is the traversal layer on top.

## Foundation rules (violate none)

- **Always handle `tr.StartedSolid`** — ignore collision that frame so an
  overlapped body can walk free; the alternative is permanent entrapment.
- **Vertical state is yours, not the trace's**: track height/vertical speed
  explicitly and keep horizontal traces at a fixed torso height.
- All dials in a tuning class, SI units, one conversion at the boundary.
- **Instrument from day one**: a `stuck` watchdog line, state-transition
  telemetry, and a swallowed-input log — feel bugs are input-eating bugs more
  often than physics bugs.

## Ground contact quality (do this before any moves)

1. **Rate-limit the DOWN snap.** A ground-stick that hard-teleports to
   `groundTop + skin` pops on every curved slope. Snap **UP instantly** (never
   sink into geometry — that StartedSolids the next trace), but ease DOWN at a
   bounded glue rate. Sizing rule: the glue must clear the real per-step drop at
   top speed so genuine descents pass unclipped. Do NOT smooth the snap *target*;
   rate-limit the applied move only.
2. **On stepped/coarse collision, add step glue + (only where the root is NOT
   engine-interpolated) visual smoothing**: size step-up/-down probes to the
   terrain's actual step. A hand-rolled per-frame visual-z smoother is valid
   **only** when the character root is not already interpolated by the engine — if
   `WorldPosition` is written in `OnFixedUpdate`, `FixedUpdateInterpolation`
   (default ON) already smooths it, and a second per-frame smoother computed from
   raw fixed-tick z double-smooths into a 50 Hz sawtooth that reads as model
   flicker on stepped terrain. Verify engine interpolation is absent/disabled
   before reaching for the manual smoother. Audit that standing still never
   oscillates.
3. **Slide/slope logic needs a continuous slope estimate on stepped collision** —
   the flat-quad coarse surface reads as 0° or wall, so derive slope from a
   multi-sample probe; when a slide goes airborne, detach cleanly to free
   air-slide.

## The jump kit

- **Coyote time** (~0.15–0.2 s): a jump just after leaving a ledge counts as a
  ground jump and does NOT spend the double jump.
- **Input buffering**: a jump pressed slightly early fires on landing —
  buffering is a first-class feature, not a nicety.
- **Double jump: set vertical velocity DIRECTLY.** The controller's `Jump()`
  clamps against rising velocity and silently no-ops mid-air — do not "fix" that
  back; write `Velocity.z`. See
  [double-jump-set-velocity-directly](double-jump-set-velocity-directly). Steer
  the second jump toward the held direction.
- **Refresh rules create routes**: refreshing the double jump on wall touch and
  grapple attach turns walls into route nodes and enables chains.

## Mantle

Auto-mantle a ledge within a fixed reach when jumping toward it (probe forward
at ledge height, then up-and-over). Two reuse notes:

- Mantle is also the correct **swim exit** — boosting out of water reads as a
  rocket; a ledge-grab mantle reads right.
- Document the **reachability ladder** the numbers produce (jump apex,
  jump+mantle, double-jump+mantle) — level geometry is tuned against these, so
  they are part of the movement contract, not trivia.

## Wall run

- **One entry probe, branch on ENTRY SPEED.** Wall run and climb want the
  identical tall-wall detection — don't duplicate the probe; gate on
  pre-contact horizontal speed (threshold between walk and run): fast → wall
  run, slow → climb. Call the entry from BOTH the ground tick and the air tick.
- **Rebuild `Velocity` fresh each tick from tracked scalars** (`up`, `along`)
  instead of accumulating — then the slide-mover mangling the into-wall
  component is harmless (overwritten next tick). This compose-fresh pattern is
  the house rule for every constrained state (bar swing uses it too).
- A wall-run gravity dial bleeds the upward glide for a natural top-out; exit on
  duration OR when upward speed decays; on timeout **re-probe into the wall** —
  still climbable → drop to climb, else air.
- Wall-jump exits get their own (stronger) dials than the climb wall-jump —
  chains must cover real distance. Respect a climb re-entry cooldown shorter
  than the wall-jump arc so chains re-enter cleanly.
- Visuals: face into −wallNormal; pick clips by the along-wall velocity
  fraction; pace clip rate by wall travel speed.

## Node climbing (climbable objects without authored climb volumes)

Wrap a field of grip nodes around a climbable object — but **surface-FIT every
node by raycasting inward** to the actual collider; never place at a formula
radius (tapered/shelved meshes put a fixed radius inside the mesh).

Each node carries THREE things: `GripPos` (hit + small proud offset — where
hands grab), `Pos` (hit + proud + **bodyRadius** — where the body root hangs;
grip offset ≠ body offset), and the actual hit `Normal` (not a radial
assumption).

Raycast misses → `Valid=false` nodes that traversal **skips past** up to a
budget — a missing slot must not dead-stop the climb. Drop the hit normal's
VERTICAL component before offsetting (a shelf top returns an up-normal that
would shove the grip skyward).

**The collider must match the VISUAL**: per-poly `ModelCollider` does not follow
`WorldScale` — on a scaled GO the hull stays tiny and buried. Bake a scale-1
wrapper and put the ModelCollider on a WorldScale-1 GO. Fit at `OnStart` —
sibling colliders must already exist ("resolve against reality after all
builders run").

## Rope/bar swinging

- The swing sim is a pendulum integrated around an **anchor** (physics pivot)
  with a **length** (radius); the state tick composes velocity fresh (same rule
  as wall run).
- **Visual mount ≠ physics pivot.** The rope's visual attach raycasts UP to the
  real roof collider at `OnStart` instead of trusting the builder's formula
  (formulas in two places drift → mid-air gaps). Moving only the visual
  preserves the tuned swing period exactly.
- Regrab needs a **recency gate** (don't re-grab the rope you just released for
  N ms) and grab selection should weight recently-used grips down.
- In multiplayer the swing stays owner-simulated; only "who holds which rope"
  needs arbitration — see [/guides/networking-methods](/guides/networking-methods)
  Part B.

## Design math: the combo distance ladder

Tune moves as a **distance ladder and build the level against it**: jump →
slide-hop → double jump → +spin → grapple, with risers capped below the reliable
clear. Every gap in the map is an interval on this ladder. When a dial changes,
the ladder doc changes — that's the regression contract for level reachability
(and what an autopilot suite asserts; see
[/guides/agent-test-harness](/guides/agent-test-harness)).

## Verification

- Waypoint-circuit autopilot with stuck-detection telemetry and screenshots en
  route — exercises the collision surface for real; audits: never falls through,
  never wedges permanently.
- Scenario harness asserts the state machine's public contract and PASS-by-skips
  input-driven beats with named handoffs.
- Camera: chase cams on terraced/roofed worlds need occlusion handling with
  sliver rejection.
