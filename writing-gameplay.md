# Writing gameplay — skill pack

> Lane pack. Load `_core.md` first, then this file. Denser than the full articles by design;
> for a matching bullet's full write-up, follow that gotcha's article link in `coverage.md`
> (full articles live on the Field Guide website, not in this pack). Sanitized public
> advice; unconfirmed details marked `(needs verification)`. The sync appends new bullets here.

## Scene & world

- **Flat "decal" geometry must clear the surface below it.** Ground box top at z=0 →
 water/road/path boxes need their top at z≥+0.5 or they're invisible. We shipped a
 completely invisible creek and pond this way.
- **A "decal" box splatted at a projectile's raw hit point sticks to whatever it hit —
 including a person's chest.** A thrown-projectile splat placed at `tr.HitPosition` on an NPC
 became a floating slab glued mid-body. Fix: only splat-at-surface for WORLD hits; for
 a body hit, trace DOWN from the NPC's feet (start the trace ~0.3 m ABOVE feet — the NPC
 WorldPosition sits at ground level, so a trace from exactly there begins inside the
 floor and self-hits) and lay the splat on the ground below.
- **Orient a flat "decal" box to the hit NORMAL, not world-up.** `Rotation.FromYaw(yaw)`
 alone leaves the box's up = world-up, so a wall splat lies flat on the floor "the wrong
 way". Build the rotation so the thin (+Z) axis points along the normal:
 `refv = |n.z|>0.99 ? Forward : Up; fwd = Cross(refv,n).Normal; rot = LookAt(fwd,n) *
 FromYaw(yaw)`, then offset +0.5 u ALONG the normal (generalizes the floor decal-gap
 rule to walls/props). Make it a FILM (~0.02 m) not a slab so it reads as a decal.
- **A translucent splat on `models/dev/box.vmdl` reads fine — its UVs are 0..1 per face.**
 The magenta "opaque glossy slab" was NOT a material bug (F_TRANSLUCENT compiled, the
 RGBA texture bound — confirmed in the .vmat_c). It was the pink splat's own magenta
 center shown on a thick slab floating on a body. box.vmdl maps the whole texture once
 per face at `g_vTexCoordScale [1 1]` (plaza uses `[5 5]` to TILE 5×), so the blob shows
 correctly. Pin splat roughness to 1.0 + metalness 0 + `g_flModelTintAmount 0` for a matte
 cartoon look and never set renderer `.Tint` on it (a tint flattens the blob to a solid
 fill).
- **Prefer runtime world-building over giant generated scene files** for anything the
 code needs to know about: scene holds only Sun + Skybox + Camera + one Bootstrap
 component; C# builds the rest in `OnStart`. Hotloads better, no scene/code drift.

- **Over-world UI (name labels, health/alert bars over a head) is built from MODEL-BASED
 tinted boxes, NOT a WorldPanel razor, in one project.** Two independent places
 (`ZonesBuilder.NameLabel`, `MapExtension.NameLabel`) explicitly chose "dark backing
 slab + bright face-plate" dev-box renderers over a WorldPanel "to avoid razor namespace/
 BuildHash traps" — and there is ZERO working WorldPanel usage in the codebase to copy. The
 guard's daze "stars" cue (`GuardNpc.SpawnStars`) is the same idiom: `models/dev/box.vmdl`
 renderers parented to the character, `renderer.Tint` for color, `LocalScale = sizeMeters *
 M / 50f` (the dev box is a 50u cube). For a FILLABLE bar (alert meter), a back slab +
 a fill slab whose X-scale = fraction, left-anchored, billboarded to `Scene.Camera` each
 frame: to present the wide face, orient the WIDTH (+X) axis along screen-right
 (`Cross(Up, toCam)`) via `Rotation.LookAt(screenRight, Up)` — NOT `LookAt(toCam)` (that
 points +X at the camera, showing the bar edge-on). Cheap, reliable, visible from any angle,
 no razor surface.
- **Full-screen HUD toasts/banners: mirror ScreenFade — a `PanelComponent` with a static
 null-safe `Show` + a per-client `Instance` set in OnEnabled, mounted once in Bootstrap
 on the `ui` GameObject next to ScreenFade/CeremonyScreen.** The static API no-ops when
 `Instance` is null (menu/headless), so callers never guard. Gate a per-player banner on
 `Character.Instance == caught` (the local non-proxy) so only the affected client sees it, same
 as the catch fade. `BuildHash` must cover every field the markup reads (the phase/flag) or
 the panel goes stale.
- **A swing/grab anchor that needs visible dressing (so a "no invisible grab points"
 audit passes) should get a RENDERER-ONLY visual with NO collider at all, not a
 collider-bearing prop placed carefully clear of the swing arc.** The swept radius of
 a pendulum/spin grab isn't an authored fixed number (depends on player momentum), so
 reasoning about where its arc passes to dodge a new collider is fragile; a helper
 that creates a `ModelRenderer` (+ `NoShadow`) and skips `BoxCollider` entirely makes
 "cannot intrude the swing volume" true by construction. Grab/swing audits (this repo's
 `AuditGrabElements`) only require a live renderer within radius — never a collider —
 so this costs nothing functionally.
- **Custom components in scene JSON**: `__type` is the plain class name when the class
 has no namespace (e.g. `"GameBootstrap"`, `"GolfHole"`). Keep bootstrap-referenced
 classes namespace-free.
- Scene JSON details: positions/rotations are strings (`"x,y,z"`, quat `"x,y,z,w"`),
 every GO/component needs a unique `__guid`, `Tags` are comma-separated. `IsTrigger`
 colliders + `ITriggerListener` for volumes.

## Component lifecycle

- **`OnAwake` fires synchronously inside `Components.Create<T>`**, before the calling
 code's next line runs. Any spawn helper that does
 `var c = go.Components.Create<Foo>; c.SomeProperty = x;` has already run `OnAwake`
 with `SomeProperty` at its default — derive per-instance state (hashes, seeded timers,
 waypoint indices) from `[Property]` values in `OnStart` instead, which runs on the first
 enabled frame, safely after the spawn helper's synchronous property assignments land.

- **Session-reset for STATIC-ONLY facades (no component of their own): ping their
 `ResetForNewSession` from a boot singleton's `OnAwake`, NEVER its `OnStart`.** Statics
 survive Play→Stop→Play in one editor process, so facades like an Sfx loop registry / a
 scene-scan cache / an item-holder set need a once-per-session clear. The hook ordering is
 load-bearing: `OnAwake` runs synchronously at the `Components.Create` line inside
 Bootstrap's own OnStart (i.e. BEFORE Bootstrap's later lines start this session's loops/
 registrations), while the singleton's `OnStart` is deferred to frame 1 — AFTER Bootstrap
 already started them — so a reset there wipes the fresh session's state it was meant to
 protect. Also reset in the right ORDER of ownership: clearing a shared registry (Sfx loop
 dict) that a peer's still-set one-shot flag guards (WandererNpc's `_plazaMurmurStarted`)
 leaves flag and registry disagreeing → the guarded loop never restarts; reset the flag and
 the registry at the same boundary.

- **Owner-simulated character spawn: implement `INetworkListener.OnActive(Connection)` on a
  host component and `go.NetworkSpawn(channel)` there.** `OnActive` fires for the host's OWN
  connection (#0) too (so the host gets a character), but `OnDisconnected` does NOT fire when
  the host itself leaves — only when a remote peer drops. The engine calls
  `INetworkListener` methods only on the host, so no `Networking.IsHost` guard is needed.

## Runtime & movement

- **A collider that co-moves with a swing arc is an invisible wall the swing hits every
 revolution, eating all speed.** one project's freestanding gym-bar spawned the whole frame
 model with a bounds `BoxCollider` (Prop's default) — the 0.7 m giant-swing circle around the
 crossbar clipped that box each turn, killing momentum ("I get stuck on it"). Fix: frame model
 `collide:false` + TWO slim static POST colliders at the uprights (offset along the frame's
 local ±X by `Model.Bounds.Size.x*0.5*scale`, ~0.15 m section, base→crossbar height), clear of
 the spin plane. Same reason swing-rope KNOTS/TIRE tips stay collider-less — a grabpoint is read
 by TAG (`NearestGrabpoint`), it is a route piece, not a wall; a collider riding the player's
 grip while held (and sweeping the arc while idle) recreates the trap.
- **Never teleport a body "over" geometry by a fixed offset — resolve the landing with a
 down-trace first.** Per-poly (`PhysicsMeshFile`) collision is a ONE-SIDED CONCAVE SHELL:
 backfaces don't collide, so a body placed even a few cm past the surface free-falls INSIDE
 the mesh and settles there with nothing to push it out (no StartedSolid either — a mesh
 interior is not "solid", only the surface skin is). A climb-mantle that blindly stepped
 +0.4 up / 0.4 inward (safe over a convex box wall) trapped the player inside a tapered
 stump. Fix: sweep DOWN from the intended arc apex, require a walkable hit (normal.z >= 0.6,
 not StartedSolid), land ON the hit or refuse; belt-and-suspenders: a trace-evidence
 inside-the-shell eject invariant (surface found clearly OUTSIDE the body's own radius at
 ankle height -> snap out + rate-limited warn).
- **A trace-based kinematic controller has NO collider component, so trigger volumes +
 `ITriggerListener` never fire against it.** Pickups that "OnTriggerEnter when the player
 walks in" silently never trigger. Fix: distance-poll each fixed tick against the player
 singleton (`Character.Instance.WorldPosition.Distance(WorldPosition) < radius*M`) and consume
 on proximity — no collider, no trigger.
- **Trace-based movement can trap the player permanently.** If the position ever overlaps
 a collider (slide clipping, or a building placed on top of the player), every trace
 reports a hit and movement zeroes forever. Fix: check `tr.StartedSolid` and ignore
 collision that frame so they can walk out; and forbid build placement within the
 structure's footprint of the player.
- Trace API that works: `Scene.Trace.FromTo(a,b).Radius(r).IgnoreGameObjectHierarchy(go)
 .WithoutTags("player","ghost").Run` → `.Hit`, `.Normal`, `.StartedSolid`.
- **`Jump()` on the controller clamps against rising velocity** and silently no-ops —
 for double jumps set `Velocity` z directly.
- **Suspension forces along the contact normal, not body-up**, or a tilted vehicle
 pushes itself sideways.
- Don't smooth longitudinal slip (adds lag/surging); do lightly smooth lateral slip.
 Shift on ground-speed-implied RPM, not engine RPM, to stop gear hunting.
- Runtime meshes: `Mesh` + `Model.Builder.AddMesh.AddCollisionMesh`; if winding is
 ambiguous (Clipper2 + earcut), emit triangles double-sided. Yield with
 `await GameTask.Yield` every N items to keep loading screens alive.
- **A trace hit exposes the physics body**: `tr.Body` (a `PhysicsBody`, null when the hit
 had no body), `tr.Body.BodyType == PhysicsBodyType.Dynamic`, `tr.HitPosition`,
 `tr.Shape`, `tr.Collider`. Push a dynamic prop the player walks into with
 `tr.Body.ApplyForceAt(tr.HitPosition, dir * forceN * M)` — force units are engine
 (kg·units/s²), so scale SI Newtons by M. Fixed force + `MassOverride` mass = light
 props fly, heavy ones barely move (F=ma).

- **NOCLIP in a trace-based kinematic controller is a STATE, not a collider toggle.** A
 hand-integrated controller (Character) has NO collider component of its own — collision lives
 entirely in the sliding mover's traces. So "disable the body collider" is a no-op; the whole
 noclip mechanism is a `CharacterState.Noclip` whose tick INTEGRATES position directly
 (`WorldPosition += vel*dt`) and skips gravity, MoveWithSlide, AND StickToGround — that's what
 phases through glass/walls/terrain. Fly camera-relative on YAW ONLY (`Rotation.FromYaw(camYaw)`,
 not full look rotation) so forward flies level regardless of look pitch. The character flies and
 the normal chase-cam follows it — this is DISTINCT from the FreeCamera (which detaches the camera
 transform and leaves the body). Un-stuck on exit: toggling OFF inside geometry would trap the
 trace mover forever (every trace `StartedSolid` → movement zeroes), so step the body UP until a
 down-cast no longer starts solid (capped), then return to Air. Break every orthogonal system on
 enter (drop prop, clear stance, release swing rope + tail-hook, zero charge) or stale attach
 state leaks across the toggle. Input audit BEFORE picking the key: keyboard "b" was free (pad B
 is PlayDead, keyboard PlayDead is X).
- **A "which movement mode does this surface allow" gate is a TAG-FAMILY split, not one tag.**
 Wall-run needed to fire on the area glass while Climb stayed off it. Solution: two tags —
 "climbable" (trees: Climb + WallRun) and "wallrun" (glass/back-wall: WallRun ONLY). Probe once
 for EITHER tag, then read which families the hit carries (`wallrunOnly = hasWallrun &&
 !hasClimb`); the sprint-speed WallRun branch fires on both, the walk-into Climb branch bails on
 `wallrunOnly`. Carry the surface class INTO the state (`_wallRunClimbable`) so the timeout-exit
 differs: a wall-run that times out on a wallrun-only surface drops to Air (no scalable wall for
 the hands to catch), only a climbable surface catches into Climb. Re-attach probes during the run
 accept either family; the Climb state's own re-probes stay strictly "climbable" (glass is never a
 Climb surface).
- **Rigidbody component API**: `.Gravity`
 (bool), `.MassOverride` (kg, set-only override), `.Mass` (kg, read), `.Velocity`,
 `.MotionEnabled`, `.PhysicsBody` (nullable → `.MassCenter`, `.AutoSleep`),
 `.ApplyForce(force)`, `.ApplyForceAt(pos, force)` (whole-step), `.ApplyImpulseAt`.
 A dynamic prop = ModelRenderer + non-static BoxCollider (`c.Static = false`) + Rigidbody.
 A drag-toward-hold-point spring: `force = offset * K * body.Mass`, cap magnitude so heavy
 props resist a single puller.

- **A single-tick GroundCheck flicker re-fires landing visuals mid-run.** A trace-based
 ground controller that, on a failed GroundCheck, flips to Air and runs the Air tick in
 the SAME fixed step will pulse `JustLanded` again the instant the next GroundCheck
 passes — so crossing a seam/step at speed machine-guns the land squash and reads as
 "bouncing / not smooth". Fix in the VISUAL only (leave the controller identical): track
 continuous air time and require ≥0.1 s airborne before a `JustLanded` counts as a real
 land to squash. Capture the air time BEFORE resetting it — JustLanded pulses on the
 frame state is already back to Ground.
- **A trace ground-snap that ADDS a fixed offset in its "buried" branch IS the bistable
 z-pop, even though the normal branch is idempotent.** one project's bodyZ flickered exactly
 ±~Skin (0.026↔0.056 m) at a run on flat ground. Root cause: a single-tick GroundCheck miss
 over a seam flipped Ground→Air→Ground in ONE fixed step; the in-step Air excursion (gravity +
 a MoveWithSlide) left the body slightly buried, so StickToGround took its `StartedSolid →
 WorldPosition += Up*Skin` branch — a FIXED ADD, not an absolute snap. Add-then-snap-back each
 alternate step = bistable by exactly Skin. Two-part fix: (1) before TickGround drops to Air on
 a failed GroundCheck, DEEP-probe down by a step-down tolerance (0.18 m) — ground right below =
 a seam/step, stay grounded, never enter Air; only a real drop becomes a ledge fall. (2) Make
 the buried branch re-probe for the true ground top and snap to `groundTop + Skin` (absolute,
 idempotent) instead of the additive bump. Keep the stick-reach ≥ the step-down tolerance or a
 step the step-down accepts sits beyond the stick's reach and the body floats.
- **On ROLLING slopes an idempotent ground-snap still POPS — rate-limit the DOWNWARD snap.**
 one project added noise hills (±2.5 m / 22 m ≈ 13° slopes) and telemetry lit up with a
 jittery snap train: all `cause=stick` (not the fixed `stick-buried` bistable), all NEGATIVE,
 magnitude GROWING with horizontal speed (−1..−3.6 cm/step at 5 m/s). Cause: `TickGround`
 integrates a purely-horizontal delta, projects onto the ground plane using the normal at the
 STEP-START, but the slope curves away within the step → the body ends slightly above the true
 surface at the new XY → StickToGround TELEPORTS down. The value is right; the discontinuity is
 the pop (and the visual rides the body, so bodyZ jitter = render jitter). Fix: snap UP
 instantly (never sink → StartedSolid next trace) but ease DOWN at a bounded glue rate
 (`StickDownGlue` 3 m/s → 6 cm/step @50 Hz). SIZING RULE: the glue must exceed the real
 per-step slope drop at TOP speed (RunSpeed × maxSlope × dt, worst observed −3.6 cm) or genuine
 descents lag → floor-HOVER; it only shaves the frame-to-frame jitter. A real step-down
 (≤ step-down probe) still resolves in ~3 steps, faster than gravity would drop the body, so no
 visible float, and GroundCheck's own reach keeps the eased body grounded. Rate-limit the
 APPLIED move, NOT the snap target (the target is already idempotent — hysteresis on it just
 masks the signal).
- **`StickToGround` snapping z to `trace.EndPosition.z - r + Skin` is idempotent on flat
 ground and does NOT oscillate** — the snap target is a function of ground height, not of
 current z, so it converges to `groundTop + Skin` and stays. If a run looks bouncy, the
 bounce is the CLIP's authored pelvis bob (visual child z), not the controller — confirm
 by logging controller `WorldPosition.z` vs the visual child's world z separately; a flat
 bodyZ with an oscillating visZ isolates it to the clip. Don't add position hysteresis
 speculatively — it masks the very signal that tells you which layer bounces.
- **A candidate SELECTOR's "nearest-in-reach fallback" silently defeats any exclusion above it.**
 one project's swing re-grab kept snapping back to the just-released rope despite a re-grab
 exclusion window: the selector excluded anchor A, but a trailing
 `if (best==null && nearest in reach) best=nearest` used the *pure unfiltered* nearest — which was
 A. Mid-flight toward B (B not yet in reach), the exclusion nulled `best` → the fallback handed A
 right back. Fix: make the fallback the ONLY recovery path and gate it on "EVERY real candidate was
 hard-excluded," not "best came out null." For grab/target scoring that blends 3+ signals
 (proximity + velocity-alignment + look-alignment + recency), use an ADDITIVE score of normalized
 [0,1] terms so the weights ARE the blend and are directly comparable — far easier to tune than
 multiplicative distance-scaling. Track recency as a PER-ANCHOR ring buffer of release timestamps
 (not a single last-slot) so a chained A→B→C release still penalizes early links; hard-exclude for
 ~the flight time, then a linear decay penalty.
- **Orbiting the physics ROOT around a bar makes the model's HANDS trace a circle, not the bar.**
 A gymnast bar-spin placed the controller root at `anchor + radial·BarSwingRadius` (0.7 m); the
 rendered mesh drawn at the root put the hands (model top, ~0.5 m up the root→anchor axis) ~0.2 m
 off the bar, orbiting it ("spins an inch around where it should"). Fix is VISUAL only: while
 bar-swinging, lift the rendered mesh UP the root→anchor axis by ~BarSwingRadius so the hands weld
 to the bar and the body sweeps around them — physics (root orbit + angle integration, release
 tangent, arc size) is untouched.
- **Invisible "grab point" registration = phantom spin element; add a load-time visual audit.** A
 grabpoint-tagged anchor whose intended dressing model didn't spawn still registers as grabbable →
 the player grabs and spins on nothing. Audit at load (after ALL builders run): every grabpoint
 must have a live-model renderer on itself/descendants OR within ~1.2 m (bar anchors are
 intentionally invisible; the visual is a separate nearby Prop). Log count + name each offender.
 Build the DETECTOR rather than guessing — if the models compile (`.vmdl_c` present) the "stray
 dev cubes" a screenshot shows are usually intentional TINTED Pushable/dev boxes, not load
 failures.

## Input

- **`Input.UsingController` is a real public bool** (verified by grepping
 `Sandbox.Engine.dll`'s metadata strings for `<UsingController>k__BackingField` next
 to `UseController`/`ignoreController`/`oldUsingController` — a standard auto-property
 backing field, and `dotnet build` resolves `Input.UsingController` with zero errors).
 Use it to gate pad-only feel tweaks (e.g. a bigger look-sensitivity multiplier only
 while on a gamepad) without a per-device AnalogLook split, which s&box does not
 expose. `ControllerLookPitchSpeed`/`ControllerLookYawSpeed` also exist as engine
 ConVars (getter+setter with `ConVarAttribute`) — those are the user's own
 sensitivity settings, not something game code should read/override.
- **Gamepad bumper GamepadCode strings are `"SwitchLeftBumper"`/`"SwitchRightBumper"`**,
 not `"LeftShoulder"`/`"RightShoulder"` — confirmed consistent across all 6 project
 Input.configs on this machine. Menu/back buttons are `"SwitchLeftMenu"`/`"SwitchRightMenu"`. Other
 verified GamepadCode values in use: `"A"`, `"B"`, `"X"`, `"Y"`, `"LeftTrigger"`,
 `"RightTrigger"`, `"LeftJoystickButton"`, `"RightJoystickButton"`, `"DpadNorth"`,
 `"DpadSouth"`, `"DpadEast"`, `"DpadWest"`, `"None"`.
- **New input actions added to `Input.config` don't register until the editor
 restarts** — a headless `dotnet build` succeeding does NOT mean `Input.Pressed("New
 Action")` will fire in a running editor session; it needs a Play/editor restart to
 pick up the new action list.

- **A spin bar's release can only aim within its spin plane — yaw chain bars INTO their
 outgoing travel bearing, and beware the TWO yaw conventions.** `SwingBar(yaw)`'s plane
 CONTAINS horizontal bearing = yaw (box long axis = local Y rotated by yaw); but
 `GymBar`/`HungSpinBarStation(yaw)` pass yaw+90 to the anchor, so their plane contains
 bearing yaw+90. A cap computed against the wrong plane ("0.94", really 0.34) tuned a
 release gate above the geometric ceiling — the release never fired and every flight fell
 back onto its source bar. Validate any computed cap against one LOGGED release-align line
 (bar_7→rope_east: computed 0.57, released 0.56) before tuning gates to it. Rotating a bar
 is free placement: positions unchanged, reach audits unaffected.
- **Rest-position spacing cannot clear a SWINGING rope/tire neighbour — its knot occupies
 the whole swing sphere.** A tire knot on a 3.0 m rope whose REST point sat a "safe" 3.3 m
 from a trapeze chased an airborne character to within ~1.4 m at full extension and stole the
 grab. Clearance metric = |ropeAnchor − target| − ropeLength (keep ≥ ~2 m), never
 |knotRest − target|. Same "measured, not authored" family as the footprint rule, applied
 to motion.
- **Proof-grade aimed-bot grab window: w ≤ D(nearest thief) − GrabRadius.** A window sized
 only to the equidistance midpoint still lets the selector SEE the thief; sizing it so the
 thief sits beyond hand reach (2.6 m) at every hand-open moment silences it entirely. For
 a target directly ABOVE its own launch bar, additionally require the window to open above
 the height crossover (w < targetZ − midpointZ), or the bar below stays distance-dominant
 for the whole climb.
- **Climbable stair-step rises ≥ ~1.1 m are a mid-air Climb-catch coin flip** with
 JumpVelocity 5.5: z(0.25 s) = 1.07 m, and 0.25 s airborne is exactly when
 the controller's `TryEnterClimb` arms — whether the arc clears the next platform's face before the
 arm depends on centimetres of launch position. Uniform scale-to-height platforms worsen
 it (a 3.5 m-tall platform is ~3.7 m WIDE — faces nest into the previous top). Keep
 scripted-jump stair rises ≤0.9 m or budget for the recovery loop burning step timeouts.
- **Gamepad triggers DO have a public smooth 0..1 analog read —
 `Input.GetAnalog(InputAnalog.LeftTrigger)` / `InputAnalog.RightTrigger`.** The `InputAnalog`
 enum has explicit per-axis members (`LeftStickX/Y`, `RightStickX/Y`, `LeftTrigger`,
 `RightTrigger`) — there is no `InputAnalog.Move` member. What is digital-only is a *named
 `Input.config` action* bound to a trigger: that reads on/off via `Input.Down/Pressed/Released`,
 no pull value. The analog axis is a SEPARATE surface, read directly off the physical trigger,
 independent of any config-action binding. **Whitelist-VERIFIED** — a real game build of
 `Input.GetAnalog(InputAnalog.RightTrigger)` compiles clean through the `Sandbox.Generator`
 access analyzer. Returns `0` unless `Input.UsingController` (safe to MAX-blend with keyboard),
 and the engine pre-applies a 12.5% deadzone so resting triggers can't creep. Use for variable
 throttle/brake: `throttle = Max(keyboardForward, GetAnalog(RightTrigger))`.
- **Deriving vertical "skirt" quad winding from a verified TOP-face convention:
 pick per-wall axes (u,v) so u×v equals the wall's outward normal, then reuse the
 identical index pattern.** ⚠ SUPERSEDED IN PART: the concrete `{a,c,b},{b,c,d}`
 pattern this bullet used as its base was later PROVEN INVERTED on engine 26.07.08e
 (see the correction bullet below — the working pattern is `{a,b,c},{b,d,c}`, plain
 CCW). The u×v=outward-normal DERIVATION METHOD here remains valid and is exactly
 why the whole mesh stayed self-consistent (every face inverted together, one flip
 fixed all five orientations at once). Original context: one project's TerrainBuilder
 only ever proved winding for one orientation (up-facing: a=(i,j) b=(i+1,j)
 c=(i,j+1) d=(i+1,j+1)).
 the project's VoxelMesher needed FOUR more orientations (vertical walls on a
 stepped voxel column) with no shipped precedent to copy. Rather than guess-and-
 screenshot per wall, treat the proven top-face rule as an algebraic IDENTITY: for
 the top, u=+X, v=+Y, and u×v=+Z is exactly the face's outward normal. So for any
 other face, choose horizontal edge-direction u and vertical v=+Z such that u×v
 equals the desired outward normal N — solved directly via u = rotate(N, +90° about
 Z) = (-N.y, N.x, 0) — then reuse the SAME {a,c,b},{b,c,d} index pattern with
 a=(u0,v0) b=(u1,v0) c=(u0,v1) d=(u1,v1). This gave four internally-consistent wall
 quads (south N=(0,-1,0)→u=+X, north N=(0,1,0)→u=-X, east N=(1,0,0)→u=+Y, west
 N=(-1,0,0)→u=-Y) purely from algebra, with no per-wall trial and error. General
 rule: when a codebase has ONE verified winding convention for ONE face orientation
 and you need MORE orientations, don't re-derive winding from scratch by staring at
 a cross product — treat the known-good case as pinning the u×v=normal relationship
 for THIS engine's front-face convention, then solve for u on every other face.
- **The "verified up-facing winding {a,c,b},{b,c,d} — do NOT fix" lore is NOT portable;
 on engine 26.07.08e it rendered EVERY face inside-out in a fresh transplant.**
 the project's VoxelMesher copied the pattern byte-identically from one project's
 TerrainBuilder (same a=origin b=a+X c=a+Y d=a+X+Y layout, same index order, same
 single-sided complex.shader, all transforms scale (1,1,1), Tuning.M=39.37 checked) and
 the MCP editor camera proved tops rendered FACE-DOWN: the whole plain + terrace tops
 solid green from BELOW, absent from every above viewpoint; after flipping tops only,
 near-side skirt walls showed as see-through sky slits (the "solid silhouette from
 outside" you see pre-fix is the FAR wall's inner face — it masquerades as correct
 walls). Corrected rule that works here: for a=origin, b=a+u, c=a+v, d=a+u+v the
 front-facing pattern is {a,b,c},{b,d,c} with front = u×v (plain right-hand CCW —
 no "engine treats CW as front" exception). Do not trust ANY winding lore across
 projects/engine builds: the 60-second empirical test is screenshot from above +
 screenshot from below (tops visible only from below = flipped), via set_editor_camera
 + editor_camera_screenshot.
- **The editor MCP port is ONE engine-global preference (`config/tools.json McpServerPort`),
 last editor to set it wins, and the editor AUTO-INCREMENTS past a taken port.** With several
 editors open every port is launch-order-dependent — don't pin fixed port numbers, DISCOVER
 them dynamically and identity-probe. Before ANY mutating call, identity-probe the endpoint:
 `editor_status` must name the expected Project AND `search_tools` for a project-defined
 `[McpTool]` prefix must hit — the project name alone can go stale when owners reshuffle ports.
 If the settings page (Editor Settings → MCP Server) shows Enabled checked but "Not running",
 toggling the checkbox off/on restarts the listener.
- **The s&box MCP tool registry is two-layered: `tools/list` exposes only ~7 entry-point
 tools (editor_status, read_console, search_tools, list_toolsets, describe_toolset,
 call_tool, call_tools); every real engine/project tool is invoked THROUGH `call_tool`
 with {name, arguments}.** Transport is stateless HTTP POST (JSON-RPC tools/call, no
 session/initialize needed). Two return-shape facts: an [McpTool] returning a JSON
 string is NOT double-encoded (the string lands verbatim as the text content block —
 one json.loads gives the object), and screenshot tools return an MCP image content
 block (content[0] = {type:"image", data:<base64 png>, mimeType}) — not a JSON field.
- **Edit-mode `scene_trace` is blind to runtime-built ModelColliders** — chunks freshly
 created by an editor-scene regeneration (ModelRenderer + static ModelCollider via
 Model.Builder.AddCollisionMesh) render fine and list in scene_tree, but a scene_trace
 ray straight through them reports Hit=false in edit mode. Don't use edit-mode traces
 as geometry evidence; trust screenshots (or play mode) instead.
- **A root GameObject named `editor_camera` (bare CameraComponent) appears in the open
 scene once the MCP editor-camera machinery runs** — engine-managed live-session
 artifact, NOT in the .scene file, clones into play sessions as a second enabled
 camera. Harmless so far (the real scene Camera wins the render), but expect it in
 scene_tree/find_game_objects output and don't save the scene assuming the tree is
 clean.
- **`Mouse.Visible = true` is past "obsolete but functional" — migrate to
 `Mouse.Visibility = MouseVisibility.Visible/Hidden`** (engine XML: "Use
 Mouse.Visibility instead"). It raises CS0612 in the fresh in-editor compile, and the
 whole-tree 0/0 gate stays red until migrated; one project already migrated
 (a tool camera/EscapeMenu). Companion play-mode note for cursor-driven tool cameras:
 editor keyboard/mouse input reaches one project only while the game viewport has FOCUS —
 "camera dead in play mode" is usually an unclicked viewport, not an input-API bug
 (verify attachment headlessly via find_game_objects component=<CameraDriver> before
 suspecting code).
- **Verify a mesh-import scale pipeline in-engine with a spawned 1 m REFERENCE CUBE, not
 by eyeballing a lone prop.** `models/dev/box.vmdl` is a 50-unit, center-origin dev cube;
 spawn it at `WorldScale 0.7874` for exactly 1 m (0.7874×50 u = 39.37 u = 1 m) and, since
 it is center-origin, ground its base by placing the object at `z = 0.5 m = 19.685 u`
 (props exported grounded at z=0 sit at z=0). Put the cube and prop at the SAME y (equal
 camera depth) with a LEVEL camera (pitch 0, yaw ±90) and measure the pixel-height ratio —
 perspective and vertical foreshortening then cancel. This confirmed the project's
 `pine_large` renders ~6.1× the cube (target 6.0 m), i.e. the meters-authored Blender OBJ
 → `import_scale = 39.37` path delivers EXACT in-engine metres with no per-prop fudge.
 A far camera makes a small cube unmeasurable (±3 px on a 30 px cube = ±0.6 in the ratio) —
 frame it to fill a good fraction of the shot.
- **`wb_generate` leaves a transient `wb_world` terrain GameObject in the open scene — it
 is a STEP-TERRACED diorama, so props spawned for a clean side-by-side verification land
 on it at random heights (float/sink), not on your own flat floor.** Before a prop-audit
 loop, `set_game_object {enabled:false}` on `wb_world` (don't delete — it's session-
 transient and regenerated), spawn your own flat floor (a scaled `box.vmdl`), do the
 shots, then re-enable it to leave the editor as found. Also note `find_game_objects`
 returns `{"Total":N,"Results":[…]}` (objects under `Results`, each with `Id`/`Name`),
 NOT a bare list — and its `name` filter is a substring, so a `"wb_"` query also matches
 `wb_world`; filter by exact prefix before deleting so you don't nuke the terrain root.
- **A freshly generated `.vmat`/`.vmdl` batch that has NEVER been compiled must be
 `asset_compile`d over the MCP before spawn — but a successful compile returns
 `{"Success":true, "CompiledFile":"…"or""}` where `CompiledFile` is often an EMPTY string
 even on success** (it only fills in when that call actually did the compile vs. finding it
 already up to date). Gate on `Success`, never on a non-empty `CompiledFile`. All 26
 the project starter-prop vmdls + `atlas.vmat` + a flat vmat compiled Success on first
 try with zero material/remap defects (the both-names remap rule + white-tex+g_vColorTint
 flat recipe held).
- **A low-frequency "mountain-mass" mask at wavelength >> world width makes the WHOLE
 diorama sample one point on the mask → the terrain reads uniformly flat OR uniformly
 mountainous by pure seed luck, with no apron↔massif split.** M2's HeightPass first used
 massScale = 1.5× world width (per an over-eager scope note); across the 192 m world that
 is <1 wavelength, so seed 1337 landed the entire 384² world below the mountain threshold
 → a dead-flat green plain (2 m everywhere) despite a 35 m amplitude. The mask must have a
 wavelength COMPARABLE to (a bit shorter than) the world — massScale ≈ 0.7× world width
 (~1.5 wavelengths across) — so it actually transitions apron→massif within the frame. To
 make the composition reliable regardless of seed (reference art wants massif-in-back /
 apron-in-front), blend the noise mask with a positional back-corner gradient
 (0.55·noise + 0.45·biasToFarCorner) before the smoothstep; the far corner is +x,+y for the
 standard hero_iso camera at (-0.85w,-0.85w,+0.6w). Diagnostic: a flat world from every
 angle with non-trivial amplitude ⇒ suspect the mask range, not the octaves.
- **Greedy meshing delivers only ~1.4–1.8× tri reduction on fine-grain dithered voxel
 terrain — NOT the 5–15× that flat-terrace scope estimates assume.** Two compounding
 reasons at 384² @ 0.5 m: (1) real ridged/warped height has few adjacent cells at the exact
 same integer step, and (2) the pixel-art per-cell material DITHER (hash picks
 GrassLight/GrassDark/Sand per cell) means even a perfectly flat plateau splits into
 single-cell tops because the MERGE KEY is (step, material) and the material differs
 cell-to-cell. Net: mixed_reference 312k, alpine 459k, desert 225k render tris — all under
 the 500 k budget, but alpine is close. The dither-vs-merge tension is fundamental: if the
 budget ever fails, dither material at a coarser granularity (e.g. per 2×2 block) to restore
 large same-material runs, or drop skirt-material from the merge key. Census the greedy
 efficiency every rebuild so a regression that tanks it is visible.
- **Constant per-face atlas UV is a positive trick: give every vertex of a merged face the
 SAME cell-center UV and the GPU keeps mip 0 forever (zero UV derivatives) → crisp flat
 pixel color on arbitrarily large merged quads, zero atlas-cell bleeding, one draw call per
 chunk.** This is what lets a strata palette atlas (8×4 grid of 16 px cells) survive greedy
 meshing without the classic "distant merged quad mip-averages into a neighbouring atlas
 cell" artifact — the artifact needs a nonzero UV gradient across the face, and a constant
 UV has none. Pair with the darkened-row variant (CellCenterUv(cell+16)) for skirt fake-AO.
- **A per-cell hash DITHER on elevation-band edges is what turns a strata table from "hard
 topographic contour lines" into the pixel-art salt-and-pepper transition — and pairing it
 with an ABSOLUTE-height alternate-shade band (swap to the band's darker/lighter twin every
 N metres) is what makes voxel cliff faces show horizontal strata striations like the
 reference.** Two independent effects, both needed: dither jitters the band THRESHOLD per
 cell (±half a band) so the boundary is grainy in plan view; the alt-shade band keys off
 floor(height / period) so a vertical cliff face reads banded in elevation view. Missing the
 first gives contour maps; missing the second gives flat-colored cliffs.
- **A translucent water film over BRIGHT WARM terrain desaturates to muddy grey, not blue —
 and a low-roughness (glossy) water surface catches the grey-blue sky as specular and greys
 it further.** M3's first water.vmat (tint blue, TextureTranslucency 0.55 = 55% opacity,
 roughness 0.15) rendered the lakes flat lavender-grey: 0.55·blue + 0.45·(204,173,117 sand)
 blends to ~(113,124,131), and the glossy sheen added sky-grey on top. Two fixes together got
 a pleasing pixel-art blue that still shows the bottom: raise opacity to ~0.80 (blue dominates,
 a faint bottom still reads at shallows) and raise roughness to ~0.45 (semi-matte, so the tint
 reads true instead of mirroring the sky). General rule for flat translucent overlays on a
 warm palette: opacity ≥ ~0.75 or the color muddies, and keep it semi-matte unless you
 actually want a reflective sheen. The glass_clear recipe (white.png + g_vColorTint +
 g_flModelTintAmount 1 + F_TRANSLUCENT 1 + TextureTranslucency-as-opacity) needs NO RGBA png.
- **Priority-flood depression fill on noisy terrain floods EVERY enclosed pit → a dry world
 gets speckled with spurious 1–3-step puddles; the fix is to treat SEA and above-sea LAKES
 differently, not a global depth threshold.** A plain Barnes priority-flood (water = min over
 paths to edge of max terrain along the path, floored at sea level) correctly makes oceans AND
 mountain tarns, but keeps every shallow local minimum as a tiny lake. A blanket min-depth
 threshold can't separate "wanted" from "unwanted" because a coastal shore is ALSO shallow.
 The load-bearing distinction: water whose surface is at/below the sea-level slider is SEA (the
 user's "amount of water" dial — always keep it), water perched ABOVE sea level is a depression
 LAKE (keep only if it clears MinLakeDepthM, e.g. 1 m). This one rule makes a sea-0 arid spec
 bone-dry while a sea-+6 spec keeps its whole ocean, from the same flood.
- **A sea-level slider does nothing until it exceeds the terrain's APRON FLOOR — and a layered
 HeightPass floor is rarely at 0.** the project's HeightPass eases the diorama edge down to
 plainH = baseH·plainFrac·amplitude, which at plainFrac 0.12 / amp 35 sits at ~2 m (range
 0–4 m), NOT ~0. So SeaLevel 0.5 floods nothing at the edge (no cell connects to the border
 below 0.5) → zero ocean; only interior basins that fill above 0.5 show, and those are the
 shallow lakes the depth guard removes. To get a coastline the sea level must exceed the apron
 floor (here ~2 m gave the intended "modest bay + beach"). Lesson: before picking sea-level
 spec values, know the actual MIN of your height field — an apron eased toward a nonzero plain
 height shifts the whole "water appears at" point up by that plain height.
- **Snow (and any climate band) must gate on ABSOLUTE altitude in metres, never elevation
 FRACTION (h / amplitude) — the fraction gate silently snows low-amplitude worlds.** M2 gated
 snow at StrataSnowFrac 0.82 of amplitude; on desert_mesa (amp 18) that is 14.8 m, so its
 16–18 m mesas got snow-capped — an arid desert with snow. M3 makes snow a BIOME keyed on
 absolute metres (moisture-adjusted snow line ~22 m), stored per-grid as SnowAltitudeM so a
 grid-only audit can assert zero snow when the world's max height is below it. Same trap
 applies to any "high/low" classification: fraction-of-amplitude couples the threshold to the
 amplitude slider and misclassifies at the extremes.
- **`System.Array.Clone()` is BLOCKED by the s&box whitelist, but the headless `dotnet build`
 does NOT enforce the whitelist — so a `(float[])arr.Clone()` snapshot compiles green offline
 and only fails on the in-editor compile (`SB1000: 'System.Array.Clone()' is not allowed when
 whitelist is enabled`).** M4's RiverPass/RoadPass snapshotted the heightfield with `.Clone()`;
 `dotnet build ... --no-incremental` was clean, then `compile_status` over the MCP showed 2
 SB1000 errors. Fix: a plain loop copy (`var c = new float[n]; for(i) c[i]=src[i];`) or
 `Array.Copy` — both whitelist-safe. LESSON: the headless build is necessary but NOT sufficient
 for whitelist safety; always gate on the editor's `compile_status` (bump mtime -> poll) before
 trusting a runtime pass. Prime suspects the headless build misses: `Array.Clone`, LINQ corners,
 reflection, various `System.*` helpers.
- **Headless `dotnet build` can report 0 errors while the in-editor Razor compiler has
 real `.razor` compile errors — it is not a substitute for `compile_status` for anything
 touching `.razor` files.** A `.razor` file with genuine CS errors built clean via
 `dotnet build` both before AND after the fix — the headless MSBuild path doesn't
 regenerate/validate the Razor-to-C# codegen the live editor's Roslyn compiler does.
 Plain `.cs` files still error correctly; the gap is specifically Razor codegen.
- **A hex hash constant with the top bit set (e.g. the golden-ratio `0x9E3779B1` = 2654435761)
 is a `uint` literal and will NOT assign to `const int` — CS0266.** Other seed offsets on this
 project (`0x51ED2701`, `0x6A09E667`) are < 2^31 so they slid in; the 32-bit golden ratio does
 not. Use `unchecked((int)0x9E3779B1)`. Cheap, but it stops a fresh build cold.
- **A monotonic invariant proven on a FLOAT construction can still be violated on the QUANTIZED
 grid the audit reads — enforce it on the final grid, not just at authoring.** M4 rivers clamp
 the water surface non-increasing downstream along the walk, but the channel is painted over a
 DISC (width), and where a meander brings a lower downstream disc adjacent to an upstream cell,
 min-painting lowers the upstream cell below its own downstream neighbour -> one river_monotonic
 offender out of ~600. Fix that makes the audit 0 BY CONSTRUCTION (not luck): after quantizing,
 relax along the stored upstream chain to a fixpoint (`if surf[cell] > surf[upstream]: lower it`;
 chains never cycle because upstream is always an earlier walk cell). General rule: if an audit
 reads quantized/painted state, satisfy the invariant on THAT state — a proof about the pre-
 quantize float field is necessary but not sufficient.
- **Nearest-centerline corridor stamping leaves a step DISCONTINUITY where two flattened
 corridors run adjacent at different heights — diffuse the target-height field before applying.**
 M4 roads flatten each cell to its nearest A*-centerline's smoothed height; where two corridors
 pass within a corridor-width on a slope, the seam cells snap to different centerlines and jump
 >2 steps, tripping road_slope. Fix: a few Jacobi passes over the target-height field (blend each
 road-influenced cell toward its road-influenced neighbours) before the flatten, so adjacent
 corridors grade into each other while the shoulder still eases to terrain. COMPANION LESSON: this
 offender only appeared AFTER a river-momentum tuning tweak rerouted A* through a new seam — any
 change that alters one pass's output can silently break a DOWNSTREAM pass's audit, so re-run the
 full audit suite after every tuning change, not just after touching the pass you edited.
- **Steepest-descent rivers stall into mid-slope tarns on a rugged/ridged crest; the fix is more
 MOMENTUM (plow through noise pits) + sources starting slightly BELOW the ruggedest peak — not
 more octaves or a deeper carve.** M4's first river_valley run reached the sea on only 2 of 4
 rivers; the other two dead-stopped in local minima on the snow crest and LakePass filled the
 terminal carved pit into a pond. Raising the previous-direction blend 0.62->0.70 and dropping the
 source-height gate 0.62->0.55 of max height tripled river-water cells (637->2044) and got all
 four to the coast — a river doesn't flow uphill, so blending in the prior direction (with the
 monotonic-floor carve notching through the bump) is exactly the physical behaviour. Diagnostic:
 short rivers ending in a small blue blob mid-slope = walk stalled, raise momentum before touching
 anything else.
- **`TextEntry.OnTextEdited` (an `Action<string>`) needs an EXPLICITLY-TYPED, BLOCK-bodied lambda
 — `t => _field = t` fails two different ways.** An untyped lambda (`OnTextEdited=@(t => _field =
 t)`) fails `CS8917: The delegate type could not be inferred` in the razor codegen (the in-editor
 compiler only — headless `dotnet build` doesn't catch it, see below). Adding an explicit param
 type (`OnTextEdited=@((string t) => _field = t)`) trades that for `CS0029: Cannot implicitly
 convert type 'Func<string,string>' to 'Action<string>'` — an EXPRESSION lambda with an assignment
 BODY gets inferred as returning the assigned value (a `Func`), not `void` (an `Action`), once the
 compiler has enough type info to try. Fix: explicit param type AND a block body so the assignment
 is a statement, not an expression: `OnTextEdited=@((string t) => { _field = t; })`. The other
 engine-source precedent (`CreateGameModal.razor`) already uses this exact explicit-type-plus-block
 shape — `(string x) => { Output.GameSettings[e.Name] = x; }` — so it's the house pattern, not a
 fallback. Also: `TextEntry`'s `Numeric` bool property needs `Numeric=@true` (a real C# expression),
 NOT `Numeric="true"` (a markup string attribute) — the latter fails `CS0029: Cannot implicitly
 convert type 'string' to 'bool'` in the same codegen pass.
- **Whitespace immediately adjacent to a tag/expression boundary in razor markup collapses to
 NOTHING — including `&nbsp;` (U+00A0 still satisfies `char.IsWhiteSpace` in .NET, so the collapse
 logic eats it too).** `chunks <span class="cval">@x</span> more text` renders as `chunks123more`
 — the literal space right before `<span>` and the literal space right after `</span>` both vanish,
 while a space in the MIDDLE of one uninterrupted text run (no tag/expression boundary crossed)
 survives fine. Same root cause bit a plain multi-expression markup line with no elements at all:
 `@_worldSize × @_worldSize` (two adjacent `@`-expressions with literal ` × ` between) also lost
 its spacing. Fixes, in order of preference: (1) collapse multiple `@expr`/literal fragments into
 ONE C# interpolated string — `@($"{_worldSize} × {_worldSize}")` — when no per-fragment styling is
 needed; (2) when a styled inner `<span>` genuinely needs breathing room from its neighbours, use
 CSS `margin` on the span's own class instead of a text-node space (`.cval { margin: 0 3px; }`) —
 box-model spacing doesn't go through the whitespace-collapse pass at all and is the only reliable
 fix once `&nbsp;` has already failed. HTML entities that aren't whitespace (`&middot;` etc.) DO
 decode and render correctly, so entities themselves aren't the problem — only whitespace-class
 characters are collapsed.
- **A per-cell WHITE-noise hash is the WRONG driver for pixel-art terrain shade choice — it reads
 as salt-and-pepper checkerboard, not "organic variation", AND it tanks greedy-mesh efficiency.**
 M6.5's owner defect: `hash = LatticeValue(x,y,seed); mat = hash<0.5 ? GrassLight : GrassDark`
 gave a 50/50 checkerboard across the whole apron ("very variable and very scattered"). The fix is
 a two-frequency split: drive the shade from a SMOOTH low-frequency value-noise PATCH field
 (`Noise.ValueNoise(wx,wy, ~15 m, seed)`) so you get large uniform meadow/dune patches with ONE
 dominant shade, and confine the per-cell hash to a NARROW feather band around each threshold
 (`hash < smoothstep(t-half, t+half, patchField)`) so ONLY the patch edges dither. This is the
 same "smooth field ± narrow hash dither" primitive for BOTH in-biome shade patches and
 material-to-material transitions; for transitions add mid-stop atlas cells and pick a stop from a
 smoothstep blend + hash jitter (`A -> A-blend -> B-blend -> B`, dithered only where 0.15<b<0.85)
 for a watercolor wash instead of a hard dithered contour. Because the merge key is (step,
 material), turning a 50/50 two-material checkerboard into large single-material fields DIRECTLY
 raises greedy efficiency — measured desert_mesa 1.9x->3.9x (render tris 223k->107k), mixed
 1.7x->2.1x, alpine 1.4x->1.6x, all at seed-stable determinism and audits still 0. Nuance vs the
 earlier M2 "dither+banding pairing" note: the ABSOLUTE-height alt-shade band that makes cliff
 faces show horizontal strata is still wanted and must stay keyed on RAW height (level striations);
 only the PLAN-VIEW per-cell dither was the defect. Keep the elevation-band THRESHOLDS wandering
 organically by comparing (h + a smooth low-amp noise perturbation) instead of raw h, so boundaries
 follow contours instead of snapping to iso-lines. Rule of thumb: any time terrain color is chosen
 per cell, ask "is the DRIVER smooth?" — if it's white noise, you'll get static; make the driver a
 low-freq field and let hash only break up threshold edges.
- **Regenerating the strata atlas PNG at a NEW cell-grid size (8x6 -> 8x8) is safe through the
 runtime ONLY because every UV/offset is derived, not hardcoded — verify that before resizing.**
 M6.5 appended 6 feather-band mid-stop cells, growing the atlas from 26->needs-4-rows. The append
 worked with zero runtime breakage because `WbAtlas.CellCenterUv` divides by `Cols`/`Rows` (const,
 regenerated) and `Darkened(cell)=cell+DARK_OFFSET` where `DARK_OFFSET = COLS*BASE_ROWS` is DERIVED
 in gen_assets.py (24->32 automatically). A grep for hardcoded `+24`/`8x6`/atlas dims across Code/
 confirmed nothing else pinned the old layout. TWO editor-side facts made the resize land cleanly:
 (1) the regenerated `atlas.png` needs the editor asset-watcher to recook its `*_png_*.vtex_c` —
 it did so within ~1 s (compiled vtex mtime > png mtime), NO manual asset_compile of the png
 needed (and `asset_compile materials/wb/atlas.png` actually errors "no source file / atlas.jpg"
 because the MCP asset lookup resolves the texture by a different key — compile the `.vmat`
 instead, which pulls the texture); (2) a stale `.vtex_c` at the OLD 128x96 size would have made
 the new 8-row UVs sample the wrong cells, so always confirm vtex mtime > png mtime after a
 resize.
- **Autopilot progress metrics must be state-gated** - sampling "max height gained" across a
 whole routine counts the ballistic kick-off apex as climb progress (gb_pilot_lab run 1 read
 7.2 m on a 4.1 m tower). Gate progress samples on the state that earns them (Climb/WallRun
 only).
- **The editor console buffer (2000 entries) rolls over during long pilot sweeps** - per-attempt
 telemetry floods it and read_console loses the report lines. Grep the DATED log file instead,
 and the live file is sbox-dev-2026-07-11.N.log (highest N), not necessarily sbox-dev.log.
- **Tower/platform geometry is not isolated from the swing web** - changing Tower B's step
 layout changed the bar10 approach -> tire_w catch dynamics -> residual tire swing at the
 bar_11 release -> a wrong-grab that had never occurred in 7 runs. Any platform move feeding
 a swing chain needs FULL-suite verification, not just its own routine.
- **A NEW `*.razor.scss` created while the editor is already running does NOT get compiled/applied
 until the editor restarts — the panel COMPONENT runs fine, it's only unstyled.** Symptom: a new
 PanelComponent's `OnStart`/`OnTreeBuilt` both fire (code is live, panel IS in the render tree) and
 INLINE styles render (a `<div style="...left:500px...background:red">` shows), but nothing driven by
 the sibling `.razor.scss` applies — so the root's `width:100%`/`height:100%` never take, the root
 auto-sizes to content, and any `right:Npx`-anchored child lands off-screen (measured from a
 zero/narrow root's right edge). Editing/renaming/`@attribute [StyleSheet]`/touch-triggering the scss
 in-session all FAILED to make the running editor pick it up (razor recompiles many times, scss stays
 stale). Same family as "new vmdl/regenerated texture needs an editor kick." DIAGNOSIS RECIPE that
 isolates it in minutes: (1) add `Log.Info` to the panel's `OnStart`+`OnTreeBuilt` — if they fire, the
 code is live and it's NOT a stale-assembly/compile problem; (2) put an INLINE-styled box at `left:Npx`
 (not `right:`) — if it renders, the render pipeline works and the ONLY missing piece is the scss.
 Fix for the deliverable: the scss is correct and applies on the next fresh editor start (like every
 other panel in the project); to make a panel usable IN-session without the scss you'd have to set the
 root style in C# (`Panel.Style.Width = Length.Percent(100)` in OnTreeBuilt) — but children still need
 their own styling, so a restart is the clean answer.
- **A stylesheet with MANY selectors simultaneously declaring `font-size` (and/or
 `letter-spacing`) can corrupt UI TEXT GLYPH RENDERING for the WHOLE PANEL** — text
 draws as solid filled blocks (correct layout width, wrong glyph fill) instead of
 legible characters. A handful of `font-size` declarations is fine; roughly a dozen
 across one panel breaks every styled element. Carry visual hierarchy via
 `font-weight`/`text-transform`/`color` instead; if a panel truly needs per-element
 sizing, add it ONE selector at a time and screenshot-verify before adding the next.
- **Multiple `PanelComponent`s on ONE GameObject under ONE `ScreenPanel` all render** (one project
 Bootstrap mounts 6 on one ScreenPanel). So a second panel that shows nothing is NOT a
 one-ScreenPanel-per-panel wiring limit — don't split it onto its own ScreenPanel chasing that theory
 (it doesn't help). Instrument OnStart/OnTreeBuilt first to split "code not live" from "in tree but
 unstyled/mispositioned."
- **A play-mode terrain brush's LOWER op digging a cell below the sea level leaves an unflagged
 below-sea cell → the `water_above_floor` audit fires (the invisible-creek net working as designed).**
 Generation's LakePass floods depressions; a naive brush doesn't, so a sub-sea pit is a genuine
 invariant violation. Fix that also makes "dig a pit to below the water table" FILL naturally: after
 every height op, reconcile each changed cell against the sea surface step — floor below sea ⇒ set
 water to the sea surface (never lower an existing higher lake); land raised to/through a water
 surface ⇒ clear it (else `ws ≤ gs` trips the audit). Keeps the audit target-0 BY CONSTRUCTION, and
 a `SeaLevel ≤ 0` world reconciles to nothing (no surprise flooding).
- **Dirty-chunk remesh seam law: a brushed cell on a chunk BORDER must remesh the NEIGHBOUR chunk too,
 because the neighbour's skirt quads sample this cell's step across the seam** (VoxelMesher's
 East/West/North/South walls read `GetStep(gx±1)/(gy±1)`). Miss it and the far side keeps a stale wall
 = a visible crack. The mark-dirty helper adds the axis neighbour for a cell on that chunk edge (and
 the diagonal chunk for a corner cell). CRUCIAL: the grid-only `chunk_seams` audit checks only the
 lattice formula (always clean by construction) — it CANNOT see a stale-mesh crack from a missed dirty
 chunk. The real regression net is screenshots of strokes straddling a boundary and a 4-chunk corner
 (both verified crack-free at single-digit remesh ms).
- **`Component.Active` is a real inherited member** — naming a component's own bool `Active` raises
 CS0108 (`hides inherited member`) and, worse, silently shadows the engine's enabled flag; the editor
 in-compile surfaces the warning even when `dotnet build` was clean. Name a domain flag something else
 (`Armed`).
- **Size step-up / step-down / glue to the COLLISION mesh, not the VISUAL step.** the project renders
 0.25 m stairs on 0.2 m treads but its COLLISION is a coarse 4-cell (0.8 m) block heightfield taking each
 block's MAX cell height (VoxelMesher.BuildCollision) — the character walks the COARSE tiles, never the
 fine visual steps. A trace mover with `StepUpMax = 0.35 m` (one visual step + slack, the "obvious" value)
 STALLS constantly on any moderate slope, because the coarse block riser there already exceeds 0.35 m —
 measured: a walkable-looking ridge climb tripped 5 stuck-rescues at 0.35 m and **0 at 0.9 m** (≈ one
 0.8 m block + slack). Same for the step-down deep-probe and the down-glue rate (a real step DOWN one
 0.8 m block at run speed crosses it in ~0.13 s, so glue must clear ~0.8 m in ~0.13 s ⇒ ≥ ~6 m/s or
 descents visibly float). Genuine cliffs (>0.9 m rise per 0.8 m ground ≈ >48° local) still refuse. RULE:
 when a mover walks a decimated/coarsened collision proxy, tune step tolerances to the PROXY's step
 geometry, and keep them ABSOLUTE (never scale them with the character body — terrain risers don't shrink
 when the character does).
- **Standing-still BOUNCE = the fall-through audit fighting the ground-snap because it read a DIFFERENT
 ground source than the mover.** The mover snapped the feet onto the traced collision surface, but the
 `[boot] AUDIT character_floor` fall-through check compared bodyZ against `WorldGrid` block-max heights (a
 static, `WorldGen.Grid`). Those normally agree — but an editor `wb_generate` mid-play repoints the
 `WorldGen.Grid` static at the EDITOR scene's grid while the PLAY colliders stay the play grid, so the
 audit's floor sat ABOVE the real collider surface → it teleported the body UP every tick → the mover's
 snap dropped it back → continuous oscillation. Telemetry signature: bodyZ alternating by a fixed amount
 every tick while stationary. FIX: base the fall-through check on the SAME trace the mover stands on
 (`GroundZAt`, a cast against the live ModelColliders), never a parallel grid/static that can diverge —
 one source of truth for "where is the floor". Proof: a 2 s standing bodyZ log went from oscillating to
 0.000 m range.
- **`Scene.GetAllComponents<T>()` does NOT return DISABLED components.** A chase camera pre-created
 `Enabled = false` (so orbit is the boot mode) was then UNFINDABLE by a later
 `Scene.GetAllComponents<CharacterCamera>().FirstOrDefault()` — it returned null, the possess-time
 camera swap silently no-op'd, and the camera stayed stuck at the orbit pose. Two fixes: search for an
 ENABLED sibling (the OrbitCamera) and read the disabled one off its GameObject, OR (cleaner) CREATE the
 transient camera on possess and DESTROY it on release (create-on-enter, not pre-create-disabled). A
 disabled component is invisible to the type-search API.
- **The MCP `camera_screenshot` captures the engine's transient `editor_camera` artifact, NOT your
 render Camera, until a component ACTIVELY drives the render Camera's transform.** In an MCP-driven play
 session there are TWO enabled cameras: the scene "Camera" (your OrbitCamera/CharacterCamera) and a
 cloned `editor_camera`. `camera_screenshot` framed the frozen editor_camera (a fixed wide/sky view), so
 in-character-mode chase changes never showed — until the chase cam actually moved the "Camera" GO, after
 which the screenshot tracked it. For RELIABLE agent screenshots of a specific subject regardless of which
 camera wins, drive `set_editor_camera` to the subject and use `editor_camera_screenshot` (100% under your
 control). Verify a camera is really driving by reading the "Camera" GO's WorldPosition via
 `get_game_object` and comparing to the expected pose — a frozen pose means nothing is driving it.
- **Static facades that bridge editor McpTools ↔ play-mode components MUST session-reset across
 Play→Stop→Play.** A command/report bridge (editor tool POSTs a command into a game-assembly static;
 the play component consumes it and writes a report back) carries STALE state across a play restart —
 a leftover `InCharacterMode = true` made the new session's director skip spawning, so the first
 `wb_walk` no-op'd against a null character. Clear the per-session flags (and drop any un-consumed
 command) from the boot singleton's `OnEnabled` (runs synchronously at Create, before any command is
 read). Same family as the Sfx/HideSpot ResetForNewSession lifecycle rule. Also: `System.Threading`
 (`Volatile`/`Interlocked`) is NOT whitelisted in the game assembly — a plain `int` token compare is
 whitelist-safe and torn-read-proof for int on x64, use that for the bridge's command token.
- **Visual-Z smoothing to kill staircase pops: clamp to the COARSE step, and beware the fixed-vs-render
 rate aliasing when you try to MEASURE it.** The kinematic body steps instantly (collision truth); the
 visual child eases its world-Z toward the body (`1 - exp(-k·dt)`, k≈14) with a hard clamp so it can't
 detach — but the clamp must match the COARSE collision step (~0.9 m), not the 0.25 m visual step, or it
 leaves ~0.5 m of a 0.9 m body pop unsmoothed. Smooth the CHASE CAMERA's focus height on its OWN slower
 exponential (k≈8) too — camera smoothness dominates perceived smoothness. MEASUREMENT TRAP: bodyZ steps
 at the FIXED-update rate but the smoother runs at the RENDER rate, so per-log-sample deltas alias —
 sampling every N frames shows body≈visual (both integrate the same displacement); the honest metric is
 the max WALKING (teleport excluded) single-frame pop, which showed body 0.25 m → visual 0.05 m (~4.8×).
 Standing-still bodyZ range is the cleaner scalar proof (0.000 m = idempotent snap).
 **SCOPE-LIMIT:** this manual smoother is ONLY valid where the character root is NOT engine-interpolated.
 If `WorldPosition` is written in `OnFixedUpdate`, `FixedUpdateInterpolation` (default ON) already
 smooths it — a second per-frame smoother computed from raw fixed-tick z DOUBLE-smooths and produces a
 50 Hz sawtooth that reads as model flicker on stepped terrain. Verify engine interpolation is
 absent/disabled before using the manual smoother.
- **A SCALED citizen foot-slides unless you feed the AnimGraph velocity ÷ scale.** `CitizenAnimationHelper`
 (the engine component — `WithVelocity`/`WithWishVelocity`/`WithLook`, `IsGrounded`, `TriggerJump`, set
 `.Target` to the SkinnedModelRenderer; the NpcWander pattern) picks the gait from the
 velocity you feed, authored in ENGINE UNITS/s for a 1.0-scale citizen. Scale the citizen child
 `WorldScale = 0.65` and its stride covers 0.65× the ground per cycle → feet drag; feed `velocity /
 scale` so the gait cycles fast enough to keep the scaled feet planted. Also feed move-speed from
 HORIZONTAL velocity only (a vertical step delta must not pulse the run cycle) and give `IsGrounded`
 hysteresis (≥0.1 s continuously airborne before grounded=false) or a single-tick seam flicker
 machine-guns the jump/air anim.
- **Clothing: the engine ships ~221 LOCAL `citizen_clothes` items; dress via `ClothingContainer`.** Enumerate
 `addons/citizen/Assets/models/citizen_clothes/**.clothing`; resource paths are `models/citizen_clothes/…`
 (the addon Assets/models mounts as `models/`). Working apply pattern (ClothingScene.cs / the project
 PlayerController): `var c = new ClothingContainer(); foreach path: var item =
 ResourceLibrary.Get<Clothing>(path); if(item!=null) c.Add(item); c.Apply(skinnedRenderer);`. Prefer
 locally-shipped items so headless/offline runs work (some clothing is cloud-hosted and silently no-ops).
 GOTCHA on engine 26.07.08e: several torso pieces (`shirt/Flannel_Shirt/flannel_shirt`,
 `jacket/Sleeveless_Jacket/sleeveless_jacket`, `vest/Tactical_Vest/tactical_vest`) render with a large
 "POLICE" placard on the back — inspect the actual render, don't trust the folder name, when assembling a
 themed look. First-person body hide is `skinnedRenderer.RenderType =
 ModelRenderer.ShadowRenderType.ShadowsOnly` (keeps the shadow, drops the body draw — enum confirmed in
 Sandbox.Engine.dll).
- **Project `[McpTool]`s that take one STRING JSON param are invoked as `{"<paramName>": "<json string>"}`,
 not as the JSON object directly.** `wb_character(string argsJson)` is called with
 `{"argsJson":"{\"op\":\"probe\",\"x\":480}"}` — passing `{"op":"probe",…}` errors "Unknown argument
 'op'". Same shape as `wb_generate(specJson)` / `wb_brush(opsJson)`. The client's stdout on Windows is
 cp1252 and crashes printing a tool description containing a non-ASCII char (e.g. `∈`) — set
 `PYTHONIOENCODING=utf-8`.
- **Python's `open(path, "w")` on Windows silently uses the legacy codepage (cp1252), not
 UTF-8, unless `encoding="utf-8"` is passed explicitly** — it does NOT raise, it just
 mis-encodes any non-ASCII character (an em dash becomes one wrong byte instead of the
 3-byte UTF-8 sequence). Always pass `encoding="utf-8"` on every `open(..., "w")` in
 codegen scripts emitting em dashes, curly quotes, or other non-ASCII punctuation.
- **Slide/slope logic on a STEPPED coarse-collision voxel world must read slope from the FINE GRID
 GRADIENT, not a ground-trace normal.** The coarse collision is a field of flat-TOPPED block quads
 (VoxelMesher.BuildCollision), so every trace normal is straight up (0,0,1) and carries ZERO slope —
 useless for a slope-slide gate. Sample `grid.HeightM` at ±~1.5 m about the feet and take the gradient;
 the downhill = −gradient, slope = |gradient| (tan θ).
- **A "snap-to-ground or detach-to-air" slide FREE-FALLS block-by-block on a steep coarse face** — because
 each flat-topped block puts a >StepDownProbe (0.9 m) riser at every block edge on any slope past ~1.0, so
 the mover bails to Air at each block and the descent reads as a fall (recorded slide speed capped, the fast
 part logged as "air", never exceeding the tier). FIX: let the slide ARC over sub-cliff risers under gravity
 and re-ground each tick, staying ONE continuous momentum slide (no tier cap → it builds past sprint); only a
 near-vertical multi-block plunge (a single-tick drop > a `SlideDetachM` ~ several block-risers) becomes true
 Air. Live-verified: a 60° face went from slideMax 4.7 (block-hopping fall) to 7.0 m/s > sprint 6.5, 0
 fall-throughs, once the arc-and-reground + a raised detach threshold landed. Slide friction is CONSTANT
 (not speed-scaled) so net accel stays positive on any slope past the entry threshold and speed climbs —
 key for the short slopes a terraced world offers.
- **The citizen AnimGraph already has native SLIDE and SWIM poses — feed them, don't author.**
 `CitizenAnimationHelper` (base/code/Components/Citizen) exposes `SpecialMove = SpecialMoveStyle.Slide`
 (also Roll/LedgeGrab), `IsSwimming` (b_swim), `DuckLevel` (0..1 duck param), `IsNoclipping` (b_noclip),
 and `MoveStyle` (Auto/Walk/Run). A slope-slide sets SpecialMove.Slide + DuckLevel 1; a swim sets
 IsSwimming; all resolve under `dotnet build`.
- **Double jump: SET Velocity.z DIRECTLY (never a Jump() helper — it clamps vs rising velocity).** One air
 jump per airtime, latched with a bool reset when grounded/sliding; second impulse = JumpSpeed × ~1.25 ("a
 little higher") + a small forward boost if moving; re-trigger the jump anim. Confirmed working via a
 `doubleJumps` telemetry counter and a `[boot] double-jump vz=4.50` log (= 3.6 × 1.25). Gating is on the mover
 MODE (Ground/Slide/coyote-Air → first jump; airborne + !latch → double), NOT on the ANIM grounded-hysteresis
 (that's visual-only and would mis-arm the latch).
- **Swim on a voxel world: a NARROW river never triggers swim — the coarse collision BRIDGES the channel**
 (the 0.8 m block takes the MAX cell height over its 4 cells, so a 1–3-cell-wide carved channel reads as bank
 height, and the mover walks a "bridge" over the water). Swim needs a WIDE/deep body (lake/ocean) where the
 coarse floor actually sits below the surface by > chest. The `wb_character probe` `coarseFloorM` field is the
 fast eligibility check: swim engages where `waterSurfaceM − coarseFloorM > chest`. Buoyancy that eases the
 feet toward `surface − CharHeight·waterlineFrac` is stable (bodyZ 0.35→0.87 m, head clear, 0 bounce, 0
 fall-throughs). Reuse target for vehicles (jet ski) — keep water-depth detection on the grid, not a trace.
- **First-person "hide the player" — use the `"viewer"` tag + camera `RenderExcludeTags`, NOT `RenderType`.**
 `RenderType.Off` does NOT hide the model — `ModelRenderer.cs` defines `Off = render WITHOUT shadow` (model
 still draws); only `ShadowsOnly` sets `ExcludeGameLayer` to drop the draw. The correct fix is the engine's
 own PlayerController idiom: camera keeps `"viewer"` in `RenderExcludeTags` (set once), and the body/item GO
 does `Tags.Set("viewer", firstPerson && !IsProxy)`. GameObject tag propagates to children, so clothing items
 spawned by `ClothingContainer.Apply` are automatically hidden — no per-renderer enumeration needed.
- **Citizen clothing folder/file NAMES lie about the render — vet with the `.clothing.png` THUMBNAIL first,
 then in-game.** Engine 26.07.08e: `shirt/Flannel_Shirt/flannel_shirt` renders as a black TACTICAL VEST with
 a "POLICE" back placard (this, not the flannel, is the M9 "POLICE on the torso"); `shirt/Tshirt/tshirt` is a
 "SUPER DEAD" zombie graphic tee; `jacket/Hoodie/hoodie` APPLIES (logs 1/1) but its mesh does NOT render on the
 citizen (torso stays bare); `shirt/Loose_Shirt/loose_shirt` (plain tan open button-up, "Tops" slot) is clean
 AND renders. Each `<item>.clothing` sits next to a `<item>.clothing.png` render thumbnail — READ THAT to vet
 branding in seconds instead of a recompile+screenshot cycle per candidate.
- **MCP play-mode iteration: verify `compile_status` AFTER the mtime bump and BEFORE `play_start`, or play runs
 the STALE assembly.** Two clothing-swap screenshot rounds showed the OLD outfit because play_start fired before
 the in-editor compile of the new source finished — the render "not changing" across a code edit is the tell.
 Also do a clean `unpossess`→`possess` for a fresh run report: a stale bridge report (e.g. reached=3/3 from a
 prior session's 3-waypoint route) surfaces on the first status poll and looks like your new command no-op'd.
 And `wb_walk` arrival is HORIZONTAL-only — a slide/descent leg's target must sit PAST the base of the face or
 it "arrives" mid-descent and ends the leg early.
- **Collision-fidelity study (the project default 960²): halving CollisionBlockCells 4→2 (0.8→0.4 m blocks) =
 EXACTLY 4× collision tris (115 200 → 460 800 world-wide), NEGLIGIBLE regen delta (2095 vs 2132 ms), render
 unchanged.** 461k is still << the 2 M budget and < 754k render tris, so collision cost is not the blocker;
 the blocker is that the whole step/slide dial set (StepUpMax 0.9 m etc.) is sized to the 0.8 m block, so a
 finer collision pass must re-tune + re-validate. Kept 4 as default; the switch is one Tuning const.
- **An arcade RAYCAST CAR on stepped voxel terrain MUST air auto-level, or every launch cartwheels.** The
 buggy is `Rigidbody` + 4 wheel down-raycasts (suspension force along the CONTACT NORMAL, per the standing
 drive gotcha) + a kill-lateral-slip tire model (cancel a fraction of each grounded wheel's sideways velocity;
 handbrake scales rear grip down = drift). On its own it flipped CONSTANTLY on the 0.25 m steps / 0.8 m coarse
 blocks. Three fixes turned it arcade: (1) **air auto-level** — while airborne (`grounded < 2`) apply a STRONG
 roll+pitch angular-velocity damp + an upright-restoring torque toward world-up (yaw left free), so it rotates
 flat in the air and lands on its WHEELS instead of upside-down (the Rocket-League trick; without it, launches
 end in a 2 s self-right). (2) **speed downforce** ∝ v² at the CoM, plants it so it doesn't launch off small
 steps. (3) grounded roll/pitch damp + a gentle upright torque for the tip-over wobble. Result went from
 ~200 flipped-ticks/run to **0**.
- **Spawn a raycast car at SUSPENSION EQUILIBRIUM height, not "surface + radius".** Seating the body so the
 wheels start at ~full compression makes all four hit the per-wheel spring cap at once → 4× weight up → a
 violent launch/flip on spawn. Seat origin = `surface + (travel + radius) − smallEquilibriumComp + attachOffset`
 so each wheel carries ~static load at rest. Also cap the per-wheel spring at ~2.5× static (not 4× = mass·g),
 or a single compressed corner flings it.
- **`Rotation.FromYaw(+angle)` is a LEFT (CCW) turn — get the steering sign right or the car spirals the WRONG
 way into hazards.** A `+cross`/`-cross` or `+steer`/`-steer` mixup makes the autopilot (and keyboard) steer
 AWAY from the target; the buggy drove straight into the sea every run until the sign was fixed
 (`steerRot = WorldRotation * Rotation.FromYaw(-steer)` for right-positive steer; jet-ski yaw likewise
 negated). Symptom: the vehicle consistently heads the opposite way from where it's told.
- **A ground-vehicle fall-through audit on a COARSE flat-topped-tile collision world must down-trace from JUST
 ABOVE THE BODY — never a fixed ceiling, never the grid block-max.** Same family as the M9 character
 standing-bounce, two ways: (a) the grid `CoarseGroundM` (block-max static) diverged from the play
 `ModelCollider` by ~4 m, so an audit keyed on it yanked a perfectly-parked buggy up onto a phantom floor and
 flipped it — trace the LIVE collider, one source of truth. (b) even tracing the collider, a FIXED-CEILING
 down-trace hits an OVERHANGING neighbour tile (the coarse blocks are flat tops with NO riser walls, so a
 taller block overhangs the space above a lower one) and "rescues" a parked vehicle up through it — start the
 trace at `body + 2 m` so overhangs above are skipped and it finds the tile the wheels rest on. A
 Rigidbody+BoxCollider physically CAN'T clip solid collision, so real "fall-through" is basically only the
 void off the world edge; the aggressive audit was the bug, not the detector.
- **A LAND vehicle needs a HARD-DECK + DROWNED recovery, because physics strands it in water.** Drive a buggy
 into the sea and it sinks and sits on the seabed submerged — too shallow for a "z < sea−25 m" hard deck yet
 never coming back. Add: (1) hard deck `z < seaLevel − 10 m` (land) → respawn; (2) drowned timer — submerged
 below the grid water surface by >1 m for >2.5 s → respawn to the parked pose. The jet ski is exempt (it
 legitimately rides the surface).
- **Jet ski = single-point buoyancy on the GRID water surface (no water collider), and it holds the waterline
 to ±0 m.** Read the height truth from `grid.GetWaterStep` (the M9.6 swim interface), NOT a trace. Vertical =
 a damped spring toward `waterSurface − hullHeight·waterlineFrac` with **gravity fed forward** so equilibrium
 sits AT the target (and only applied while at/below the surface band, so a wave/beach launch arcs down under
 gravity); thrust forward with a top-speed taper; **speed-dependent yaw** (a PWC steers by vectored thrust —
 near-zero turn authority stopped, which makes autopilot direction-reversal slow, as expected); cosmetic bank
 on the VISUAL only (a physics roll fights the single-point buoyancy); beaching when the grid ground rises to
 within a clearance of the water surface → buoyancy targets the sand + drag spikes, reverse throttle pushes
 off. Measured surface-tracking deviation over a full bay crossing: **0.00 m**.
- **Forge/Tripo vehicle meshes re-exported through Blender withOUT extra rotation keep their facing — offset 0
 worked.** The dune-buggy/jet-ski `.vmdl`s drove nose-first with `FacingYawOffset = 0` (unlike one project's
 hero character which needed −90); the difference is those were re-exported joined+grounded only. Still VERIFY
 in-engine before wiring facing-dependent movement. And note the wall-less coarse collision means a wheel
 raycast that finds a HIGHER tile ahead just lifts that corner — the buggy RIDES gentle terraces and only a
 big drop launches it (driving INTO a tall terrace, the body box stops against the higher tile — it can't
 climb multi-block risers).
- **A runtime world root torn down with `GameObject.Destroy()` KEEPS RENDERING in EDIT mode — the
 deferred destroy queue is not processed between MCP regenerations, so the OLD world (all ~900 chunk
 ModelRenderers) overlaps the new one.** the project's `WorldGen.Regenerate` did
 `previousRoot?.Destroy()` then built a new `wb_world` root; in edit mode `scene_tree` then showed TWO
 `wb_world` roots, each with 923 children, both Enabled. Identical specs coincide exactly (invisible —
 determinism/snapshots look fine); a CHANGED slider (amplitude/scale/sea) leaves the previous world
 showing THROUGH the new one — this was the owner's "visual inconsistency when sweeping sliders and
 regenerating in the editor." Proof: generate amp80 then amp10 + screenshot = the tall amp-80 mountain
 renders through the flat amp-10 plain. Same family as the M9 grid-vs-collider "static repointed
 mid-play" bug. FIX: `foreach(root named wb_world) root.DestroyImmediate()` (synchronous, valid in both
 edit and play mode; the editor tools themselves use `go.DestroyImmediate()` for scene deletes) — and
 sweep ALL matches, not FirstOrDefault, to also collect an already-leaked root. Regression net: a
 `wb_grid_hash` McpTool that also returns `worldRootCount` + `chunkGOs` vs `expectedChunks`, asserted
 ==1 / == on every mutating step.
- **A scene query fired in the SAME breath as a regenerating mutation can return a LAGGED
 snapshot — even when `scene_tree` already shows the tree is correct.** A tool that
 rebuilds a world root each call (`previousRoot.Destroy()` → build new) is correct, yet
 `find_game_objects` called immediately after returned STALE objects from the PRIOR
 build — an impossible-looking contradiction. Don't trust a query issued immediately
 after a mutation: re-generate and re-query, or verify in PLAY mode where lifecycle is
 real. Corollary: edit-mode lighting for runtime-spawned `ModelRenderer`s is also
 unreliable (unlit/near-black across regenerates) — verify colour/lighting in PLAY.
- **Editor-viewport auto-exposure ADAPTS over wall-clock frames, so two screenshots of a BYTE-IDENTICAL
 regenerated world can differ globally by tens of percent — a stale-render false positive.** After
 fixing the double-root overlap, return-to-start grid hashes were byte-identical but return-to-start
 top_down SCREENSHOTS still diffed up to 26% (worst on the sea sweep: sea +6 floods half the map in
 bright water → auto-exposure darkens → returning to sea 0 and shooting immediately catches exposure
 mid-re-adaptation). It is a GLOBAL brightness/tint shift over identical geometry (verified: two shots
 of the same returned world with a ~2.5 s settle diff to 0.000%). Two fixes in the diff harness: (1)
 SETTLE the viewport before a comparison capture; (2) EXPOSURE-NORMALIZE the pixel diff — match B's
 per-channel mean to A's before thresholding, which cancels a uniform tint but preserves a LOCALIZED
 structural difference (a real stale overlapping world is not uniform and survives). Post-normalization
 noise floor across five sweeps: 0.0-0.21%; real structural staleness reads 15-25% (100x). Same family
 as the WbFpsProbe warmup-skip. The grid hash stays the authoritative return-to-start gate; the
 screenshot diff is the coarse structural one.
- **A deterministic content hash for "same spec = same world" byte-identity checks must use a
 PROCESS-INDEPENDENT hash — C#'s `string.GetHashCode`/default hashing is randomized per process** and
 would make two editor sessions disagree. the project's `wb_grid_hash` folds the persistent WorldGrid
 arrays (Steps/Material/WaterSurfaceStep/Biome/Flags) + dims + sea/snow through FNV-1a (offset
 14695981039346656037, prime 1099511628211) into one hex key, with per-array sub-hashes so a mismatch
 localizes WHICH array diverged. Cheap (~5 arrays x 0.92M cells < 50 ms at 960^2) and the backbone of the
 transition suite's determinism/return-to-start gates.
- **Flat-topped MESAS from a heightfield need TWO terraces, not one: terrace a SMOOTH low-frequency
 block field for the walls, THEN flat-Z-snap the final height so tops are horizontal.** the project's
 M9.5 mesa lane first tried terracing the detailed massif — gave concentric "wedding-cake" contour rings
 on a rounded dome, not buttes. Three fixes stacked: (1) terrace a 2-octave field at ~0.5×TerrainScale
 (several blocks across the massif), NOT the full ridged massif (whose base-noise detail breaks flat
 tops); (2) STRETCH the block field's dynamic range (~4×) before terracing — value noise clusters near
 0.5 so an unstretched source spans barely one tier and only one soft step appears; (3) after composing
 the massif with its smooth mass-envelope, terrace the FINAL height in absolute Z (gated by the envelope)
 — the envelope otherwise rounds every mesa top into a dome. Snow then pools on genuinely flat tops. The
 0.25 m step quantization + strata band table supplies the fine cliff striation for free.
- **The editor MCP `editor_camera_screenshot` renders through the `editor_camera` GameObject, NOT the
 game "Camera" — so one project camera's Tonemapping/Bloom/exposure components do NOT grade your shots, and
 the editor VIEWPORT's own auto-exposure normalizes overall brightness.** Consequence for a runtime
 lighting grade (the project WbLighting): brightening the sun/ambient/sky uniformly reads as NO change
 (auto-exposure claws it back); only COLOUR BALANCE and directional contrast survive. Verified with an
 "orange sun" diagnostic — the terrain went fully orange, proving the DirectionalLight IS driving the
 edit-mode render, but a mild warm-white sun looked identical to cool-white because exposure normalized
 the brightness. Also: DirectionalLight (LightColor/SkyColor/FogStrength/rotation), SkyBox2D.Tint and
 EnvmapProbe.TintColor CAN all be set at runtime in EDIT mode and take effect (confirmed via
 get_game_object). But you can't lift the scene into a high-key "chalky bright" look this way — the
 blue stock skybox + baked envmap + viewport exposure cap it; a genuinely bright grade needs a paler
 skybox material or viewport-exposure control.
- **Two water audits can CONFLICT at the sea boundary, and the resolution must be keyed on the QUANTIZED
 step, not the float height.** the project's M9.5 added `water_contained` (no water surface above an
 adjacent dry ground) alongside the existing `water_above_floor` (no below-sea cell left dry = invisible
 creek). A flat enclosed bench BELOW sea level (created by the mesa terrace, or by a road corridor that
 re-quantizes the coast AFTER LakePass) breaks one or the other: dropping it as a shallow pit strands it
 dry-below-sea (above_floor); filling it to its above-sea spill rim strands the film over the dry rim
 (contained). Only fill-to-EXACTLY-sea-level satisfies both — and the "below sea" test must compare
 `groundStep < floor(seaLevel/step)`, because a float height of 1.9995 m rounds to a step below sea yet
 is ">= sea" in float, slipping through the gap between the two quantized audits. Also: a post-final-
 quantize "sea reflood" sweep is needed because roads flatten the coast after LakePass runs. General
 rule: when two grid audits police the same cells, satisfy BOTH on the FINAL quantized grid, keyed on the
 same quantized quantity the audits read.
- **A containment "settle" that only ever LOWERS water, alternated with a monotonic "relax" that only
 lowers, converges to a fixpoint — but each can re-break the other's invariant, so loop them together.**
 the project rivers must be (a) contained (surface <= adjacent dry ground) AND (b) monotone
 non-increasing downstream. The containment settle lowers an upstream cell to a low bank; that can drop
 it below its downstream neighbour, re-breaking monotonicity; re-relaxing monotonic can dry a cell,
 which exposes a new dry neighbour and re-breaks containment. Both operations are monotone-decreasing and
 bounded below (ground), so alternating them to a combined fixpoint terminates. Guard BOTH sweeps to skip
 cells at/below the sea step (a river mouth at sea is sea, not a terrace — relaxing it strands an
 invisible creek).
- **Adding sheer mesa/cliff terrain silently breaks road A*-corridor grading: a corridor forced over a
 wall the profile-smoothing can't flatten lights up the road_slope audit (0 -> 250 offenders).** Two
 fixes together: raise the A* slope penalty so roads PREFER valleys/apron (route around cliffs), AND add
 a hard grade-clamp that pulls any core road cell more than one graded step above its lowest core
 neighbour DOWN toward it (monotone-decreasing, converges) — a graded cut through an unavoidable wall.
 General: any pass that assumes "gentle terrain" (roads, prop seating, spawn) needs re-validating when a
 landform pass makes the terrain steeper.
- **A greedy voxel mesher that colours a cliff SKIRT with its TOP cell's single material turns per-cell
 strata dither + contour-wander into clashing VERTICAL stripes on sheer walls.** A sheer wall exposes ONE
 material per column (the top cell's, Darkened for fake-AO), so any classification field that varies
 COLUMN-to-COLUMN — a per-cell white-noise dither hash tuned for plan-view grain, or a smooth
 contour-wander that perturbs band-boundary height (hc = h + noise) — makes vertically-adjacent columns
 pick DIFFERENT strata bands. The result reads as a vertical picket-fence of clashing hues instead of the
 reference's level HORIZONTAL strata (worst where the mesa lane packs thin single-cell buttes). Fix : detect a WALL cell (max quantized step-delta to a 4-neighbour >= 3 ~ 0.75 m over a
 0.2 m cell) and on it key strata on RAW absolute-Z bands (bh = h, no contour wander -> boundaries stay
 level in every column) with the dither hash NEUTRALISED (dh = 0.5 -> every Feather/StopPick resolves to
 the SAME hard band in adjacent columns); also drop smooth patch-driven accents (scree/ice) on walls
 (they streak). Flat ground keeps the contoured, dithered plan-view wash. SECOND, independent fix: keep
 vertically-adjacent strata bands NEIGHBOURS in colour space — a warm-tan next to a saturated-blue band
 clashes violently even one band apart, so ramp rock warm-tan -> light-neutral-grey -> cool blue-grey with
 no big hue/value step. True horizontal strata ON a single-cell sheer face still needs the mesher to
 vertically SUBDIVIDE the skirt and colour each sub-quad by its Z band (a later change).
- **Shared multi-agent working tree: `git checkout -b` branches off wherever HEAD currently is, which a
 CONCURRENT agent may have moved out from under you.** In the project a vehicle-milestone session
 committed its WIP to `m98-vehicles` and left that branch checked out; a look-pass session that then ran
 `git checkout -b m95c-look-rounds` (intending "off main") silently branched off `m98-vehicles`, stacking
 its commits on top of 5 unrelated vehicle commits. Detect via `git reflog` (the "checkout: moving from X
 to Y" line names the REAL base) and `git log --oneline main..HEAD`. Recover cleanly with
 `git rebase --onto main <real-base>` when the two commit sets touch DISJOINT files (verify with
 `git diff --name-only main..<base>`): it replays only your commits onto the intended base and leaves the
 concurrent branch untouched. General: before branching in a shared tree, `git rev-parse --abbrev-ref
 HEAD` to confirm the base — do NOT trust a stale earlier `git status`.
- **Altitude-driven biome gradients: derive EVERY climate band from ONE effective-temperature lapse
 anchored to the snow line's own span, and adjacency invariants hold by construction across the whole
 slider space.** the project M9.5c r2 ("desert must never abut snow"): tEff = Temperature - h/SnowSpanM
 (SnowSpanM = the same 90 m the snow-line formula already uses) makes tEff at the snow line a CONSTANT
 (~0.26) for EVERY Temperature value - so a "cool ground goes green" ease keyed on tEff is always FULL at
 the snow line and sand can never reach it, hot or cold, with zero per-band retuning. Second trick: ease
 the lowland moisture axis toward a grass-core TARGET (lerp toward 0.48, never additive past it) instead
 of hard biome gates - the continuous material wash and the discrete biome classification then agree for
 free (both read the same eased axis), avoiding the classic "biome says grass but material paints sand"
 divergence. Audit the adjacency law only on WALKABLE-continuum pairs (|dstep| <= ~1 m per cell): sand at
 the foot of a sheer cold-top mesa is a legit Death-Valley composition, not a flank seam - a strict
 plan-adjacency audit false-positives on every big cliff.
- **s&box EDIT-mode EnvmapProbe ambient FLAPS on/off across wall-clock frames, and a single-frame
 camera_screenshot landing MID-flip applies the probe to only SOME screen tiles - rendering equal-spaced
 SCREEN-aligned rectangles that masquerade as chunk-sized material patches.** the project's
 "rectangular apron tint patches": measured with ZERO scene changes, consecutive captures alternate
 between two global states ~19/255 apart (the probe's uniform ~7% ambient lift), dwell ~seconds; a
 mid-flip capture shows ~67 px screen-axis rows, phase-flipped at a tile column. PLAY mode is stable
 (probe ON) - purely a capture-path artifact. Triage screen-space vs world-space artifacts FIRST by edge
 orientation (world/chunk seams project as DIAGONALS at a 45-deg hero yaw; renderer tiles stay
 screen-axis-aligned even in perspective) and by back-to-back no-change captures (flip-flop = temporal
 race, not content). Guard (tools/wb_gamecam.py): burst-capture, keep the BRIGHTEST frame that has a
 pixel-level twin among the burst - a mid-flip tiled frame has no twin, so it can never be saved, and
 brightest = the stable play-mode state. Bonus finding: the scene-stock probe box is +/-512 u (~13 m) -
 ~1% of the diorama; resize it to enclose world + cameras (byte-identical render when the probe is on).
- **`compile_status` returns `{IsBuilding, Compilers:[...]}` — there are NO top-level
 `Success`/`Errors`/`NeedsBuild` fields.** Each entry in `Compilers[]` carries its own
 `{Name, IsBuilding, NeedsBuild, Success, Errors, Warnings, Diagnostics}` (verified live,
 engine 26.07.08e, ~10 compilers incl. `local.<project>` and `local.<project>.editor`).
 A gate that reads flat fields gets `None` and mis-reports "compile not clean". Reduce
 the array: clean = every `Success==true`, no `NeedsBuild`, nothing `IsBuilding`; judge
 YOUR assemblies by the `local.<project>*` entries.
- **A per-CELL minimum-depth gate on flood-filled water SHREDS lake sheets — depth-gate per BASIN,
 and audit "every adjacent non-river water pair shares one surface".** the project's LakePass kept a
 water cell only if `surf − terr >= MinLakeDepthM`: a genuine lake's shallow SHELF ring dried while its
 deep core stayed wet (a sheet with a dry gap at its edge over ground still below the waterline), then
 the containment settle staircased the stranded edge cell-by-cell down the terraces — orphan one-cell
 films at unique heights ringing the basin (owner play-mode defect; 507 offenders on the live default
 world). Physically a lake is wet to its waterline CONTOUR or it isn't a lake. Fix: the priority-flood
 propagates ONE exact float surface per basin, so basins are 4-connected components of equal above-sea
 surface — keep or drop each WHOLE component on its MAX depth. The regression net (`water_levels`,
 target 0): every pair of 4-adjacent water cells must carry the same quantized surface unless one is a
 River cell (rivers are stepped by design under their own monotonic audit).
- **Two special-case water rules that are each correct alone can collide INSIDE a feature: "below-sea
 floor reads exactly sea level" carved a sunken sea-level disc into the middle of lakes whose floor
 dips under the sea.** The M9.5 override (quantized floor below the sea step ⇒ surface = sea — needed
 so enclosed below-sea benches satisfy water_above_floor AND water_contained) fired for cells inside a
 KEPT above-sea lake, so mid-lake cells read sea level while the rest of the sheet read the spill rim —
 adjacent 8-vs-4 surfaces the new water_levels audit caught on two golden specs (a defect that predated
 the audit and had simply never been visible to any existing net). Scope narrow overrides by feature
 membership (here: skip cells of kept basins), and when adding an invariant audit expect it to unearth
 OLD violations, not just the defect that motivated it.
- **VISUAL adjacency laws ("X must never read as touching Y") need a PLAN-distance mechanism, not just
 an altitude gradient — cone-dilate the height field with a 2-pass chamfer and drive the classifier
 off the dilated "environment height".** the project round 2 eased sand→grass with altitude; sheer
 walls still put full-warm desert paint 1 cell (in plan) from a snow rim, because the wall's foot is at
 LOW altitude. Fix: env[i] = max_j (h(j) − planDist(i,j)·slope) — a cell at the foot of a snowy wall
 reads the wall's height, i.e. it is climatically "under the mountain". The cone dilation is EXACT for
 the chamfer-8 metric in one forward + one backward sweep (max-plus analogue of the classic two-pass
 distance transform; verified against Dijkstra to 0.0 error) — O(n²), ~10 ms at 960², deterministic.
 Store the field on the grid so the material-wash pass paints with the SAME values the biome classifier
 gated on (recomputing "identically" is how the two drift apart).
- **"ONE coherent region, not patches" from noise: cut the FBM variation BELOW the seam distance and add
 a single seed-hashed directional gradient — then only the gradient can cross the classification
 seam.** the project's desert scattered in pockets because moisture FBM (±0.29 swing) crossed the
 desert seam (baseline 0.5 → seam 0.32) anywhere. Fix: variation cut to ±0.17 (can no longer reach the
 seam alone) + an "arid pole" planar gradient (seed-hashed compass direction, smoothstepped, up to
 −0.30 toward one map side) — desert becomes one contiguous warm quarter with naturally faded edges,
 and the FBM survives as texture WITHIN the region. Slider extremes keep working because they shift the
 baseline itself. Mint a FRESH hash salt for the direction pick (reused salts correlate fields).
- **The s&box editor's "Mcp Server Enabled" preference does not reliably persist across editor
 restarts (a force-killed editor never flushes it), and it CANNOT be enabled headlessly — no config
 file, no convar, no CLI flag stores it (verified by byte-searching the install + user profile while
 a sibling editor served MCP).** If the editor restarts, the agent harness is DOWN until a human
 toggles Edit → Preferences → MCP Server (port table: the project 7200, one project 7269). Budget
 for this in any round that spans an editor restart: probe `editor_status` FIRST, and if the port is
 dead, surface one line to the owner ("toggle MCP on") instead of burning the session hunting for a
 bypass — a project-side auto-enable hook is possible in principle (set
 `EditorPreferences.McpServerEnabled` from an `[EditorEvent.Frame]` once-guard in the Editor assembly)
 but is a persistence mechanism the owner must explicitly approve first.

## Save / load

- DTO classes + `Json.Serialize`/`Json.Deserialize<T>` + `FileSystem.Data.WriteAllText/ReadAllText/FileExists`.
- Mark runtime-placed structures with a `PlacedBuildable { BuildId }` component;
  save loop reads component state per GameObject, load loop respawns through the
  same factory used for building — one spawn path, no drift.
- Static world stays deterministic (fixed RNG seed) so only deltas need saving
  (e.g. chopped-tree indices, not tree positions).
- Missing JSON fields → C# defaults, so guard restored values (`x <= 0 ? 1f : x`)
  and keep enums append-only. Autosave on the natural checkpoint (sleep).

> _(Section restored 2026-07-13 from the pre-split code-patterns pack.)_

- **`Sandbox.Input.EscapePressed` is a real public get/set bool** — read it to detect
  Escape, and set it `false` to consume the press so the engine doesn't route to its own
  pause menu. Verified in the SDK's `Sandbox.Engine.xml` with both `get_EscapePressed` and
  `set_EscapePressed` accessors. Use this for in-game close/back, not an `Input.config`
  bind (editor-reserved keys silently swallow `Input.config` Escape bindings).
- **A ground-vehicle "top speed" telemetry field computed from 3D rigidbody velocity
  length balloons into free-fall speed** when the car drives off the edge of a finite
  ground collider. A plausible-looking `maxSpeedMs=165` was actually the car plummeting
  off the runway — `speed = Velocity.Length` includes the Y (gravity) axis. Fix: report
  `Velocity with { z = 0 }.Length` for a surface-clamped reading. Better: compute and log
  *both* and flag if they diverge (divergence = the car is airborne or off-world).
- **To exercise the full networked-spawn path with one peer (no second machine),** call
  `Networking.CreateLobby(new LobbyConfig())` from an editor MCP tool through a
  game-assembly static bridge — never call `CreateLobby` from the editor tool thread; it
  must run on the game main thread (consume the request in a play-mode component's
  `OnUpdate`). This sets `Networking.IsActive` true and runs the real spawn/sync path,
  letting you verify component creation order and `[Sync]` wiring without a second peer.
- **An overhead UI element (name tag, health bar) anchored to a per-player gameplay field
  FREEZES over a remote player's spawn position while their model walks away** — if that
  field is not `[Sync]` and written only inside the owner's `OnFixedUpdate`. A proxy never
  runs the owner's tick, so the field is stuck at spawn. Fix: anchor off the live networked
  transform (`WorldPosition`), which is replicated and engine-interpolated.
- **A `[Sync(SyncFlags.FromHost)]` field on a runtime-created singleton does NOT replicate
  unless that object is `NetworkSpawn`ed.** A `Scene.CreateObject()` singleton has no
  cross-peer identity even with `NetworkMode.Snapshot`. `GameObject.Network.Active == false`
  and the field never crosses the wire. Fix: host-`NetworkSpawn()` the singleton; the joining
  client receives the host's networked proxy instead of creating its own local copy.
- **On the host, spawning a joiner's character clobbers the host's camera-target singleton:**
  `Components.Create` runs BEFORE `NetworkSpawn(owner)`, so `IsProxy == false` at create time
  and an `OnEnabled` that claims `static Instance` behind `if (!IsProxy)` grabs the joiner's
  body. Fix: re-resolve the claim at the first `OnFixedUpdate`, where `IsProxy` is trustworthy.
- **A joining client's static join state (invite code, mode) gets WIPED by the networked scene
  handoff:** `Networking.Connect` loads the host's scene, the bootstrap creates a new instance,
  and its `OnEnabled` "reset for a fresh session" runs before the join handshake sends those
  values. Fix: make `OnEnabled` reconstruct-not-reset when already connected as a non-host.
  Test blind spot: `-joinlocal` never sets a code pre-handoff, so it can't catch this.
- **A PUBLISHED-build client join RELOADS the game assembly, wiping ALL statics** — the
  reconstruct-not-reset fix has nothing to reconstruct from. Fix: persist join intent to
  `FileSystem.Data` before `Networking.Connect`; restore from disk after the reload, gated
  on a freshness window. Only a real cross-machine published join exercises this path.
- **`Networking.CreateLobby()` is ASYNC — `Networking.IsActive` is still false on the same
  frame.** Any branch on `IsActive` immediately after `CreateLobby` takes the wrong path.
  Gate on your own synchronous mode enum (set on the same frame). Also: a session-END path
  must un-possess the character (`ExitCharacter()`) to restore the pre-session view.

- **Reusing one component type for a NEW object makes tag-based selectors unable to
  distinguish them — add a discriminating tag, don't weaken the shared rule.** If two
  different game objects share the same component type and tag set, a proximity scorer ranks
  them identically. A slightly nearer wrong-type candidate steals the grab. Fix: at spawn,
  add a distinguishing tag to the new variant and apply a small additive penalty in the
  scorer for that tag. The penalty should be small enough that a clearly-nearest candidate
  still wins.
- **A penetration-containment rule that DEFERS to another system ("that's climbable, the
  grapple owns it") deadlocks if the other system can't act in the deferring state.** A
  mantle veto that declines because a climb lattice is nearby assumes the airborne grapple
  will catch the body — but the grapple's own entry gates (intent, toward-dot, reach) reject
  a body sunk below the node band. Fix: on a proven-wedge gate, try a FORCED rescue entry
  that bypasses normal intent gates — the caller has already proven the body is trapped.
- **Pointing a dedicated server at a published-style ident that is not actually published yet
  boots the engine, connects, then fails with `Unable to download package` — and the server does
  NOT self-exit, it lingers holding the process.** Distinct from the client-side join wall where a
  LOCAL `.sbproj` host + joining client dies on `Package wasn't found!`. Kill the server with a
  timed launch + kill-by-PID pattern. Expected to resolve once the package is actually published
  (Hidden should be sufficient).
- **A zero-radius `Scene.Trace.Ray` slips through coarse voxel `ModelCollider`s and returns
  `Hit=false`.** The physics line-vs-trimesh raycast misses degenerate greedy-mesh seams. Fix:
  sweep a thin sphere (`.Radius(0.1f * M)`) on any trace against runtime mesh colliders.
- **A grounded wish-speed servo (`MoveTowards`) silently destroys any applied velocity within
  a few ticks of ground contact.** A mantle carry / knockback that touches down is clamped to
  the wish target before the player perceives it. Fix: give the effect enough airtime (ballistic
  hop) so propulsion lives where the servo can't reach.
- **In a trace-swept NPC steer loop, "wall ahead, hold position" is a permanent freeze when the
  desired direction is constant.** The same trace hits the same wall every frame. Fix: project
  the step onto the wall plane and sweep the slide direction; hold only on a dead-on hit.
- **Absolute-altitude biome thresholds break when height amplitude changes.** Scale every climate
  altitude by `max(amp, refAmp)/refAmp`; clamp k >= 1 to prevent snow-on-mesa fraction bugs;
  leave sea-relative dials unscaled.
- **`Input.config` `KeyboardCode` for punctuation keys is the LITERAL CHARACTER (`"["`,
  `"]"`), not a `KEY_`-enum-derived name.** A wrong name like `"lbracket"` fails silently
  (action never fires, no warning at load or bind time). Check the engine's
  `KeyboardCode` enum or test with `Input.Keyboard.Pressed("char")` to confirm.

- **Visible cursor blocks ALL game mouse input with no raw bypass** — `Input.Down/Pressed` for a button eaten by a pointer-events panel never fires; `Input.Keyboard.Down("mouse2")` reads the same gated store; `Input.AnalogLook`/`MouseDelta` are hard-zeroed. A hold-to-look mode must actually lock the cursor.
- **Chase camera reading raw fixed-tick position causes model sawtooth** — the raw field is a 50 Hz staircase; read `chr.WorldPosition` (context-sensitive interpolated getter) instead for smooth per-frame tracking.
- **Mover riding coarse collision heightfield bobs on a visually smooth surface** — reproduce the render mesher's surface at the feet XY and ride it in the fixed tick, scoped to vertical ground-follow only.
