# AI-assisted workflow — skill pack

> Lane pack. Load `_core.md` first, then this file. Denser than the full articles by design;
> for a matching bullet's full write-up, follow that gotcha's article link in `coverage.md`
> (full articles live on the Field Guide website, not in this pack). Sanitized public
> advice; unconfirmed details marked `(needs verification)`. The sync appends new bullets here.

> **Restored 2026-07-13:** this lane's topic content (below) predates the lane-pack split
> and was restored after an over-eager orphan cleanup; the sync pipeline appends new
> gotcha bullets after it.

s&box is a good fit for AI-assisted development: it's C#, it compiles headlessly, and
much of the work is well-specified mechanical implementation. But it also has failure
modes that make an agent *honestly report success on code the game then rejects*. This
doc is the methodology that keeps agent-built s&box work landing correctly — the
division of labor, the feel-tuning loop, and the s&box-specific verification gaps to
guard against.

None of this is engine-secret; it's process that has repeatedly worked. Adapt it to
whatever agent setup you run.

## Division of labor

Match the model tier to the task, not the other way around:

- **A strong planning/reviewing model** should own diagnosis, feel- and
  correctness-critical code (movement, physics, camera, animation math), and the review
  pass that hunts bugs in landed work. Anything where the brief says "diagnose before
  fixing" needs the top tier — root-cause fixes come from evidence, not pattern-matching.
- **Cheaper execution agents** handle well-specified mechanical work: self-contained new
  components, model/renderer swaps with documented constants, UI panels, settings
  persistence — anything deterministic with clear acceptance criteria.

## What makes an agent task land clean

A task spec that reliably produces good s&box work has six parts:

1. **Mandatory prep** — the exact files and the specific gotchas sections to read first.
2. **Verbatim acceptance criteria** — quote the player/tester's own words ("swing too
   fast", "model drifts left") as the definition of done.
3. **Explicit file ownership** — "files you own / do NOT touch (X is owned elsewhere)".
   Parallel agents get **disjoint** file sets; contested files serialize the agents.
4. **House rules restated** — units are inches (SI × 39.37 at the boundary), all
   feel-dials in a tuning class, sweep for whitelist violations (below), no per-bone
   runtime bone writes on clip-animated rigs, etc.
5. **A verify clause** — `dotnet build <proj>.csproj` green in scope; "foreign errors
   from another agent's in-flight edit are not yours — report, don't fix".
6. **A return format** — diagnosis before fix, constants changed, deviations one-lined.

## The feel-tuning loop

Feel is tuned from data, not guesses:

1. Playtest → the tester reports feel.
2. Read **telemetry** from the console log — log state transitions, stuck events, and a
   low-rate gait/state line so you're diagnosing from numbers.
3. **Diagnose from the data.** When the data is missing, the next task's job #1 is to
   *instrument* (add the telemetry), fix only what's provable, and let the next playtest
   calibrate the rest. **Never stack guesses** — one speculative fix on top of another
   produces overcorrections you can't untangle.
4. **Fix the instrument first when it lies.** A metric with a wrong baseline or noisy
   sampling will send you chasing ghosts. Prove engine conventions (axes, rotation
   signs) against the real engine assemblies — a scratch console app referencing the
   `Sandbox.*` DLLs can classify `Rotation.From(...).Forward/Right/Up` against a travel
   direction in seconds — rather than guessing a sign and shipping a latent bug.

## The review pass — bug classes to hunt

After an agent lands work, a targeted review of the riskiest new logic catches a small
set of recurring s&box bug classes:

- **Feedback loops in transform/bone code** — anything that reads state it also wrote
  last frame (a rotation composed from `WorldRotation`, a bone that accumulates).
- **Degenerate vector math** — cross products of near-parallel vectors, damping along an
  axis that's identically perpendicular to the velocity (a no-op).
- **Colliders vs `WorldScale`** — Capsule, ModelCollider, and mesh hulls do **not** scale
  with `WorldScale`; Box does. Bake scale into the vmdl or use an unscaled sibling GO.
- **Input overlaps** — two systems reading one button (grab vs aim-cancel); one owner per
  key.
- **Missing state→clip mappings** — a state that plays the wrong (or idle) animation.

## Hot-file discipline

**After ~3 stacked patches on one file, the next change is a rewrite, not a fourth
patch.** Individually-correct patches to a hot file (a camera, a movement controller)
interact in ways no single patch tested, producing compounding regressions. When a file
crosses that threshold, rewrite it into one ordered pipeline with **one owner per state
variable**, and add **unconditional invariants** with rate-limited warnings (e.g. a
camera's focus stays near its subject; non-finite math forces a hard re-acquire) so the
failure class degrades to a visible one-frame snap instead of an unrecoverable drift.
Bound the output; don't just tune the inputs. Corollary: never run two feature agents in
the same hot file — serialize them.

## s&box-specific verification gaps (why agents falsely report green)

These are the traps that make a headless "build passed" untrustworthy:

- **`dotnet build` does NOT enforce the s&box whitelist.** Only the in-editor compiler
  does. Code using `Environment.*`, `System.IO`, `Process`, `Thread`, or reflection
  (`Type.GetProperty`/`SetValue`) compiles clean and is then rejected at runtime
  (SB1000). Every task carries a whitelist-sweep clause; grep new code for these before
  trusting it.
- **`Model.Load` of a missing vmdl can return the error model carrying the requested
  path as its `Name`** — so a naive `Name.Contains("error")` check passes and you spawn
  the giant orange ERROR mesh. Gate on `model == null || model.IsError ||
  model.Name.Contains("error")`.
- **"Everything broke at once" = check for a stale assembly first.** When a package
  compile fails mid-edit, the editor silently keeps running the *last good* hotloaded
  assembly — so a "regression" can be from code that predates hours of committed work.
  Grep the log for `Compile of … Failed` / `Broken Reference` before debugging any
  symptom.
- **`dotnet build` warning counts lie under incremental builds** — warnings only
  re-emit for files that recompiled, so a stale build prints `0 Warning(s)` over a tree
  that carries them. Any whole-tree "clean" claim must come from `--no-incremental` (or
  a clean build). Per-scope checks can stay incremental.

## Autonomous test loops

The s&box editor exposes an MCP server (`http://127.0.0.1:7269/mcp`) with
`asset_compile`, `spawn_model`, `set_editor_camera`, `editor_camera_screenshot`,
`read_console`, and `play_start`/`play_stop`. Combined with an in-game test harness that
drives a scenario and prints a machine-checkable verdict line (e.g.
`[test] SUITE DONE failed=0`), this lets an agent compile, run, observe, and verify a
change end-to-end without a human in the loop.

## Boot-audit-driven QA

Build-time audits that **measure the actual runtime state** (real collider footprints,
overlaps, reachability), name each offender with coordinates, and end in a single
`target 0` summary line become a regression net a coordinator (or a log monitor) can
grep. Two rules that matter: measure the **real** collider (`Scale × WorldScale`), not
the authored graybox — a later model swap can re-inflate a footprint under a graybox
that passed; and **scope audit exemptions narrowly** — a category an audit exempts is
exactly where the next bug appears.

Text-to-3D generators (Tripo, Meshy, Rodin, Hunyuan3D, and similar) now produce
fully-textured, game-ready meshes from a prompt. They're a fast way to fill an s&box
project with props and characters — but the exported files usually need a handful of
fixes before s&box will load them cleanly. This doc collects the ones that bite, so you
don't lose a day to a floating orange ERROR mesh.

The Blender-authored flow is in [asset-pipeline.md](getting-art-in.md); the axis /
material / collider fundamentals are in the [`getting-art-in.md`](getting-art-in.md) lane
pack (and the cross-cutting rules in [`_core.md`](_core.md)). This doc is the delta for
*generated* assets.

## What you get, and where it goes

Most generators export an **OBJ or GLB mesh + a baked PBR texture** (albedo, sometimes
normal/roughness). s&box does not load raw OBJ/GLB in a scene — you always wrap it in a
`.vmdl`, exactly like a hand-authored model. A typical import layout:

```
Assets/
  models/<game>/<slug>.obj        # mesh, UVs preserved
  models/<game>/<slug>.vmdl       # s&box wrapper (KV3 text)
  materials/<game>/<slug>.vmat
  materials/<game>/<slug>_color.png   # baked albedo
```

Reference it in code root-relative, forward slashes, no `Assets/` prefix:

```csharp
var model = Model.Load("models/mygame/cart.vmdl");
```

The `.vmdl` wrapper conventions are the same as any imported mesh: `import_scale`
(39.37 if the source is authored in meters/inches — see below), `import_rotation
[0,0,0]`, material remaps that map **both** `"name"` and `"name.vmat"`, grounded at
z=0, triangulated. New/changed vmdls hot-compile on the next editor focus — kick the
editor if a model doesn't appear.

## The fixes generated assets commonly need

These vary by generator and change over time, so **verify each against your own
exporter's current output** rather than assuming. All of them have been seen in real
deliveries:

- **Meshes often arrive NORMALIZED to ~1 m max dimension** — no real-world scale, so a
  "tall tree" imports knee-high. Rescale at placement:
  `WorldScale = desiredHeightMeters * 39.37f / model.Bounds.Size.z`. Note the source
  mesh is "~1 m", not *exactly* 1 m, so a flat baked `import_scale` can under/overshoot
  — the runtime `Bounds`-based rescale self-corrects to the true native size. (Colliders
  authored in local-space bounds scale along automatically; but see the collider caveat
  in gotchas — Capsule/ModelCollider do **not** follow `WorldScale`.)

- **Some exporters emit a `.vmdl` declaring `format:modeldoc32`**, which the engine may
  reject: *"No valid format conversion from 'modeldoc32' to 'modeldoc30'"* — the model
  shows as the floating orange ERROR text. Fix per asset: replace the vmdl's first line
  with the header used by hand-authored models (copy line 1 of any working vmdl). The
  node classes inside are compatible as-is.

- **The baked texture may be a corrupt or oversized PNG** (e.g. bad IDAT checksum → the
  texture compile fails). Re-encode it (any clean re-save) or replace it.

- **A bare texture reference in the `.vmat` may not compile.** s&box's material compiler
  resolves `TextureColor` against the **Assets root**, not the vmat's own folder, so a
  bare `<slug>_color.png` fails with *"Unable to read file …/assets/<slug>_color.png"*
  and the model errors out with it. Fix: set `TextureColor` to the full root-relative
  path, e.g. `materials/mygame/<slug>_color.png`.

- **No collision ships with the mesh.** Generated models have no `ModelCollider` — add a
  bounds-derived `BoxCollider` (`c.Center = model.Bounds.Center; c.Scale =
  model.Bounds.Size;`) per the standard practice in gotchas. If you need real per-poly
  collision, add a `PhysicsMeshFile` node to the vmdl (see gotchas — "a vmdl with only a
  RenderMeshFile compiles clean but has ZERO collision").

- **Facing is a coin-flip — and often OPPOSITE the Blender convention.** Verify one
  placed instance visually and hard-code a facing-yaw constant per model. Where a
  Blender-authored mesh faces world −Y (yaw **+90°** to face +X), generated meshes have
  been observed to want facing yaw = `atan2(dir.y, dir.x)° − 90`. Don't guess — place
  one and look.

- **Characters come as static meshes — no skeleton, no rig.** To animate one you rig it
  locally (headless Blender: armature + scripted weights + clips + FBX export + animated
  vmdl). See the "Skeletal rigging & animation" section of gotchas for the traps
  (auto-weights fail on generated meshes; use geodesic weights; keep quaternion keys
  hemisphere-continuous). **Rig from a COPY** outside your generator's output folder —
  a re-run overwrites files in place.

- **Triangle budget.** Generated meshes can be dense. Do a census weighted by
  `tris × instances` (the most-instanced asset, not the densest file, is usually the
  worst offender), then decimate — collapsing preserves painted UVs fine; **silhouette**
  is the failure mode (thin/curved features fall apart below ~2k tris). Verify with a
  textured before/after render on one complex prop before batching. (Full detail in
  gotchas — "Scene triangle overload".)

## Working with a generated asset

- **Don't hand-edit files your generator re-runs will overwrite.** Copy the asset out of
  the generator's output folder before forking or fixing it, or your edits vanish on the
  next generation.
- **Kick the editor for new vmdls; restart Play for scene changes.** A headless
  `dotnet build` does not compile assets.
- **Batch thoughtfully** — most hosted generators bill per asset.
