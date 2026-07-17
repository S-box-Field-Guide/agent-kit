# Tooling & environment — skill pack

> Lane pack. Load `_core.md` first, then this file. Denser than the full articles by design;
> for a matching bullet's full write-up, follow that gotcha's article link in `coverage.md`
> (full articles live on the Field Guide website, not in this pack). Sanitized public
> advice; unconfirmed details marked `(needs verification)`. The sync appends new bullets here.

## Engine environment

- **`new System.Random` (time-seeded) IS whitelisted** — compiles + runs headless. Useful
 for per-LOAD procedural variation (verified: one project arched-roof open-pane picker uses
 `new System.Random; rng.Next(n)`). Note the earlier "no crypto RNG" gotcha is specifically
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

## Tooling (see tooling.md for detail)

- **PowerShell 5.1 corrupts UTF-8 on bulk edits** (`Get-Content`/`Set-Content` reads
 BOM-less UTF-8 as ANSI → emoji/dash mojibake). Use python or byte-safe .NET file APIs.
- **Some C# source files in one project are CRLF, and a `\n`-based string-replace edit
 silently fails to match them** (the search string has `\n`, the file has `\r\n`, so the
 multi-line `old_string` never hits — the byte content otherwise looks identical under
 `od -c` per-line, which hides the `\r`). Symptom: an exact-looking edit reports "string
 not found" repeatedly on a block you can see in the file. Diagnose with
 `python -c "print(b'\r\n' in open(p,'rb').read)"`; fix by editing via a python
 byte-level `data.replace(old_bytes, new_bytes)` with `\r\n` in the literals (assert the
 match count is 1 first), then write back `'wb'`. Mixed in the same repo — ProjectileTuning.cs
 is CRLF, ProjectileSplat.cs is LF — so check per file.
- Verify compiles without the editor: `dotnet build Code/<proj>.csproj` — the csproj
 references the Steam s&box install directly. Do this after every batch of edits.
- **A stalled Steam update half-deletes the s&box install — close the launcher.** If
 `sbox-launcher.exe` stays running across an update (e.g. left open overnight), Steam
 downloads + stages the update but can't commit while files are in use, and the install
 ends up missing files: `sbox-dev.exe` gone (launcher's "open project" silently fails —
 no window, error only in `sbox/logs/sbox-launcher.log`), random dlls gone
 (`Sandbox.CodeUpgrader.dll` → all headless `dotnet build`s fail with CS0006 from
 `Base Library.csproj`). Diagnose: `steamapps/appmanifest_590830.acf` StateFlags ≠ 4
 with 100% BytesStaged. Fix: kill the launcher, run `steam://validate/590830`, wait for
 StateFlags 4. Don't "fix" the csprojs — they were never broken.
- **`dotnet build` warning counts lie under incremental builds** — warnings are only
 re-emitted for files that actually recompile, so a stale-output build happily prints
 `0 Warning(s)` over a tree that carries warnings. Any build-gate claim (docs,
 feature-matrix headers, agent verify clauses) must come from
 `dotnet build --no-incremental` (or a clean). Per-agent scope checks can stay
 incremental — it's the WHOLE-TREE 0/0 claims that need the rebuild.
- **A one-shot "commandeer + suspend competing drivers" sweep misses components created
 AFTER it runs** — one project's benchmark flythrough suspended everything on the camera
 GameObject at scene start, but Bootstrap.StartPlay creates ChaseCamera on that same
 GameObject ~1 s later (menu -> play transition), so it was never suspended and fought the
 flythrough every frame (its leash invariant hard-snapped the camera back to the player
 every ~2 s -> the visible "camera disjointed / sliding away"). Any commandeer pattern must
 either re-sweep for newborn drivers every tick (cheap on one GameObject) or hook the
 creation path; a suspension list built once is a scope-hole of the same class as a
 one-shot audit exemption. Diagnosis shortcut: if a misbehavior's telemetry warns cluster
 EXACTLY inside another system's active window, suspect a two-writers fight, not a broken
 writer.
- **The editor compiler can crash internally (NullReferenceException, "One or more errors
 occurred") and WEDGE: `compile_status` then reads `success=False` with 0 errors/0 warnings
 AND `needsBuild=False`** — it thinks nothing needs rebuilding while the last compile failed,
 so the editor silently keeps running the stale assembly forever. No code error exists to fix.
 Recovery: bump any watched source file's mtime (PowerShell `(Get-Item file.cs).LastWriteTime
 = Get-Date`) to dirty the compile; it rebuilds clean. Detect via the MCP `compile_status`
 (success=False + 0 diagnostics + needsBuild=False is the wedge signature).
- **Steam can update the s&box engine UNDERNEATH a running editor** — files swap mid-session
 and the symptoms look like impossible compiler bugs, in escalating order (observed 2026-07-10,
 26.07.08c->e): hotload "Failed to clean" reflection noise -> an internal Roslyn NRE
 (`GetExtensionContainers`) wedging the compiler (success=False, 0 diagnostics) -> on restart,
 `SerializationDeprecationException` + "Errors when loading 'Sandbox.Project'" (mixed-version
 DLLs), the scene deserializing with project components STRIPPED (MissingComponent — do NOT
 save the scene in that state, the on-disk file is still good), the package never mounting
 (type registry empty, nothing plays) -> "Could not find sbox-dev.exe" if relaunched while
 Steam stages that exact file. FIRST CHECK for any inexplicable editor-internal crash:
 `sbox/.version` mtime vs your session start (also `appmanifest_590830.acf` StateFlags —
 4 + all BytesStaged = update complete). Recovery once the update finishes: relaunch, discard
 scene changes, verify headless `dotnet build --no-incremental` against the NEW engine
 assemblies before trusting anything.
- **The s&box editor runs an MCP server on `http://127.0.0.1:7269/mcp`** — the
 headless verification loop for assets. Launch `sbox-dev.exe -project <sbproj>` in
 the background, then JSON-RPC `tools/call` → `call_tool` wrapping: `asset_compile`
 (returns Success/CompiledFile — THE way to verify a vmdl compiles), `asset_info`,
 `spawn_model` + `set_editor_camera` + `editor_camera_screenshot` (base64 PNG — eyes
 in the engine: verify orientation/scale against a known-good model side by side),
 `read_console`, `play_start/stop`, scene CRUD. `list_toolsets`/`describe_toolset`
 to discover schemas. Spawned objects live in the unsaved scene — don't save and
 they clean themselves up on exit.
- **Reusing another project's assets = copy with identical root-relative paths.** vmdl
 files reference their .obj and .vmat by project-root-relative path, so copying
 `models/tree_oak.*` + `materials/flat/*.vmat` +
 `materials/textures/white.png` into the same subfolders of the new project
 works with zero edits. Copy the source files only (.obj/.mtl/.vmdl/.vmat/.png), not
 the compiled `*_c`.
- **Kenney's own nature pack is an even
 easier zero-edit borrow than another project's**: every vmdl there references its mesh as
 `models/kenney/nature/<name>.fbx` and a SHARED `models/kenney/nature/materials/*.vmat`
 folder (one universal `DefaultMaterialGroup` remap table, identical across all 20
 vmdls), and every one of those vmats points only at the ENGINE's own
 `materials/default/default_{color,normal,rough}.tga` — no project-local textures at
 all, just a `g_vColorTint` per material. So copying the vmdl+fbx pair for each chosen
 species plus the whole `materials/` folder into the same `models/kenney/nature/`
 subpath in the new project needs LITERALLY zero path edits. Kenney's `nature/` folder is the source for trees/pines/bushes/rocks/flowers/cliffs. Kenney's pack has NO
 dedicated grass-tuft mesh — reuse a small-scaled `plant_bush.vmdl` as the "tuft" stand-in
 until a real grass model is generated.
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

- **s&box whitelist is only enforced by the IN-EDITOR compiler** - `dotnet build` passes code that the game runtime then rejects (e.g. `Environment.TickCount` -> SB1000 whitelist violation). Fix: engine surfaces only (`Time.Now`-derived entropy for seeds, `System.Random(int)` itself IS whitelisted). Sweep agent code for `Environment.*`, `System.IO`, `Process`, `Thread` before shipping.

- **Runtime reflection is ALSO whitelist-banned** in s&box game code - `Type.GetProperty`/`PropertyInfo.SetValue` -> SB1000, same as `Environment.*`. Never use reflection as a cross-file workaround for a property another agent owns; emit a HANDOFF instead.

- **Model.Load of a MISSING vmdl can return the error model with the REQUESTED path as its Name** - the classic `Name.Contains("error")` check passes and you spawn the engine's giant orange ERROR-text mesh. Robust gate: `model == null || model.IsError || model.Name.Contains("error")`.

- **A self-swept projectile + a separate "did it hit me" detector must NOT both collide with the same collider — the projectile bounces off before the detector's poll runs.** one project's ThrowableProp sweep-traces its own ballistic path each fixed tick; BreakableGlass polls live props for a plane-crossing to shatter. Both saw the pane's collider, so (with no guaranteed OnFixedUpdate order between the two components) the prop's flight trace hit the glass and bounced BACK before the glass ever detected the crossing → the pane never broke. Fix: tag the breakable collider with a distinct tag (`"breakable_glass"`) and have the projectile's flight trace `.WithoutTags("breakable_glass")` so it PASSES THROUGH, while the detector (and the character's wall-run/collision, which don't exclude the tag) still treat it as solid. General rule: when object A is meant to pass a barrier that a poller B watches for the crossing of, A's trace must exclude B's collider tag — don't rely on tick order.

- **Free a penned AI by WIDENING its public wander rect, not by scripting an exit path.** one project's openable area frees pen animals by growing each AnimalNpc's public `[Property] PenMin/PenMax` rect to a box centred OUTSIDE the opening — its own wander AI (which reads PenMin/PenMax live each PickWanderTarget) then paths it out through the gap on its own, no bespoke escort code, no reach into AnimalNpc internals. The one catch: the opening must line up with an actual GAP in the containing fence, or the sphere-traced movers pile up against it. Put the openable door AT the pre-existing walk-path gate gap (FencePen already skips fence panels inside a walk corridor) so door-open == fence-open at the same x.
- **Blender `materials.clear` + `materials.new(name)` = the `.001` checkerboard trap.** `mesh.data.materials.clear` only detaches the datablock from the slot list — it stays alive in `bpy.data.materials`, so a follow-up `materials.new(same_name)` dedup-renames to `name.001`. That `.001` becomes the FBX material slot key, the vmdl remap (listing the clean name) can't match it, and the engine loads `name.001.vmat` → File not found → red checkerboard in-game. The `.001` lives in the FBX *binary* — grepping vmdls finds nothing; grep the `.fbx` bytes. Fix: purge stray `name`/`name.NNN` datablocks and force-rename the slot before export (`sanitize_material_slots` in the quadruped rig library/the NPC rig library). Hit 10 rigs (8 animal rigs plus humanoid rigs); the hero character escaped only because its OBJ used a hyphen where the rig used an underscore.
- **Coplanar overlay ribbons z-fight — give each layer its own lift.** Roads and walk paths both seated at `terrain + 0.06 m` produced camera-dependent tan streaks wherever a path's segment overlapped a road (every path starts on one). One shared lift constant for two overlay types = guaranteed z-fight at every junction. Fix: layer the lifts (roads 0.06, walk paths 0.04) so the intended winner always renders on top; both stay proud of terrain. General rule: any two procedurally-laid coplanar surfaces need an explicit z-order via distinct lifts.
- **Never publish live mutable static Lists to per-frame consumers — hotload's ListUpgrader reallocates them mid-tick.** NavData exposed `static readonly List<Vector3> StreetLoop` that the builder `Clear`+`Add`ed and every GuardNpc/Wanderer indexed each frame. A hotload (or rebuild) reallocates/shrinks the backing array BETWEEN a consumer's `Count` read and its `list[i]` — IndexOutOfRange every frame on every consumer at once, even ones with modulo guards (the race is on the list, not the index). The log smoking gun: `[hotload/GameMenu] Destination array is too small … ListUpgrader`. Fix: publish `IReadOnlyList<T>` and REBIND the field to a fresh list per rebuild (one atomic reference assignment); consumers capture `var loop = NavData.StreetLoop` once per tick and get an immutable snapshot. Belt-and-suspenders in consumers: empty → skip tick; wrap with modulo of the CURRENT count; rate-limit the warn.
- **Hysteresis lives in the CONSUMER, never in the stateless predicate tests read.** The guard's 15 Hz Spotted/LostSight flap: `TryCatchScan` read raw `CanSee(character)` per frame; on a "seen" frame the guard turned toward the character, on the next the patrol mover re-aimed his gaze at the waypoint, flipping the cone verdict — two facing authorities fighting at frame rate, so pursue never accumulated. Fix pattern: keep `CanSee` a pure stateless truth table (the test scenarios assert its exact per-gate reasons), add a `SeesSticky(target, dt)` wrapper that (a) holds sight until the lose-condition persists ~0.6 s and (b) widens the effective cone hugely under 3 m (nobody loses a character at their feet by turning their head), and make the tracking state own facing for the whole tick. Sight telemetry logs on rising/falling EDGES only.
- **Third-person camera occlusion: ease asymmetrically and tag-exclude thin structure — never pull in instantly.** An occlusion trace that snaps the boom to every hit turns any beam/rib thicket into per-frame distance jitter (the roof-swing jank). The fix trio: (1) ease the pull-IN too (fast k≈22), keep recovery slow (k≈6); (2) ignore transient slivers — a clamp shortening the boom <0.6 m while the prior clamp is clear is a rib ticking past, not a wall; (3) give thin structural members a `camstruct-ignore` tag excluded from the CAMERA trace only (they stay solid for movement) — a beam briefly crossing the lens beats a distance snap. Related: on play-start, SNAP the camera to its fully-resolved pose on first acquire, then ease — lerping out of the menu-camera's pose reads as "camera starts too close and crawls out".
- **Static input gates leak across play sessions — reset them in OnStart AND OnDestroy.** `static bool IsOpen` style gates (EscapeMenu, CeremonyScreen) survive Play→Stop→Play within one editor process. A session ending with the gate set freezes the next session (character wouldn't move until the menu was toggled, resyncing the static). Rule: any static a gameplay loop reads must be hard-reset when its owning component spawns and cleared when it's destroyed. Grep `static bool` near input checks when adding UI overlays.
- **"Everything broke at once" during agent waves = check for a stale assembly FIRST.** When the package compile fails (an agent mid-edit), the s&box editor silently keeps running the LAST GOOD hotloaded assembly — so a playtest can exhibit "regressions" from code that predates hours of committed work (audio dead, features missing). Before debugging any multi-symptom regression reported during concurrent agent edits, grep the log for `Compile of ... Failed` / `Broken Reference` in the session window. If present, the fix is "finish/fix the broken edit + restart Play", not the symptoms.
- **SoundHandle spin-up: freshly-played handles report IsPlaying=false for a frame or two.** A loop-retrigger keyed on `!IsPlaying` fires overlapping duplicate plays every spin-up frame — stacked copies read as a garbled rumble. Retrigger only on invalid-or-Finished, and Stop any lingering handle before replacing it.
- **Sounds/assets compiled AFTER a session started are invisible to that session — and a retry loop on them floods every frame.** The editor builds its asset registry at session start; .sound_c/.vsnd_c produced later (by another session, an agent's compile, or a git checkout) exist healthy on disk but "Couldn't find sound event" until an editor kick re-indexes. Two rules: (1) mtime staleness is a RED HERRING — prove it with a known-working control asset with identical mtimes before chasing it; (2) never per-frame-retry a failed loop: retry once after ~2s, then DISABLE with one warn (a permanently-invalid handle otherwise = one engine warning per frame per loop). A zero-volume canary probe of a few cross-bus events at first Sfx use turns "audio mysteriously dead" into one log line naming the editor kick.
- **.sbproj `Org` must be a valid lowercase package ident — a placeholder breaks engine BOOTSTRAP, not just publishing.** Setting Org to an uppercase TODO string made `Sandbox.PackageLoader.LoadAssemblyFromPackage` assert at editor startup ("File doesn't exist? Maybe a case sensitivity issue??") — the whole editor fails to boot, which reads as engine corruption, not a config typo. Keep `local` for dev; set the real org only when it exists, and never park a non-ident placeholder in that field (document the TODO in a doc instead).

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

- **The editor ignores external edits to persisted settings.json** - GameSettings caches its
 file read once per editor-process lifetime (`static bool _loaded`), so editing
 `data/local/<ident>/settings.json` on disk while the editor runs is silently ignored - a
 benchmark launched after flipping QualityPreset 0->2 externally still printed `preset=Low`.
 No stock ConVar flips quality in-process either. Headless preset changes need an in-game
 Video-tab click or a project `[ConVar]`-backed setter (planned: gb_quality_preset).

- **The engine ships its own built-in `[McpTool]`s as readable C# source, not just compiled
 DLLs — read it before inventing a pattern.** `<path> Files (x86)\Steam\steamapps\common\
 sbox\addons\tools\Code\Mcp\*.cs` (`Scene.cs`, `EditorTools.cs`, `AssetSystem.cs`, `Play.cs`,
 `Packages.cs`, `Log.cs`, `Components.cs`) is real source, ProjectReference'd (not just
 Reference'd) into every project's `.editor.csproj` — that's why it's on disk in full.
 one project's `Editor/SfxProbeTool.cs` (the usual "how to write a project [McpTool]"
 reference) is a pure resource-lookup tool and never touches the scene, so it can't show you
 the canonical "get the active editor scene" pattern — that lives in `Scene.cs`:
 `SceneEditorSession.Active?.Scene ?? Game.ActiveScene` (see `SceneTools.ResolveScene` /
 `ActiveSession`). Same file is also the reference for viewport screenshots
 (`Application.Editor?.Camera` + `camera.RenderToBitmap(bitmap, false)`), moving the editor
 camera (`SceneViewWidget.Current?.LastSelectedViewportWidget`), and resolving game objects by
 guid across every open `SceneEditorSession`. Read this before SfxProbeTool.cs for any new
 project [McpTool] that needs the scene, camera, or selection. Two attribute forms both
 compile: the house convention (SfxProbeTool.cs) is
 `[McpTool( "name", Hints = McpToolHints.ReadOnly )]`; the engine's own tools use the shorthand
 `[McpTool.ReadOnly( "name" )]`.
- **`Angles` struct fields are lowercase `.pitch/.yaw/.roll`, `Vector3` fields are lowercase
 `.x/.y/.z` — do NOT trust capitalized `.Pitch/.Yaw/.Roll` sightings elsewhere in a codebase
 as proof of the struct's own casing.** Grepping this dev folder turns up BOTH casings: the
 lowercase form on `Angles`/`Vector3` themselves (`drive/Code/MapGen/AddressMapBuilder.cs`
 `heading.x, heading.y`; `addons/menu/Code/AvatarEditor/AvatarEditManager.Camera.cs`
 `_angle.yaw`/`_angle.pitch`/`_angle.roll`), and a capitalized form that belongs to unrelated
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
- **Blender `materials.clear()` + `materials.new(name)` = the `.001` checkerboard trap.** `mesh.data.materials.clear()` only detaches the datablock from the slot list — it stays alive in `bpy.data.materials`, so a follow-up `materials.new(same_name)` dedup-renames to `name.001`. That `.001` becomes the FBX material slot key, the vmdl remap (listing the clean name) can't match it, and the engine loads `name.001.vmat` → File not found → red checkerboard in-game. The `.001` lives in the FBX *binary* — grepping vmdls finds nothing; grep the `.fbx` bytes. Fix: purge stray `name`/`name.NNN` datablocks and force-rename the slot before export (`sanitize_material_slots` in quadriglib/npcriglib). Hit 10 rigs (8 animals, zookeeper, janitor); the hero monkey escaped only because its OBJ used a hyphen where the rig used an underscore.
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
- **The editor MCP server's enable+port is a MANUAL per-editor-instance Preferences step, NOT a
 repo/config setting — a running editor may serve NO MCP at all.** The house port table
 (project_a=7200, project_b=7269, project_c=7290) is a *convention the owner
 sets by hand* in each editor via Edit → Preferences → MCP Server (Enabled checkbox + Port
 field); it is NOT persisted in `sbox/config/*.json`, `config/editor/`, or `config/convar/*`
 (grepped all — no `McpServer`/port key exists to set), so it can't be automated from code and a
 freshly-launched editor won't serve MCP until toggled. Don't assume your project's assigned port
 is live: a the vehicle project editor was running (correct `-project`) yet answered on no port —
 scan 7000–7399 and `editor_status`-probe to find who's actually serving, and if the owner used a
 different port, repoint via `$PROJECT_MCP_URL`/`--url` rather than editing anything.
- **On a shared multi-agent working tree, ONE agent's uncompilable file reddens the WHOLE editor
 assembly and silently blocks every other agent's live MCP loop.** The s&box csproj is
 SDK-glob (no explicit `<Compile>` items), so it compiles every `.cs` under `Code/`; a concurrent
 UI agent's half-written `UiRig.cs` referencing a not-yet-created `SessionMenu` failed the whole
 `the vehicle project.csproj` (and, transitively, the `.editor.csproj`), which would leave the
 editor on a stale assembly / `compile_status` red for an unrelated harness agent. Judge only YOUR
 files with `dotnet build … | grep ": error" | grep -v "\\<other-scope>\\"` (empty = yours are
 clean); do NOT "fix" the other agent's file — the owning agent completes it (it did, and the tree
 went green).
- **Adding a `public` method to the GAME assembly and calling it from the EDITOR-tools
  assembly in the SAME hot-reload pass throws `MissingMethodException`** — even though
  `compile_status` is all-green and `dotnet build` is 0/0. The running editor assembly
  re-JIT'd against a stale copy of the game assembly that predated the new method. Fix:
  restart Play (a fresh Play session loads both assemblies together); the exception is
  transient to the cross-assembly hot-reload seam only.
- **`Array.Clone()` is NOT whitelisted in the game assembly** — `(short[])arr.Clone()`
  compiles headlessly but fails the in-editor compile with `SB1000 'System.Array.Clone()' is
  not allowed when whitelist is enabled`. The old assembly silently keeps running. Fix: use
  `var copy = new short[a.Length]; System.Array.Copy(a, copy, a.Length);` — `Array.Copy` IS
  whitelisted. Always check `compile_status` after a game-assembly edit.
- **The `FileSystem.Data` multi-file API surface is whitelist-clean and works at runtime for
  a named-slot save system:** `WriteAllText`, `ReadAllText`, `FileExists`, `DeleteFile`,
  `DirectoryExists`, `CreateDirectory`, `FindFile(dir, "*.json")` all compile in-editor AND
  execute. Paths are relative to the project data root; sub-dirs like `saves/<slug>.json`
  work. Sanitize any user-derived slug (drop `/ \ .`) to prevent path traversal.
- **`editor_status` over the editor MCP can transiently return `Project: null` while
  mid-hotload** (right after a source change compiles). An identity-probing harness then
  aborts with a false "wrong port / wrong project" even though the port and project are
  correct. Fix: treat a null Project as "editor busy", wait ~10–15 s and re-probe before
  concluding wrong-port; only a different non-null project name means wrong port.
- **On Windows, invoking `python3` from a project tool aborts with exit 49** ("Python
  was not found; run without arguments to install from the Microsoft Store") even though
  Python is installed and on PATH — `python3` resolves to the WindowsApps App Execution
  Alias shim, not the real interpreter. Use `python` or the launcher `py` instead.
- **Porting a `.cs` file into another s&box project with its doc comments intact: a
  `<see cref="TypeYouDidNotCopy"/>` in an XML `///` comment emits CS1574** ("XML comment
  has cref attribute that could not be resolved") — which quietly fails a "0 warnings"
  acceptance gate even though the code is correct. For a small port: grep for `cref=`
  and strip or redirect references to types you didn't copy. For a LARGE vendored
  slice you want to keep drift-diffable against upstream: prepend
  `#pragma warning disable 1574` to each vendored file instead of scrubbing the
  crefs — keeps bodies byte-identical to the source for drift-sync.
- **The editor MCP `camera_screenshot {includeUi:true}` captures base HUD panel elements fine
  but DROPS a centered full-screen modal card** — even one on the same ScreenPanel. The
  backdrop's dim/blur composites (the scene visibly dims) but the card and all its children
  never appear. This is a render-pass artifact of the modal sub-layer, not layout. Workaround:
  bind the asset-under-test to an always-visible base HUD element (which does composite),
  screenshot that, then revert.
- **Game code cannot subscribe to the engine log stream — `Sandbox.Diagnostics.Logging` is
  `internal`.** `Logging.OnMessage += handler` fails to compile (CS0234). Only
  `MenuUtility.AddLogger` / `EditorUtility.AddLogger` are public (menu/editor realm, not game).
  Workarounds: (1) derive events from observable side effects instead of log parsing; (2)
  bracket runs with grep-able START/DONE markers and have the outer tool grep the console
  between them.
- **When the whole HUD is gated behind a static flag on a static class, an MCP test harness
  that only pokes gameplay singletons can drive every gameplay verb yet capture ZERO HUD** —
  the flag never flips, the `@if` renders nothing, and screenshots show only the start menu.
  `set_component` reaches only component `[Property]` fields, never static class fields.
  Fix: expose the gate as a `[Property]` on a component, or skip HUD capture for automated
  runs and verify HUD separately.
- **Moving legacy assets out of a publish payload with `git mv` alone leaves the shipped bytes
  behind AND a source-only dependency closure misses shared textures.** Compiled artifacts
  (`*_c`, `*.generated.*`) are git-ignored, so `git mv` only relocates sources. AND a
  `.vmat`/`.vmdl`-only move misses shared `.vtex` files referenced by the material. Combine
  the `git mv` with a `git rm` of the compiled artifacts and trace the full texture closure.
- **The editor serializes its STALE in-memory `.sbproj` on any settings/wizard save, reverting
  on-disk hand-edits.** A `Resources` glob added by editing the file while the editor was open
  gets dropped without warning when the publish wizard runs. After any editor settings interaction,
  re-read the sbproj on disk and restore hand-edits (`git diff -- *.sbproj`). The publish wizard
  also PACKAGES from the stale in-memory copy — an editor restart (or editing through the Project
  Settings UI) is the only fix.
- **`editor_camera_screenshot` renders the EDITOR viewport (the edit scene), NOT the running play
  scene.** Anything that exists only at runtime (procedurally generated terrain, play-mode-spawned
  objects) is invisible to it. Capture the play scene with the `scene` toolset's
  `camera_screenshot` instead (arg = a CameraComponent/GameObject id, or omit for the scene's
  main camera).
- **A newly added Component type can be compiled-but-not-yet-registered in the TypeLibrary
  right after the editor loads the assembly.** `compile_status` is green but playing a scene that
  references it logs `TypeLibrary could not find <Type>` and silently skips the component (its
  `OnStart` never runs). Resolves on its own after a short window. Gate: re-query
  `get_component_type` before concluding the component is broken; if it now resolves, reboot play.
- **The editor MCP resolves only ONE component per GameObject.** `set_component {type}` fails on
  any secondary component with `has no <Type> component`. Workaround: drive behavior through the
  component you CAN reach, or put the thing you need to script on its own single-component
  GameObject.
- **There is NO scene/global time-scale API in the game-reachable engine surface (26.07).**
  `Scene.TimeScale` does not exist; the only `TimeScale` anywhere is
  `ParticleEffect.TimeScale`/`PerParticleTimeScale`. Slow-motion must be faked with a custom
  multiplier applied to delta-time in your own update loops.
- **The stock `PlayerController` exposes NO public speed property.** `WalkSpeed`/`RunSpeed`/
  `DuckedSpeed` are private serialized `[Property]` fields. Game code cannot cleanly scale
  player move speed (e.g. for a slow debuff). Write your own controller or reflection-hack
  the privates (fragile across updates).
- **Re-setting a `[ConVar]` to the value it already holds is a SILENT no-op** -- the property
  setter never runs. Because statics survive Play stop/start, a convar-triggered action from
  a prior session leaves the convar "already set," so a fresh session's identical command does
  nothing. Fix: toggle to a different value first, or reset the backing static on boot.

- **Headless Blender 5.2 drops the old compositor API silently** — `Scene.node_tree` / `CompositorNodeComposite` removed; use `scene.compositing_node_group` + `NodeGroupOutput`, or skip the compositor entirely with an opaque-floor render recipe.
- **Git worktree at a different directory depth breaks sbox csproj relative refs** — the generated `.csproj` uses deep `../` paths that only resolve at the main checkout's depth. Build from a worktree-local `.csproj` with absolute paths.
- **Headless Blender opaque-floor render recipe** sidesteps compositor API churn entirely — an emissive-grey world + albedo-matched diffuse floor + the subject's own cast shadow; no film transparency, no compositor graph needed. Use Standard view transform, not AgX.
