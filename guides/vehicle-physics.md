---
title: Vehicle physics — the slip-curve raycast-wheel stack
slug: vehicle-physics
date: "2026-07-13"
updated: "2026-07-16T02:31:00-04:00"
lanes:
  - writing-gameplay
tags:
  - vehicles
  - physics
  - tuning
  - gameplay
summary: >-
  The proven architecture for driving games in s&box: raycast wheels on a single
  chassis Rigidbody, substepped slip-ratio/slip-angle tire physics with peaked
  curves, a torque-curve drivetrain, layered assists, and arcade dials on top of
  a sim core.
sourceRev: methods/vehicle-physics.md
relatedFixes:
  - rigidbody-component-api
  - sbox-units-are-inches
  - rotation-fromyaw-is-ccw
  - capsule-vs-box-collider-choice
unverified: false
---

The proven architecture for driving games in s&box: raycast/shapecast wheels on a
single chassis Rigidbody, substepped slip-ratio/slip-angle tire physics with
peaked curves, a torque-curve drivetrain, layered assists, and arcade dials on
top of a sim core.

Official docs cover `Rigidbody`/`PhysicsBody`/traces; there is no vehicle-physics
method doc. See [rigidbody-component-api](rigidbody-component-api) for the engine
surface.

## Locked architecture (don't re-litigate these)

1. **One chassis Rigidbody; wheels are raycast/shapecast, not bodies.** Each
   wheel is a component doing ground detection + spring/damper + tire-force math;
   forces apply to the single chassis body. Multi-body joint wheels are a
   separate research track, not the baseline.
2. **SI units everywhere; convert at the engine boundary**
   (`MetersToUnits = 39.37f`). All internal math in meters/N/kg/s — see
   [sbox-units-are-inches](sbox-units-are-inches).
3. **Set gravity explicitly** — the stock scene gravity is ~2.2 g and will
   silently wreck every tuned number.
4. **Deterministic**: no runtime RNG in physics or tests; scripted maneuvers
   frame-reproducible. This is what makes agent tuning honest.
5. **All feel dials in data** (per-car definition + a tuning-constants class),
   never scattered in logic.

## The wheel

Per wheel, configured by the factory from a car definition: radius, inertia,
suspension travel/rates, longitudinal/lateral curves, load sensitivity, static
load, steering/driven/handbrake flags, plus live multipliers (`GripScale`,
`ParkBrakeScale`).

Per step:

1. **Shapecast down** (small sphere, not a line trace — survives mesh edges)
   from the attach point along suspension travel. Grounded ⇔ hit.
2. **Suspension**: spring force from compression + damper from compression rate,
   applied along the **contact normal** — not world-up. On a slope, world-up
   suspension slowly walks the car sideways; contact-normal suspension is the
   fix.
3. **Tire model**: wheel angular velocity is **integrated state**. Slip ratio =
   (wheel surface speed − ground speed) / |ground speed|; slip angle from the
   velocity direction at the contact in wheel frame. Each feeds a **parametric
   peaked curve** (force rises to a peak slip value, falls off past it) — the
   peak is what makes limit handling readable. Combined slip via a **friction
   ellipse**, scaled by **load sensitivity**, with a low-speed blend (slip
   definitions explode near zero).
4. **Do not smooth longitudinal slip** — smoothing adds surge lag that reads as
   a rubber band. Lateral slip-angle smoothing is fine.

## Substepping — what it actually buys

Run **N internal substeps per fixed update** (e.g. 4 × 50 Hz = 200 Hz effective)
— but this is *drivetrain/wheel-state* substepping, not a full contact sim: the
ground trace happens ONCE per fixed update, the rigidbody does not advance
between substeps, and the accumulated tire force is applied once, averaged. What
the substeps genuinely refine: wheel angular-velocity integration, clutch/RPM
coupling, and the traction-control feedback loop. Contact/chassis transients
still resolve at fixed-update rate.

Also from `OnStart`: **`PhysicsBody.AutoSleep = false`** (a sleeping body ignores
suspension forces — the car sags dead), and a short **spawn settle-freeze**
(`MotionEnabled = false`) so the car initializes level and still.

## Drivetrain

Torque curve (RPM → N·m) → auto-clutch → gearbox with **ground-speed-implied
shifting** (gear from wheel speed, not engine state — immune to flare) → open
differential split across driven wheels. Short gearing is a *tuning tool*: a
high-power class can be made driveable by short final drive capping usable power
before wheelspin, not by underpowering.

A driver-selectable **sequential manual mode** layers on cleanly: a `ManualMode`
bool gates ONE thing -- the auto-shift block in `Simulate` is skipped -- and
`ShiftUp()`/`ShiftDown(groundWheelSpeed)` drive `Gear++/--` reusing the SAME
shift-timer + post-shift-lockout the auto path sets, so the flare/torque-cut model
is shared, not forked. Two design choices worth copying: gate manual shifts on
`IsShifting` only (the torque-cut window), NOT on the longer anti-hunt lockout --
that lockout is an auto-box concern and makes a hand-shifted box feel sluggish. And
the over-rev (money-shift) guard blocks a downshift whose *predicted* rpm
(`groundWheelSpeed * ratio_lower`) exceeds redline -- key it off the predicted rpm,
not the current engine rpm. Default `ManualMode=false` keeps the auto path
byte-identical, so the mode is pure opt-in.

## Assists — a layer, not a physics fork

Assist level (Casual/Sport/Sim) selects intervention strength for ABS
(brake-slip duty-cycle), TC (proportional throttle cut holding slip near the
curve peak — never an on/off cut, which oscillates), and a stability damper (yaw
damping ramping in above a rear slip-angle threshold). Two hard-won rules:

- **Assists are player-facing, so test at the level a player would choose**: a
  J-turn battery that pins Sport for RWD cars, because Casual's stability damper
  — correct in normal driving — kills the deliberate rotation the maneuver
  requests.
- Arcade feel is **dials over the sim core**, not a second model: launch boost,
  brake assist, handbrake grip scale on top. A Sim↔Arcade preset system is a
  profile struct scaling existing dials — never fork the physics.

## Drift-exit physics in a slip-curve model

Three findings from making a drift-exit complaint measurable:

1. **Slip-RATIO interventions are trajectory-neutral once the tire is in its
   tail.** Softening a handbrake clamp measurably changes wheel state but can
   produce identical chassis metrics — the longitudinal curve is flat past its
   tail start and the friction ellipse stays saturated. Don't expect "keep the
   rears spinning" to restore lateral authority mid-slide in this model.
2. **The exit throttle spike is the fixable half.** On release the player goes
   to full throttle while rear slip angle is still extreme; drive torque spends
   the ellipse longitudinally exactly when realignment needs it laterally. A
   drift-catch assist — briefly ramp throttle toward zero while |rear slip
   angle| is beyond a threshold (Casual/Sport only) — measurably raises speed
   retention. Keep a slip-angle floor so deliberate power-oversteer is untouched.
3. **Deep-slide momentum scrub is ellipse-rate physics**: the only real lever on
   scrub/recovery depth is the LATERAL curve's tail — which moves every
   cornering maneuver, so gate it on a battery + owner call.

## Spin-recovery: the uncovered throttle quadrant

An arcade brake-assist (extra chassis decel while `Brake > 0`) leaves one quadrant
uncovered, and it is exactly the one a spin exposes. After a handbrake flick spins
the car ~180 degrees, the player holds forward throttle but the car still slides
backwards along its old travel direction. In the input mapping, a forward gear +
forward throttle sets `Throttle=1, Brake=0` -- so brake-assist never fires -- and
the only thing arresting the backward slide is deep-slip tire tail grip. Result:
the stale velocity dies slowly ("keeps rolling backwards too long"). The general
rule: **brake-assist covers `opposing input -> Brake`; it never sees `throttle
commanding the gear's direction while ground velocity along facing opposes it`.**

Fix that generalizes: a second chassis-decel channel (`SpinRecoveryAssist`, m/s
squared) applied along negative planar-velocity whenever `sign(gear) * forwardSpeed < 0`
under throttle, scaled by an opposition ramp `clamp(-forwardSpeed/planarSpeed, 0, 1)`
so it fades to zero as the car rotates to face its motion (self-disabling -- no
explicit timer). Same never-reverse-within-a-step cap as brake-assist
(`min(decel, planarSpeed/dt)`); Casual/Sport only, Sim raw. It reads INPUT
throttle and applies a chassis force, so it composes with the drift-catch assist
(which cuts DRIVETRAIN throttle for a sideways rear) without merging -- sideways-
realign and backwards-kill are different states and a spin needs both.

## Input seam — one struct, everything is a peer

A nullable `DriveInputs` override on the controller: when set, it is consumed
INSTEAD of live keyboard/gamepad, so the test pilot, a gamepad layer, and a
future wheel device all drive the identical input → assists → drivetrain path a
human uses — and none of them ever applies forces directly. Build this seam on
day one; it is what makes the whole [agent-test-harness](/guides/agent-test-harness)
battery possible for vehicles.

The struct holds LEVEL intents (throttle/steer/handbrake) read directly each fixed
tick. When you add EDGE intents (gear shift, mode toggle), don't read
`Input.Pressed` from `OnFixedUpdate` -- it's frame-scoped and the fixed step runs
0..n times per frame, so presses drop or double-fire. Latch the edge in `OnUpdate`
into an instance bool, consume it in the fixed-step `ReadInput`; and edge-detect
the COMBINED request (device latch OR the scripted struct bit) against a `_prev`
bool so a scripted source that holds the bit still shifts once. One unified
rising-edge detector covers device + pilot without a branch. See
[input-pressed-fixedupdate-drops](/fix/input-pressed-fixedupdate-drops).

## Tuning by metrics, not vibes

Per-class metric bands grounded in real-world figures, a scripted maneuver
battery measuring them, and the loop *edit dials → battery → diff vs bands →
adjust*. Rules that made it work:

- Every band records its **reference basis and any deliberate deviation**.
- A band that measurement/feel proves wrong gets **edited with a reason**, never
  silently ignored.
- Feel heuristics become metrics: catchability, plantedness, bounciness.

## Spawn/recovery traps

- **Spawn at suspension equilibrium height** — `surface + radius` starts the
  springs at full extension and the car porpoises.
- **`Rotation.FromYaw(+angle)` turns LEFT** — the steering-sign bug; see
  [rotation-fromyaw-is-ccw](rotation-fromyaw-is-ccw).
- **Recovery / unflip** must re-level against the ground normal and re-freeze
  briefly, or the car re-enters contact mid-correction and carts.
- **Fall-through** on coarse/stepped collision: size the wheel shapecast and
  suspension travel against the actual collision grain, not the visual terraces.
