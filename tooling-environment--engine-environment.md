# Tooling & environment — engine environment

> Topic sub-file of this lane — router: `tooling-environment.md` (its "Where everything lives"
> table maps every topic). Load `_core.md` first. Bullets below are moved verbatim
> from the lane pack; the sync appends new bullets for these topics here.

## Engine environment

- **`new System.Random` (time-seeded) IS whitelisted** — compiles + runs headless. Useful
 for per-LOAD procedural variation (verified: one project arched-roof open-pane picker uses
 `new System.Random(); rng.Next(n)`). Note the earlier "no crypto RNG" gotcha is specifically
 about `HashCode.GenerateGlobalSeed`/`RandomNumberGenerator`, NOT `System.Random`.

- **Arch/slope tilt axis: rotate about `Vector3.Forward` (+X), not `Rotation.From`'s pitch.**
 For a slab whose up-face must slope ALONG y (an arch rising across y), `Rotation.From(pitch,..)`
 rotates about Y and slopes along x (wrong). Use `Rotation.FromAxis(Vector3.Forward, deg)` to roll
 +Z toward ±Y. Sign still needs one visual confirm (rotation-sign gotcha above): one project's
 arch uses `-pitchDeg` so +Z leans DOWNHILL — flip if it reads as a valley/twist.

- **A `FacingYawOffset` (mesh-facing correction) SWAPS which `_baseRot` local axis is the
 flip axis vs the cartwheel axis — a front flip is `_baseRot.Forward`, NOT `.Right`, when
 the offset is ±90.** one project's hero character uses `FacingYawOffset = -90` (AI-generated (Tripo-style)
 meshes face mesh-local −Y). The rotation returned by `ComputeRotation` bakes the −90 into
 its yaw, so for a character traveling world +X: `_baseRot.Forward = -Y`, `_baseRot.Right = -X`,
 `_baseRot.Left = +X` (the visual NOSE/travel dir). A front flip pitches the nose over its
 own LEFT-RIGHT axis = world ±Y = **`_baseRot.Forward`** here; `_baseRot.Right` (world -X) is
 PARALLEL to travel → an aileron **CARTWHEEL** ("goes sideways, all the way around"). Both the
 charged somersault and the air-flap barrel roll had copied `_baseRot.Right` (naive "Right =
 pitch axis" from the no-offset convention) and were latent cartwheels. Fix:
 `Rotation.FromAxis( _baseRot.Forward, t * -360f ) * _baseRot` (NEGATIVE sign: at −90° the
 nose(+X) pitches to −Z = dives forward/down = front flip; +90° backflips). DON'T hand-guess
 the axis — PROVE it: a scratch net10.0 console referencing the real `Sandbox.System.dll`
 (`bin/managed/`, net8 crashes on Vector3 binding) evaluating `Rotation.From(0,yaw,0).{Forward,
 Right,Up}` classifies each axis against the travel dir in seconds.

- **Deriving a visual's FACING from horizontal velocity flips 180° on any momentum reversal —
 lock facing to an attach-time azimuth for pendulums/oscillators, don't re-derive it each tick.**
 A rope-swing visual that set `fwd = horiz.Normal` snapped the body around every time the
 pendulum reversed (owner: "I go forward then start going backwards and I turn the other way —
 weird; a kid on a swing keeps facing and swings BACKWARD"). Root cause: horizontal velocity's
 SIGN reverses at every arc endpoint, so a velocity-heading facing is discontinuous. Fix: pick a
 facing azimuth ONCE at attach (from the initial swing impulse), hold it constant, and only
 re-aim it on DELIBERATE steering input (A/D past a threshold rotates it a fixed step) — never
 from the velocity sign. Feed it to the visual through a dedicated continuous channel
 (`Character.SwingForward`), the same fix the BAR spin already used (the spin tangent is continuous
 over the top; the pendulum azimuth is continuous through a reversal). BARS keep their spin-sense
 facing; only the POINT/tire pendulum needed the azimuth lock. General rule: any body whose
 velocity oscillates (pendulum, ping-pong platform, reversing patrol) must NOT face its velocity
 heading — face a locked/steered heading, or it strobes.

- **A camera that switches FOCUS TARGET or FOLLOW DISTANCE on a state change jerks even when the
 camera POSITION is already exponentially smoothed — smooth the target, not just the follower.**
 one project's chase-cam focused the swing ANCHOR (×1.5 distance) while swinging and the BODY
 (×1.0) otherwise; the position lerp (`Lerp(pos, desired, 1−e^−kt)`) hid steady motion but on
 dismount the `desired` TARGET jumped in one tick, and lerping toward a snapped target reads as a
 velocity kink ("jerky when I dismount"). Fix: ease the focus point + follow distance toward
 their raw per-state values through their OWN exponential (a separate `_smoothFocus`/`_smoothDist`
 at a rate SLOWER than the position lerp, ~5 vs 12), so the target glides across the Swing↔Air
 framing switch and the position lerp never chases a discontinuity. Seed the smoothed values on
 the first valid frame or they glide in from the origin.

- **An input press consumed at the bottom of the fixed tick is LOST across a state transition
 that `return`s early — buffer it.** Character's swing RELEASE branch flips to Air and `return`s;
 the shared `_jumpPressed` edge is then cleared at the end of OnFixedUpdate before TickAir ever
 runs, so a Jump pressed ON the release frame silently ate the dismount→jump. Fix: handle the
 press inline in the release branch (launch immediately), AND arm a short buffer timer
 (`TimeSince`, ~0.2 s) that TickAir checks so a press landing a frame or two LATER still fires the
 same release-jump. Buffering both the on-frame and just-after cases makes the dismount→jump feel
 continuous regardless of exact press timing.

- **Pure-nearest target selection re-grabs the anchor you just left — score by DIRECTION OF
 TRAVEL and exclude the just-released target briefly.** one project's `NearestGrabpoint` was
 distance-only, so dismounting a swing and grabbing again yanked the character BACK to the same
 anchor even after flinging toward a closer new one (owner: "pulls me back to the thing I just
 dismounted"). Fix: (a) remember the released anchor and EXCLUDE it from re-selection for a window
 (~0.8 s, longer than the same-anchor debounce cooldown), falling back to it only if nothing else
 is in reach (never a dead grab); (b) bias the score toward travel: `score = dist × (1 −
 Bias×align)` where `align = dot(toTarget.Normal, velocity.Normal)` ∈[−1,1], so an anchor ahead
 scores as if closer and one behind as if farther (a slightly-farther anchor in the fling
 direction beats a closer one behind) — gate the bias off below a min speed so a slow/hanging
 body has no false travel direction. Log the decision (chosen vs nearest-rejected + why) for
 tuning. Radii left as-is (GrabRadius 2.6 m hand / TailHookRadius 4.0 m airborne) — they weren't
 fighting chaining; the SELECTION was.

- **Whitelist:** `Http` may call any domain (not raw IPs). Vendored libs need patches:
 no `System.Console`, no crypto RNG (`HashCode.GenerateGlobalSeed`), no
 `Environment.NewLine`. `System.Text.Json`, `ArrayPool`, `GameTask.RunInThreadAsync`
 are all fine.

- **Hotload:** C# edits apply in ~ms on alt-tab. Network sessions reset on hotload;
 scene-file changes need a Play restart; new assets sometimes need an editor kick.

- **Fixing a source asset does NOT always trigger a recompile of a previously-FAILED
 asset** — the engine can keep serving the stale `_c` baked from the broken version
 (ERROR models / white materials persist across editor restarts). AND deleting the
 `_c` alone is NOT enough: with an unchanged source mtime the engine just reports
 `ERROR_FILEOPEN` on the missing `_c` without recompiling. The reliable sequence is
 BOTH: delete `.vmdl_c`/`.vmat_c`/`*generated*` artifacts AND `os.utime` the source
 files so the watcher marks them dirty, then kick the editor.
 A small fix-up script that deletes the stale `_c` and re-touches (`os.utime`) the sources automates this after any asset regeneration.

- **Engine console noise is normal**: missing `citizen_clothes/…`, `sfm` sounds,
 `menu-main.scene` sounds, wheely-bin gibs etc. are broken refs inside Facepunch's own
 base content — never ours. Vulkan `QueuePresentAndWait`/`VK_TIMEOUT` = driver-level
 present stall (alt-tab/shader compile), not game code.

- **BoxCollider.Center/.Scale are ALWAYS in the model's own native (unscaled) local
 units, never world units** — the engine multiplies by the GameObject's WorldScale
 automatically (this is exactly why BoxCollider, unlike Capsule/ModelCollider, "follows
 WorldScale": the follow-through happens because the collider's own numbers stay in
 local space and get scaled downstream). The established pattern everywhere in this repo
 is literally `c.Center = model.Bounds.Center; c.Scale = model.Bounds.Size;` — bounds are
 already native-unit, so no conversion is needed for a bounds-fit box. The mistake is
 reaching for a DESIRED WORLD-SPACE size (e.g. "a 24 cm trunk radius") and assigning it
 directly to `c.Scale`: on a GameObject scaled up 5-10× (a normalized 1 m Kenney mesh
 stretched to a 4 m tree) that world-space box would compile fine but end up 5-10× too
 BIG in-engine. Fix: divide the desired world size by `go.WorldScale` (or the relevant
 axis) before assigning, the mirror-image of the CapsuleCollider/ModelCollider bake-scale
 fix already in this file — BoxCollider needs a divide-back, those need a baked-in scale.

 **Second confirmed instance + companion bug**: a component authored assuming
 `WorldScale==1` (a bounce-pad mushroom whose stem `BoxCollider` used raw world-meter
 constants like `0.34f*M` half-width) breaks the moment a caller sets a different
 WorldScale (e.g. spawning size-VARIANTS of the same prop) — the constant needs
 dividing by `WorldScale` before assignment, same as above. The COMPANION mistake in
 the same component: a `model.Bounds` field (e.g. `Bounds.Maxs.z`) used to compute an
 absolute WORLD-space value (a bounce plane's world Z) must be MULTIPLIED by
 `WorldScale` first — bounds are native/unscaled, so using them raw in world-space
 math is correct only at scale 1. Before scaling any existing component via
 `GameObject.WorldScale`, grep its OnStart/OnAwake for both directions of this bug.

- **A self-swept projectile + a separate "did it hit me" detector must NOT both collide with the same collider — the projectile bounces off before the detector's poll runs.** one project's sweep-traces its own ballistic path each fixed tick; BreakableGlass polls live props for a plane-crossing to shatter. Both saw the pane's collider, so (with no guaranteed OnFixedUpdate order between the two components) the prop's flight trace hit the glass and bounced BACK before the glass ever detected the crossing → the pane never broke. Fix: tag the breakable collider with a distinct tag (`"breakable_glass"`) and have the projectile's flight trace `.WithoutTags("breakable_glass")` so it PASSES THROUGH, while the detector (and the character's wall-run/collision, which don't exclude the tag) still treat it as solid. General rule: when object A is meant to pass a barrier that a poller B watches for the crossing of, A's trace must exclude B's collider tag — don't rely on tick order.

- **Free a penned AI by WIDENING its public wander rect, not by scripting an exit path.** one project's openable area frees pen animals by growing each AnimalNpc's public `[Property] PenMin/PenMax` rect to a box centred OUTSIDE the opening — its own wander AI (which reads PenMin/PenMax live each PickWanderTarget) then paths it out through the gap on its own, no bespoke escort code, no reach into AnimalNpc internals. The one catch: the opening must line up with an actual GAP in the containing fence, or the sphere-traced movers pile up against it. Put the openable door AT the pre-existing walk-path gate gap (FencePen already skips fence panels inside a walk corridor) so door-open == fence-open at the same x.

- **Coplanar overlay ribbons z-fight — give each layer its own lift.** Roads and walk paths both seated at `terrain + 0.06 m` produced camera-dependent tan streaks wherever a path's segment overlapped a road (every path starts on one). One shared lift constant for two overlay types = guaranteed z-fight at every junction. Fix: layer the lifts (roads 0.06, walk paths 0.04) so the intended winner always renders on top; both stay proud of terrain. General rule: any two procedurally-laid coplanar surfaces need an explicit z-order via distinct lifts.

- **Hysteresis lives in the CONSUMER, never in the stateless predicate tests read.** The guard's 15 Hz Spotted/LostSight flap: `TryCatchScan` read raw `CanSee(character)` per frame; on a "seen" frame the guard turned toward the character, on the next the patrol mover re-aimed his gaze at the waypoint, flipping the cone verdict — two facing authorities fighting at frame rate, so pursue never accumulated. Fix pattern: keep `CanSee` a pure stateless truth table (the test scenarios assert its exact per-gate reasons), add a `SeesSticky(target, dt)` wrapper that (a) holds sight until the lose-condition persists ~0.6 s and (b) widens the effective cone hugely under 3 m (nobody loses a character at their feet by turning their head), and make the tracking state own facing for the whole tick. Sight telemetry logs on rising/falling EDGES only.

- **Third-person camera occlusion: ease asymmetrically and tag-exclude thin structure — never pull in instantly.** An occlusion trace that snaps the boom to every hit turns any beam/rib thicket into per-frame distance jitter (the roof-swing jank). The fix trio: (1) ease the pull-IN too (fast k≈22), keep recovery slow (k≈6); (2) ignore transient slivers — a clamp shortening the boom <0.6 m while the prior clamp is clear is a rib ticking past, not a wall; (3) give thin structural members a `camstruct-ignore` tag excluded from the CAMERA trace only (they stay solid for movement) — a beam briefly crossing the lens beats a distance snap. Related: on play-start, SNAP the camera to its fully-resolved pose on first acquire, then ease — lerping out of the menu-camera's pose reads as "camera starts too close and crawls out".

- **SoundHandle spin-up: freshly-played handles report IsPlaying=false for a frame or two.** A loop-retrigger keyed on `!IsPlaying` fires overlapping duplicate plays every spin-up frame — stacked copies read as a garbled rumble. Retrigger only on invalid-or-Finished, and Stop any lingering handle before replacing it.

- **Copied trace exclusion filters invert meaning across call sites - re-derive "who am I,
 who is the target, who is noise?" at every copy.** `.IgnoreGameObjectHierarchy(GameObject)`
 copied from SwingRope.ResolveRoofMount (correct: a rope raycasting UP for the roof must skip
 its own knot/segments) into ClimbNodeField.TraceInward (fatal: the field lives ON the tower
 it surface-fits, so it ignored the very collider it was fitting - every inward ray missed,
 0 nodes placed on every tower, the whole cylinder climb dead, silently). For surface-fitting
 prefer a POSITIVE filter: accept only hits on the intended hierarchy, stepping past foreign
 hits - also stops neighbouring geometry donating phantom nodes.

- **Visual "pin hands/feet to a world feature" welds = the DIFFERENCE of two measured lengths,
 never either length alone** - (physics offset of the root from the feature) minus (measured
 offset of the body part above the root in the ACTIVE clip). The bar-swing weld lifted the
 mesh by the full BarSwingRadius (0.7 m) when the bar_spin clip's hands already sit a measured
 0.664 m up the body - hands ended 0.66 m PAST the bar (owner: upside-down character, hands on
 nothing). Correct lift = 0.7 - 0.664 = ~0.04 m. Each swing surface plays its OWN clip
 (bar_spin vs hm_swing), so each gets its OWN measured constant (tools/measure_hang_pose.py
 measures both).

- **A [telemetry] boot line gated behind a debug/viz flag is not telemetry.** ClimbNodeField's
 only per-field boot line lived inside BuildDebugViz, so ShowDebug=false would have hidden
 the one line proving a field was dead (0 valid nodes). Emit per-system boot proof lines
 unconditionally in OnStart; gate only the visuals. Pair with a loud WARN on the dead state
 itself.

- **Nearest/Best pickers need an honest EMPTY answer** - ClimbNodeField.Nearest fell back to
 `_nodes[0]` when no valid node existed, which for a failed cylinder fit was an INVALID gap
 node at the trunk AXIS: climb entry teleported the body INSIDE the mesh and instantly
 ejected (Air->Climb->Air flicker). Return null and make the caller fall back explicitly
 (free climb + warn).

- **Build-time tag scans are blind to children built in a component's OnStart** - SwingRope
 builds its tagged knot child on its first enabled frame, AFTER the world Build returns, so
 any boot audit scanning for "grabpoint" tags undercounts every rope (fixed-web=15/26 with 4
 spurious gap-fillers patching holes that closed a frame later). Fix pattern: a single
 COMPONENT-DERIVED census - derive each future child's rest position from the component's own
 fields (pivot + Down*Length, exactly what OnStart will seed) under the name it will get, and
 name-dedupe so a post-frame-1 run counts identically; all consumers share the one census.

- **`Angles` struct fields are lowercase `.pitch/.yaw/.roll`, `Vector3` fields are lowercase
 `.x/.y/.z` — do NOT trust capitalized `.Pitch/.Yaw/.Roll` sightings elsewhere in a codebase
 as proof of the struct's own casing.** Grepping this dev folder turns up BOTH casings: the
 lowercase form on `Angles`/`Vector3` themselves (e.g. `heading.x, heading.y`, and the
 shipped avatar-editor addon's `_angle.yaw`/`_angle.pitch`/`_angle.roll`), and a capitalized form that belongs to unrelated
 component properties (e.g. `CitizenAnimationHelper.Pitch/Yaw/Roll` are the animation rig's
 own float properties, nothing to do with the `Angles` struct). Confirm field casing against a
 usage of the SPECIFIC type you're touching, not the first case-matching hit in a repo grep —
 it's a silent wrong-value bug (compiles fine, animation/camera math is just off), not a
 compile error.

- **`System.Text.Json.Nodes.JsonNode` has implicit conversions from primitives (int, long,
 float, string, bool, …) since .NET 8** — `new JsonObject { ["key"] = someInt }` and
 `new JsonArray { someFloat, someFloat }` just work, no `JsonValue.Create()` wrapping needed.
 Confirmed against the net10.0 TFM s&box projects use. Reach for this (not `Sandbox.Json.
 Serialize`) whenever an `[McpTool]`'s return contract mandates exact key names/casing —
 hand-building the `JsonObject` guarantees the keys match the contract regardless of whatever
 naming policy the engine's own serializer defaults to.

- **An aimed bot grabbing through a scored "best in reach" selector must hold grab ONLY while
 the intended target is inside hand reach** — holding at intent time catches whichever
 bystander enters the assist window first (11/11 wrong-grabs across three an agent suite
 runs had the wanted element ≥3.5 m away at the steal). Check where the hand-open sphere
 trips along the approach: a bystander equidistant at that point coin-flips the selector —
 shrink the window past the crossover.

- **A bar's release can only be aimed within its spin plane** — max velocity·target align =
 |target direction projected into the plane| (measured: a release at 0.56 vs computed cap
 0.57). Release gates above the geometric cap never fire; the pendulum creeps to the orbit
 top and stalls. Compute the cap per hop, gate under it, log best-seen align on every
 timeout.

- **Threshold-pair event detectors die on smooth physics: check the transition is producible
 in ONE fixed tick.** `prevVz > 0.5 && vz <= 0` can never fire under gravity at 50 Hz
 (~0.2 m/s per tick through zero); a bounce-pad impact IS one-tick detectable
 (≤−1.5 → ≥+1.5 flip).

- **There is NO scene/global time-scale API in the game-reachable engine surface (26.07).**
  `Scene.TimeScale` does not exist; the only `TimeScale` anywhere is
  `ParticleEffect.TimeScale`/`PerParticleTimeScale`. Slow-motion must be faked with a custom
  multiplier applied to delta-time in your own update loops. → [fix article](/fix/no-scene-timescale-api)

- **The stock `PlayerController` exposes NO public speed property.** `WalkSpeed`/`RunSpeed`/
  `DuckedSpeed` are private serialized `[Property]` fields. Game code cannot cleanly scale
  player move speed (e.g. for a slow debuff). Write your own controller or reflection-hack
  the privates (fragile across updates). → [fix article](/fix/playercontroller-no-public-speed-property)

- **Re-setting a `[ConVar]` to the value it already holds is a SILENT no-op** -- the property
  setter never runs. Because statics survive Play stop/start, a convar-triggered action from
  a prior session leaves the convar "already set," so a fresh session's identical command does
  nothing. Fix: toggle to a different value first, or reset the backing static on boot. → [fix article](/fix/convar-same-value-set-is-silent-noop)

- **`new System.Random` (time-seeded) IS whitelisted** — compiles + runs headless. Useful for per-LOAD procedural variation (verified: arched-roof open-pane picker uses `new System.Random(); rng.Next(n)`). Note the earlier "no crypto RNG" gotcha is specifically about `HashCode.GenerateGlobalSeed`/`RandomNumberGenerator`, NOT `System.Random`.

- **Fixing a generator whose bad emitted data a consumer already compensates for = DOUBLE-correction unless the contract is versioned.** The part-kit C# loader corrected the manifest's 180°-yawed `local_bounds_*` inside `BoundsCenterM`; fixing the python emitter to write true values would have silently re-broken every collider centre on new kits (correct data + legacy correction = wrong again). Fix pattern: bump the manifest schema id (`partkit/1` → `/2`), normalize LEGACY data once at load into the true convention, and make every downstream consumer convention-free — never leave a compensating transform inline in a consumer, because the next producer fix can't see it. Equivalence of the v1 path is provable by algebra (−(min+max)/2 on recorded == +(min+max)/2 on normalized) — check that before trusting a normalization refactor.

- **The `NodeClimbOn` routine op dismounts by KICKING OFF the wall (a climb/wall jump away from the face), landing back on the FLOOR — it is NOT a top-mantle onto whatever sits above.** (TickNodeClimb phase 3: `_jumpLatch` then `return State==Ground`.) So an automated MULTI-STAGE climb (climb panel1 → stand on a ledge → climb panel2 off that ledge) is NOT achievable in a single routine: after stage 1 the piloted character is on the ground to the SIDE of the face, never on the ledge, and stage 2's field (based up at ledge height) is then unreachable from the floor. Build the staged structure as an OWNER-PLAYABLE layout feature, cover each stage's climb field with the climb-fields boot audit, and have the automated routine climb the reachable BASE stage only.

- **A Standalone export differs from the editor/published-client runtime in ways that break editor-built tooling (verified live, engine 26.07.22).** (1) `FileSystem.Data` = `data\.local\<ident>\`, NOT `data\<org>\<ident>\`; (2) logs go to `logs\<ident>.log`, not `sbox*.log`; (3) console `quit` THROWS (kill the process externally — a per-frame quit-retry loop wrote a 102 MB log in minutes); (4) it boots straight into the game (`StandaloneAppSystem.Init` calls `CreateGame`, never `CreateMenu`). Also: `+game <ident>` joins a session but `-rungame <ident>` only opens the package-page modal; game-assembly convars take command-line `+value` at REGISTRATION time (`ConVarSystem.AddConVar` re-reads the command line as each convar registers). → [fix article](/fix/standalone-export-runtime-differs)

- **Blocking the main thread on a `Task` from `GameTask.RunInThreadAsync` (`.Result`/`.Wait()`) is a PERMANENT, silent deadlock — not a slow await (engine 26.07.22).** The process stays alive and the window still responds, but the frame loop is dead: nothing renders, any automation bridge stops answering, and the log just stops (often right after a non-yielding-async warning). Mechanism (`TaskSource.cs`): the task's `await` captures the main thread's `ExpirableSynchronizationContext`, whose continuation queue is drained *by the frame loop* — a main thread parked in `.Result` can never tick it, so the completion is undispatchable. Safe: only `await` these tasks; if you need a sync result on the main thread, compute it synchronously instead of routing through `RunInThreadAsync`; worker threads may block on them freely. Sweep game/gamemenu code for `.Result`/`.Wait(` on `RunInThreadAsync` results reachable from a main-thread path. → [fix article](/fix/runinthreadasync-mainthread-deadlocks)

- **The repeating red `Texture manager doesn't know about texture "materials/default/default_mask_tga_<hash>.generated.vtex" ... returning error texture in CTextureManagerVK::GetImageView` pair on `engine/RenderSystem` is base-menu-addon noise, not your project, and cannot be muted from game code (engine 26.07.22).** It repeats PER DRAW CALL (hundreds of lines per broken surface on screen). Prove ownership via the sibling `engine/ResourceSystem` line's `- from <referrer>` suffix: the referrers are compiled-only base-menu materials under `addons/menu/Transients/...` whose baked `default_mask` reference resolves to no file on disk. The editor mounts that transients folder into every non-menu project (`StartupLoadProject.UpdateProjectFilesystem`, id `mod_engtrans`), so it leaks into every game's console. `Sandbox.Diagnostics.Logging` is `internal` and native log commands are `IsProtected`, so game code can't silence it; and a channel mute would also hide your OWN texture errors. Filter visually, report upstream. → [fix article](/fix/base-content-error-texture-console-flood)

- **A library's `Assets/` folder created AFTER the s&box editor started never mounts: code under `Code/` hotloads fine, but the new asset folder stays invisible — asset search returns nothing under it and `asset_info` reports no asset.** Not a dead watcher (a file written into an ALREADY-mounted folder still indexes within seconds): the mount is established at editor startup and there is no rescan/remount command or API. The only fix is restarting the editor. Practical rule: any change that adds the FIRST assets to a previously asset-less library needs an editor restart before those assets are testable, even though the code side hotloads without one. Distinct from a library never registered as a project at all (missing `.sbproj`) — this fires on a library already discovered and compiling, purely on the asset-mount side. → [fix article](/fix/new-library-assets-folder-needs-editor-restart)

- **"Render-only" is a claim about what a change WRITES; "hash-neutral" also requires it alters nothing the SIMULATION later READS — a change can satisfy the first and fail the second.** Measured: setting a friction value on detach-spawned debris colliders moved a determinism hash, because shed debris is a SIMULATED body — friction changes where it lands, whether the car re-contacts it, and a contact writes ordinary damage. The leak signature is ACCUMULATION-ONLY (single-hit pins stayed identical; the 24-hit walk moved), so a determinism suite needs BOTH single-hit and multi-hit instruments — they have different blindness. Pin cause by elimination (enumerate the executable delta, grep for writes to hashed state, run the feature's own convar control), then re-baseline with the documented cause rather than treating a proven moved baseline as a regression.

- **`Scene.NavMesh.IsGenerating` never goes true for a TILE regeneration request (`RequestTilesGeneration`); it only reports a FULL rebuild (`NavMesh.Generate`).** Polling it after a tile request reads "not generating" on the very next frame, which looks like completion but is the flag never having moved. A path query fired then lands about 90 ms too early and comes back `Partial` (a short route that walks up to the hole and stops), which reads as "the tile API is inert from game code". It is not inert: the regen runs and takes about 100 ms, `IsGenerating` just never announces it for this call. A full rebuild GENUINELY does raise `IsGenerating` (49 to 159 ms observed), so an A/B looks like a clean mechanism difference when both arms are actually correct. Fix: never gate a tile-regen wait on `IsGenerating`, poll the POSTCONDITION instead, retry the actual query you need (`CalculatePath`, `GetClosestPoint`) on a short interval until it returns a real answer or a deadline passes.

- **A custom `[AssetType]` extension can lose a registration race against an engine-owned extension, and which side wins is decided PER EDITOR LAUNCH, not fixed by the commit.** The engine registers its own type on some extensions out of the box (for example `[AssetType(Name = "Ammo Type", Extension = "ammo", Category = "Game")]`); a project type claiming the same letters collides, and the LOSING type's `ResourceLibrary.GetAll<T>()` returns an empty sequence with no error, no warning, no console line. The identical commit on the identical build produced OPPOSITE outcomes across two launches ten minutes apart. `asset_types` in a live editor is the tell: two registrations can share a display `Name`, so check `Category` and which one claims the `Extension`, never the name string alone. When the custom type loses, every file on that extension deserialises as the ENGINE's type instead, so a consumer trusting "empty result = nothing of mine" can receive a foreign asset with every field at its C# default. Audit a custom extension with `asset_types` before committing to it, and make any `GetAll<T>()` path detect the empty or foreign-data case explicitly.

- **In the EDITOR the asset system brings a project's own game resources in unasked, so a custom `GameResource` type loads with OR without an `.sbproj` `Resources` glob, and an editor-only experiment can never tell the two apart.** Measured on a worktree no editor had opened: five custom resources loaded with no glob entry. The glob is still load-bearing for PACKAGING a published build, a question the editor never asks. Two corollaries: `@unreferenced` in the asset browser means nothing points AT the resource, not that it is unloaded, so it is a hint, never a verdict; and an experiment about resource LOADING run while an extension-registration race is live measures the race, not the loading (while the engine owned the extension, `GetAll<T>()` returned nothing whether the files loaded or not). Accept a race fix only after running it twice across a FULL restart, and re-run every conclusion recorded while the race was live.
