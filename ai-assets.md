# AI-generated 3D models in s&box

Text-to-3D generators (Tripo, Meshy, Rodin, Hunyuan3D, and similar) now produce
fully-textured, game-ready meshes from a prompt. They're a fast way to fill an s&box
project with props and characters — but the exported files usually need a handful of
fixes before s&box will load them cleanly. This doc collects the ones that bite, so you
don't lose a day to a floating orange ERROR mesh.

The Blender-authored flow is in [asset-pipeline.md](asset-pipeline.md); the axis /
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
