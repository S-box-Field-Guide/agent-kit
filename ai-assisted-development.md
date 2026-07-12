# Building s&box games with AI coding agents

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
