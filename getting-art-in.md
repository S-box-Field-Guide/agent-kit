# Getting art in — skill pack

> Lane pack. Load `_core.md` first, then this file. Denser than the full articles by design;
> for a matching bullet's full write-up, follow that gotcha's article link in `coverage.md`
> (full articles live on the Field Guide website, not in this pack). Sanitized public
> advice; unverified material is held privately until verified. The sync appends new bullets here.

## Units, axes, and frames

- **s&box units are inches.** 1 m = 39.37 u. Do design math in SI and convert at the
 engine boundary: `const float MetersToUnits = 39.37f`.
- **Meters-authored waypoint/position arrays: audit EVERY consumer for `* M`.** One
 code path building a world target from raw meter values puts the target ~39× too
 close to the origin — the NPC walks in a fixed, wrong direction forever ("running
 into walls") and never arrives. That symptom (steady march in an arbitrary direction,
 no convergence) = suspect a missed meters→units conversion; grep all uses of the
 authored array and check each applies `* M`.
- **Meters/units mixups travel in PACKS — sweep the whole file, then assert the FULL
 transform.** Three sibling bugs shipped in one builder in one day (a meters origin +
 unit offsets in a wall grid, the same mix in a hallway that dropped INVISIBLE collider
 walls near the origin, and a `center / M` where center was already meters), all
 presenting as "props piled mid-map near the origin". Breeding ground: helpers with
 `xxxMeters` and `xxxUnits` params coexisting in one file — every crossing call is a
 hazard. Fix pattern: author builder math in meters end-to-end, convert at EXACTLY one
 `* M` per placement, and add a boot audit that re-reads spawned GO transforms and
 asserts the intended plane/span — a z-only proof line validated the one placement that
 wasn't broken while the xy collapse survived it.
- **Default scene gravity is ~2.2g** in units — fine for chunky arcade feel, wrong for
 physical suspension. Set it explicitly: `Scene.PhysicsWorld.Gravity = Vector3.Down * 9.81f * m;`
- **OBJ importer auto-converts Y-up → Z-up at compile.** Export from Blender with
 `forward_axis='NEGATIVE_Z', up_axis='Y'` and keep `import_rotation [0,0,0]` in the vmdl.
 The compiled world frame is `world = (-objZ, -objX, objY) * scale`.
- **Model facing:** geometry built along Blender **+X** faces world **−Y** after import.
 Yaw **+90°** turns it to face +X. Codify it once (e.g. facing yaw = `atan2(dir.y,dir.x)° + 90`).
- **Text-to-3D generator output (Tripo/Meshy/Rodin-style) facing is a coin-flip and often
 OPPOSITE the Blender-authored convention above** — don't assume the same +90° yaw applies;
 generated meshes have been observed wanting facing yaw = `atan2(dir.y, dir.x)° − 90` instead.
 Verify one placed instance visually and hard-code a per-model facing-yaw constant.
- **Blender rotation sign check:** rotating a slab about **+Y by a positive angle tips its
 +X edge down**. We shipped every roof upside-down (valley instead of peak) by guessing
 the sign. When authoring angled geometry, verify one instance visually before batching.
- **Colliders live in the model's own frame** and rotate with the GameObject — author
 collider specs in the yaw-0 frame, never pre-rotate them.
- **CapsuleCollider Radius/Start/End do NOT follow WorldScale** (BoxCollider does).
 On a 4.5×-scaled tree the "0.5 m" trunk capsule shrank to a ~6 cm noodle players fell
 through. Put capsules on an UNSCALED sibling GameObject with world-unit dimensions.
- **ModelCollider's physics hull also does NOT follow WorldScale** (same class as
 CapsuleCollider). A 1 m-normalized tree mesh on a GO scaled 4.5× rendered 4.5 m tall but
 the per-poly collider stayed ~1 m, buried in the base — players climbed up through the
 branches. Fix: BAKE the scale into a per-model vmdl wrapper (`import_scale = 39.37 ×
 desiredHeightMeters`) referencing the same OBJ, load it at GO WorldScale 1 — then the
 ModelCollider matches the visual 1:1. Keep the material-remap both-names rule in the
 wrapper. New vmdls need an editor kick to compile.
- **A "baked-scale" vmdl wrapper's `import_scale = 39.37 × N` only delivers an N-metre
 model if the SOURCE mesh's own native bounding box is exactly 1 m — AI-generated (Tripo-style) OBJs
 are "normalized ~1 m", not exactly 1 m, so a flat `39.37×N` bake can under/over-shoot
 the intended size AND silently change the real footprint versus whatever the runtime
 fallback path (`heightMeters × M / model.Bounds.Size.z`, which self-corrects to the
 true native size) was delivering before the wrapper compiled. Concretely: a rock-arch
 authored "3.2 m tall" had a native footprint WIDER than tall (0.997×0.469×0.661 m);
 once its `_big.vmdl` wrapper (baked at flat ×3.2) finished an editor-background
 compile mid-session, the live footprint jumped to 3.19×1.50 m — enough to newly
 overlap a static neighbour an overlap audit had read clean on every earlier boot
 that session, with ZERO C# placement code changed. When a boot-audit result flips
 with a clean `git diff`, check whether a `.vmdl_c` for a graceful-fallback model
 (`Model.Load(...)==null/.IsError` ladders) finished compiling BETWEEN boots before
 assuming a code regression — the effective footprint can change entirely
 independently of the placement math.
- **A yaw-rotated rectangle's axis-aligned bounding box is MAXIMIZED at the EDGES of a
 yaw-jitter range around a cardinal angle (0/90/180/270°), not at the nominal centre**
 (`worldHalfX = halfLocalX·|cos yaw| + halfLocalY·|sin yaw|` — at yaw exactly 90° this
 collapses to just the short axis, but ±15° jitter off 90° picks up a term from the
 LONG axis on BOTH world axes at once). When clearing a jittered/rotated prop's
 worst-case footprint against a neighbour, evaluate at the jitter bounds, not the
 authored/nominal yaw — the centre case is never the worst case.

## Models & import

- **s&box does not load raw OBJ/GLB in scenes.** Always generate a `.vmdl` wrapper;
 the engine compiles it on load.
- **A generated vmdl declaring `format:modeldoc32` gets rejected** ("No valid format
 conversion from 'modeldoc32' to 'modeldoc30'" — the model shows as floating orange ERROR
 text). Fix: replace the vmdl's first line with the header line from any working
 hand-authored vmdl; the node classes inside are compatible as-is. Also expect the source
 mesh grounded at z=0 and triangulated before wrapping.
- **vmdl material remaps must map BOTH names**: `"MatName"` *and* `"MatName.vmat"` in
 the `DefaultMaterialGroup` remaps, or the compiler errors with "unable to resolve X.vmat".
 A `MaterialOverride` on the renderer is not a substitute.
- **Prefer hand-sized `BoxCollider`s over `ModelCollider`** for props — per-poly collision
 on decorative meshes is wasted cost and traces get noisy. Compute the box from model
 bounds at generation time.
- **A vmdl with only a `RenderMeshFile` compiles CLEAN but has ZERO collision — a
 `ModelCollider` on it creates no shapes at all** (players walk straight through; every
 trace misses). "Model loads clean / IsError false" proves RENDER, never COLLISION. To give
 a mesh-import vmdl real per-poly collision, add a `PhysicsShapeList` node whose child is a
 `PhysicsMeshFile` (concave, static-safe) with the SAME `filename` + `import_scale` as the
 RenderMeshFile (`surface_prop = "default"`, `collision_tags = "solid"`); `PhysicsHullFile`
 exists too (convex — wrong for tapered/shelved shapes). Detect a hollow model in code with
 `model.Physics?.Parts?.Count ?? 0` before trusting a per-poly branch, and on disk by the
 compiled `.vmdl_c`'s PHYS block being a ~323-byte stub (real mesh physics runs tens of KB —
 parse the Source-2 block directory at offset 8). This silently killed the whole node-climb
 system twice: every `_big` baked-scale wrapper was authored render-only, so the fit
 raycasts AND body collision both hit nothing.
- **Animated sub-parts need their origin at the joint.** Export limbs/rotors as separate
 OBJs with the pivot at the hinge (`ground=False`, geometry hanging off origin), then
 parent them to the body GameObject and rotate `LocalRotation`. Used for the farmer's
 walk cycle and spinning turbine/water-wheel rotors.
- **Model top for UI markers:** `renderer.Model.Bounds.Maxs.z * go.WorldScale.z` works;
 don't guess fixed heights.
- **Blender's OBJ exporter with `export_materials=False` silently drops the `usemtl`
 line too** — not just the .mtl file — and the vmdl's `DefaultMaterialGroup` remap
 keys off that material-group name (`from = "<slug>_mat"`), so the re-exported mesh
 compiles UNTEXTURED. After any scripted OBJ export, grep the output for `usemtl` and
 `vt `; fix by re-injecting `usemtl <name>` before the first `f` line rather than
 re-enabling material export (which writes a stray .mtl into the delivery folder).

- **Scene triangle overload: census (tris × instances) BEFORE building decimation
 tooling.** AI-generated (Tripo-style) caps every delivery at ~7–12k tris regardless of screen size,
 so the worst offender is the most-INSTANCED asset, not the densest file (an 11.4k
 grass tuft × ~1150 scatter instances = ~13M scene tris, ~30% of a 43M-tri frame).
 Budget per category weighted by screen size × instance count. Decimate (collapse)
 preserves UVs/painted textures fine — SILHOUETTE is the failure mode: thin/curved
 features (umbrella domes, wheels) collapse below ~2k tris, while high-instance
 scatter clumps tolerate the most aggressive cuts (faceting invisible at their screen
 size). Verify budgets with a textured before/after render on one complex prop before
 batching.
- **Blender OBJ import `up_axis='Y'` puts Y→Z rotation in `matrix_world`, not vertices** — raw `.co.z` reads the file's horizontal axis. Apply transforms after import (`bpy.ops.object.transform_apply`) to bake world-Z-up into vertex coords.
- **`bpy.ops.object.duplicate()` in headless Blender can share the mesh datablock** — a bmesh edit to one mutates both. Re-import per output or force `obj.data = obj.data.copy()` for independent meshes.
- **Text-to-3D generated characters arrive as static meshes — no skeleton, no rig.** To
 animate one, rig it locally (headless Blender: armature + scripted weights + clips + FBX
 export + animated vmdl); auto-weights fail on generated meshes (use geodesic weights) and
 quaternion keys must stay hemisphere-continuous.
- **Never hand-edit a file still inside a generator's own output folder** — copy the asset
 out (mesh, texture, vmdl) before forking or fixing it, or the next generation run silently
 overwrites your edits. Rig from a COPY for the same reason. Batch thoughtfully — most
 hosted generators bill per asset.

## Lighting & sky

- **No dedicated ambient-light or gradient-fog component exists in this engine.**
 `DirectionalLight` (a plain Component — "angle" is just `WorldRotation =
 Rotation.From(pitch, yaw, roll)`) folds BOTH hue and intensity into `LightColor`
 (scale the Color itself to dim/brighten, no separate lux field) and exposes
 `SkyColor` as the only ambient/bounce-color knob and `FogMode`/`FogStrength` as
 the only fog knob — there is no `Sandbox.AmbientLight`/scene-wide ambient
 property and no standalone gradient-fog component anywhere in the sibling
 projects. `SkyBox2D.Tint` (Color) IS a real runtime-settable multiply on the sky
 material (confirmed against a `sky.shader` .vmat's own `g_vTint` field — Tint is
 that same hook) with no separate rotation/angle property. A day/night cycle is
 therefore: rotate the sun's GameObject, scale `LightColor`/`SkyColor`, and scale
 `SkyBox2D.Tint` — no other engine surface needed.
- **`MathF` has no `Lerp` in this engine's .NET target — use `MathX.Lerp`/
 `MathX.LerpDegrees`** (s&box's own math helper class). `Color.Lerp` does exist
 separately for Color values.

## Materials & textures

- **Flat-color materials: constant-color `TextureColor` does not reliably compile.**
 Use a shared white PNG + `g_vColorTint "[r g b 0]"` + `g_flModelTintAmount "1.000"`.
- `.vmat` essentials: `shader "shaders/complex.shader"`, `TextureColor`,
 `TextureRoughness "[r r r 1]"`, `g_flMetalness`. Tiling via `g_vTexCoordScale "[n n]"`.
 Sky: `shader "shaders/sky.shader"` + `SkyTexture` (equirect PNG works).
- **Asset paths are project-root-relative with forward slashes and NO `Assets/` prefix**:
 `Model.Load`, `Material.Load("materials/x/y.vmat")`.
- **A bare texture filename in `TextureColor` (no folder) fails to compile** — the material
 compiler resolves it against the Assets ROOT, not the vmat's own folder ("Unable to read
 file …/assets/<slug>_color.png"), and the model errors out with it. Give `TextureColor`
 the full root-relative path, e.g. `materials/mygame/<slug>_color.png`. A generator-baked
 PNG can also be corrupt or oversized (bad IDAT checksum fails the texture compile) —
 re-encode with any clean re-save before assuming the vmat is wrong.
- `ModelRenderer.Tint` multiplies — usable for cheap state visuals (watered soil,
 ghost previews with alpha, team colors). Values > 1 brighten.
- **Skip `ModelRenderer.Tint` entirely on props using the flat-color vmat recipe (white
 PNG + `g_vColorTint` + `g_flModelTintAmount 1.0`) — any non-white per-instance Tint
 renders WRONG.** Independent per-channel jitter meant as brightness variety instead
 rotates HUE (green→purple, grey→navy/maroon), and a uniform tint off exactly white in
 EITHER direction crushes a random subset of instances to solid black — reads as a
 per-instance bug, not a global darken. Get per-instance scatter variety from scale/yaw
 jitter instead; leave Tint at `Color.White` on flat-vmat props.
- **Disable per-instance shadows via `renderer.SceneObject.Flags.CastShadows = false`, NOT a
 `ModelRenderer.CastShadows` property** — that member shows in `Sandbox.Engine.xml` but is NOT a
 public settable property (only `ParticleModelRenderer.CastShadows` is), so `r.CastShadows =
 false` fails CS1061. The real settable toggle is the `SceneObject.SceneObjectFlagAccessor`
 (`P:Sandbox.SceneObject.SceneObjectFlagAccessor.CastShadows`, canWrite=true — verified by
 reflecting the dll under net10.0). `SceneObject` is a get-only prop populated during the
 renderer's synchronous OnAwake, so it's valid immediately after `Components.Create<ModelRenderer>`
 — still guard `if ( r.SceneObject.IsValid )` defensively. Essential for a large scatter (~1k+
 grass tufts) where shadows are pure cost.
- **"Make the ground alive" = swap the flat tile for a detailed one AND scatter cheap 3D clumps —
 two independent, cheap wins.** one project's terrain read "very plain/flat" because TerrainBuilder
 loaded the blurry procedural `grass.png`; a richer hand-painted `grass_ai.png` (via
 gen_textures_ai.py) already existed but was never wired in — just repointing the `GroundMat`
 const fixed the texture. For depth, a NEW deterministic scatter (Scatter.SpawnAll, one
 Bootstrap line after the world build) drops ~1150 tiny tuft models on the open green. Two
 scatter design rules that mattered: (1) SIMULATE the placement algo in python over the real grid
 first to land the instance count MID-budget (~1150 of a 1500 cap) rather than guessing a density
 and clipping the cap; (2) density FALLOFF (smoothstep ramp) near roads/paths reads far better
 than a hard exclusion edge — hard-exclude on the corridor, then thin over a shoulder band. The
 terrain is ONE material per chunk, so a second "worn grass" tile can't be blended onto
 high-traffic areas without re-architecting the chunk mesh — generate it as a ready asset
 (`grass_worn_ai.vmat`) but don't force a per-vertex-material rewrite for it.
- **Regenerated AI textures need an EDITOR KICK to recompile — a headless `dotnet build` does NOT
 rebuild `.vtex_c`.** After gen_textures_ai.py rewrites `grass_ai.png`, the stale
 `grass_ai_png_*.generated.vtex_c` keeps its old mtime; the engine serves the old baked texture
 until the editor watcher recompiles it (Play/editor restart, same as new vmdls).
- **A tiling ground texture that will repeat across a HUGE mesh must have NO large dark blob or
 hero clump** or it strobes as an obvious grid at ~8 m intervals. Prompt the AI generator for
 "EVEN uniform density, subtle tonal variation, no big patches/blobs, no single dominant clump" +
 tiny specks for interest. The first grass_ai attempt had a few big dark patches (visible repeat
 over the 88×80 m terrain, ~10×10 tiles); a reworded prompt gave a uniform blade carpet that
 tiles invisibly (seam_post 0.09). Repeats-per-face math: terrain UVs authored in metres (1 uv =
 1 m), `g_vTexCoordScale [0.12 0.12]` → tile every 1/0.12 ≈ 8.33 m → at Grid=4 m faces that's
 0.12×4 = 0.48 repeats per face edge (one tile per ~2 faces), a painted blade ~40 cm vs the ~1 m
 character.
- **`Vector3.Right` is (0,−1,0) — NOT +X.** Forward=+X, LEFT=+Y, Right=−Y (Source convention).
 A tuple commented "slide +X" that returned `Vector3.Right` shipped pen doors sliding along their
 own face NORMAL for a whole day, and a wall grid taking that axis tiled ACROSS the pen — caught
 only because a build-time plane audit read maxOffPlane == half the span (a rectangle's far side
 is half the span off the near side's plane). Author LITERAL axis vectors for anything
 directional, and keep an unconditional spawned-transform audit on grids.
- **DOUBLE-TINT: a flat-color vmat override × a non-white renderer tint = a void slab.**
 Another project's flat materials bake their color into `g_vColorTint` with `g_flModelTintAmount 1.0`;
 binding one as a MaterialOverride while the renderer still carries the same house tint
 multiplies the color TWICE (brown² ≈ near-black — the world's "dark blank rectangles in the
 sky"). When an override binds, reset `renderer.Tint = Color.White`; keep the tint only as the
 null/error-material fallback. Auditable: flag any non-default override + non-white tint.

- **A `MaterialOverride` REPLACES the tint path — a Box/prop helper that only applies
 `.Tint` when `mat==null` shows NO tint once a material is set.** So a textured surface
 that must still read a certain color if the material fails to load needs the color BAKED
 INTO the texture, not left to a tint that won't run. one project's roof mullions bake the
 dark steel into `metal_frame.png` (mean RGB ~60) and keep a `MetalDark` tint only as the
 `Material.Load(...)==null` fallback branch.
- **`shaders/complex.shader` (compiled `complex.vfx`) DOES support real tangent-space
 normal maps via `TextureNormal`** — confirmed not by guessing or by grepping sibling
 projects but by reading
 the s&box install's own auto-generated templates, which enumerate every field the shader
 takes with working syntax: `<sbox install>/templates/default.vmat` and
 `templates/library.minimal/Assets/Materials/library_material.vmat` both list
 `TextureNormal "materials/default/default_normal.tga"` right next to
 `TextureColor`/`TextureRoughness`/`g_flMetalness`. **General rule: when a shader/vmat field's
 support is unknown and no source `.shader` exists (only compiled `.shader_c`) and no
 sibling project happens to use it, check the install's own `templates/` folder before
 concluding it's unsupported** — it's faster and more authoritative than reflecting DLLs or
 grepping every project. Used in one project's `tools/gen_textures_ai.py` to derive real
 normal maps (Sobel gradient on the AI albedo's luminance treated as a height field,
 wrap-padded so the result tiles as seamlessly as the source) rather than only baking fake
 depth into the albedo.
- **`shaders/complex.shader` supports EMISSIVE / self-illum, but the install `templates/`
 do NOT enumerate the fields (they're behind an `F_SELF_ILLUM` shader combo).** The
 `templates/default.vmat` lists TextureColor/Roughness/Metalness/Normal but nothing
 emissive, so the "check templates/" rule above fails HERE — emission is combo-gated.
 Authoritative source = grep the COMPILED shader `core/shaders/complex.shader_c` for the
 param strings: `F_SELF_ILLUM`, `TextureSelfIllum`, `SelfIllumMask`,
 `g_flSelfIllumBrightness`, `g_flSelfIllumScale`, `g_flSelfIllumAlbedoFactor`,
 `g_vSelfIllumTint`. **CORRECTED 2026-07-17: emission is GATED through `TextureSelfIllumMask` —
 a vmat that never sets it gets the default (black) mask: brightness x 0 everywhere, a SILENT
 no-op (the material compiles clean and renders matte). Set `TextureSelfIllumMask` to white.png
 to emit everywhere.** Working recipe for a flat GLOWING material colored per-instance at
 runtime: `F_SELF_ILLUM 1` + `TextureSelfIllumMask` white.png + white albedo (`TextureColor` white.png) +
 `g_flModelTintAmount 1` + `g_flSelfIllumAlbedoFactor 1` — then `renderer.Tint` colors
 BOTH the surface and the glow from one shared material (no per-color vmat). Add
 `F_TRANSLUCENT 1` + an alpha texture for a glowing decal (ring/marker). General rule:
 when a template omits a field you expect, grep the compiled `*.shader_c` for the param
 string before concluding it's unsupported — combo-gated features are invisible in the
 template dump; and when a combo-gated feature silently does nothing, look for a GATING
 TEXTURE defaulting to black.
- **`PointLight` is a usable game Component even with no sibling precedent and thin XML
 docs.** The engine XML lists no `Radius`/`LightColor` on `Sandbox.PointLight` (only the
 base `Light.LightColor`), and no game project uses it — but the install's EDITOR addons
 do, with the real config: `var l = go.GetOrAddComponent<PointLight>(); l.LightColor =
 color * intensity; l.Radius = units; l.Shadows = false;`
 (`addons/tools/Code/Editor/Clothing/ClothingScene.cs`,
 `addons/tools/Code/WidgetGallery/Examples/SceneRendering.cs`). `LightColor` folds hue AND
 intensity (multiply the Color to brighten, same as DirectionalLight), `Radius` is reach
 in engine UNITS. When one project-facing API surface looks empty, check what the shipped
 editor tooling calls — it exercises the same runtime components.
- **Trajectory/aim previews: sample by ARC LENGTH, not by time.** Even-time samples of a
 ballistic arc bunch at the apex (slow) and spread near the ends (fast) → an ugly uneven
 gap pattern that "swings" as the aim moves. Fix: integrate once at a fine substep with
 the projectile's OWN shared step function, accumulate polyline length (trace-clipped,
 terminate at first world hit), then walk the polyline emitting markers at even DISTANCE
 intervals. Reusing the projectile's exact `Step` + gravity source + trace radius/tags is
 also the guarantee the preview can't disagree with the real landing (a finer preview
 substep is MORE accurate, never in conflict).

- **s&box OBJ import can be the PLAIN Y-up→Z-up cyclic permutation `model=(objZ, objX, objY)` —
 verify any negated formula before trusting it.** Older entries here record
 `world = (-objZ, -objX, objY)` (one sibling project) and "author +X faces world −Y, +90° yaw to
 face +X" (another). On one project's pipeline (Blender 5.1.2 `wm.obj_export
 forward_axis='NEGATIVE_Z', up_axis='Y'`, vmdl `import_rotation [0,0,0]`, engine 26.07.08e) the
 LIVE truth is the unnegated cyclic permutation: net author→model = `(-bY, +bX, bZ)`, geometry
 built along Blender +X points model-local **+Y**, and the facing yaw to world +X is **−90°**,
 not +90. Verified by head-on screenshots before/after plus numeric pivot probes. Determine YOUR
 pipeline's mapping empirically: author one part with a known asymmetry per axis (a door handle),
 parse the exported OBJ for the exporter half, one in-engine facing screenshot for the import
 half.
- **Correct sub-part POSITIONS prove NOTHING about frame correctness — paired 180° errors cancel
 in position and add in orientation.** If an attach-offset conversion AND the body facing yaw are
 both 180° wrong (e.g. both derived from the same mirrored axis-mapping doc), every part pivot
 lands at the exactly correct WORLD position while every MESH sits 180°-spun in place
 (taillights facing forward, doors covering the front quarters). Treat the offset-conversion
 constants and the facing yaw as ONE coupled contract (they must flip together), and verify
 facing with an asymmetric-feature screenshot, never with pivot positions. Related: a documented
 author→engine mapping with determinant −1 (a mirror) is IMPOSSIBLE for a proper-rotation
 export/import pipeline — recompute it, don't consume it.
- **Unverified: a generated vehicle-shaped mesh's raw bbox can't tell you WHICH horizontal
 axis is length vs width by magnitude alone if the ratio is close — but "length ≥
 width" for any real vehicle is a free constraint, so the LARGEST of the two
 horizontal OBJ-space dimensions is safely assumable to be length** (confirmed by
 eye against the judge's contact-sheet render for both a dune buggy and a jet ski —
 side-view renders showed the long axis nose-to-tail in both cases). Still flag
 this as not-yet-engine-confirmed in any handoff doc — a `spawn_model` + screenshot is
 the actual confirmation, this is just how to reason about a baked-scale
 `import_scale` before an editor session is available.
- **The generated-OBJ → vmdl recipe runs CLEAN on Blender 5.1.2**
 (verified headless `-b -P`): `read_factory_settings(use_empty=True)`, the
 `primitive_cube/cylinder_add` ops, `bpy.ops.wm.obj_export(export_materials=True,
 export_uv=True, export_normals=True, forward_axis='NEGATIVE_Z', up_axis='Y')`, and
 `bpy.ops.wm.obj_import` all work unchanged from the other projects scripts. The ONLY
 API drift is a `DeprecationWarning` on `Material.use_nodes = True` ("expected to be
 removed in Blender 6.0") — still functional in 5.1, but the flat-colour material recipe
 (`use_nodes` + Principled BSDF Base Color + `diffuse_color` for Kd) WILL need a rewrite
 before Blender 6.0. `export_materials=True` DOES emit `usemtl` + a `.mtl` in the folder
 (so no `_inject_usemtl` re-inject needed on this path — that trap is specific to
 `export_materials=False`); grep-verified `usemtl` + `vt ` present on all 8 exported
 vehicle-part OBJs. For SEPARATE-part export (pivot-at-joint sub-parts), give each part
 its OWN `reset()` scene and `select_all→join→export` — no per-object selection juggling
 needed.
- **`bpy.ops.wm.obj_export` face/UV serialization order is NOT deterministic across runs
 on the same mesh, even with a fully deterministic generator** — two identical headless
 runs produced byte-identical vertex/normal/UV data but a different `f`-line order on the
 highest-poly prop. Geometry-level determinism (vertex positions, tri count, bbox,
 material assignment) still holds bit-for-bit. Don't chase OBJ-file byte-identity as a
 determinism proof; diff the manifest/bbox/tri-census data instead.
- **A high-key "chalky bright" / near-white sky is capped by TWO stock defaults, and BOTH must move —
 neither a `SkyBox2D.Tint` multiply nor a brighter sky texture alone is enough.** (1) The stock
 `skybox_day_01.vmat` bakes BLUE into the sky and ambient; `Tint` is a MULTIPLY (can only darken toward
 blue, never lift to warm-white), so the fix is a dedicated warm sky TEXTURE — bake a flat pale-warm
 equirect PNG (a plain vertical gradient tiles seamlessly, no clouds/sun-disc = haze-free) with the
 proven recipe `shader "shaders/sky.shader"` + `SkyTexture "…png"` + `g_flBrightnessExposureBias "0.000"`
 (a custom day_sky.vmat), and repoint `SkyBox2D.SkyMaterial` at it AT RUNTIME (`sky.SkyMaterial =
 Material.Load(path)` — settable, scene file stays untouched, house pattern). (2) Even with a near-white
 sky texture the camera `Tonemapping.Mode = Legacy` (the scene default, a FILMIC curve) crushes
 highlights and re-caps the sky ~mid-grey no matter the brightness — the OPPOSITE of high-key. Switch to
 `Tonemapping.TonemappingMode.ReinhardJodie` (gentle rolloff, stays bright/chalky-soft; enum is NESTED —
 `Sandbox.Tonemapping.TonemappingMode`, members {ACES, AgX, HableFilmic, Linear, ReinhardJodie}; "Legacy"
 in old scene JSON is a legacy serialization not in the enum). The whole-scene bright chalky warm look =
 warm sky texture + ReinhardJodie + a warm/dim `EnvmapProbe.TintColor` (the baked cubemap does NOT
 auto-rebake to the new sky material at runtime — warm its tint or the shadow side re-casts cool) + fog 0.
- **To LOCK the camera exposure (kill auto-exposure "adaptation" so a fixed grade reads deterministically),
 set `Tonemapping.MinimumExposure == MaximumExposure`** — Min==Max collapses the adaptation window to a
 point, so the exposure never drifts frame-to-frame. Essential for repeatable screenshot grading (the
 editor-viewport auto-exposure-lag gotcha above is exactly this drift). NOTE the render-path split:
 `Tonemapping`/`Bloom`/`Sharpen` live on the GAME "Camera" GameObject, and the editor MCP
 `editor_camera_screenshot` renders through a SEPARATE `editor_camera` (no post-processing), so a locked
 game-camera exposure only shows up via `camera_screenshot` (see next bullet) — edit-viewport shots stay
 auto-exposed by design.
- **`camera_screenshot` renders through a REAL scene `CameraComponent` — INCLUDING its post-processing
 (Tonemapping/Bloom/Sharpen) — even in EDIT mode; `editor_camera_screenshot` does NOT.** So to judge a
 GAME-camera grade (a locked-exposure tonemap, bloom, a colour grade) WITHOUT entering play mode: in edit
 mode, `set_game_object` the game "Camera" GO to your pose (position + `angles` "pitch,yaw,roll"), then
 `camera_screenshot {"camera": "<Camera GO id>"}` (pass the id explicitly — the scene may hold two cameras,
 "Camera" with the grade and a bare "editor_camera"). This is the ONLY honest way to preview a play-mode
 render grade from the deterministic edit scene; the wb_generate cameraPoses feed straight into
 set_game_object.
- **A "grey void" band at EYE LEVEL under an equirect 2D sky is an ART bug, not a wiring bug: the sky texture's LOWER HEMISPHERE (v > 0.5) was painted a flat pale/cream color, so a level gaze (which hits the horizon-and-below rows of the equirect) always lands in that dead band.** The lighting/`SkyBox2D` wiring can be perfectly correct and you still get the void — chasing ambient/fog/probe settings is a dead end. Fix is in the TEXTURE: keep the real sky COLOR (the blue) coming DOWN through the horizon row (v=0.5) and only transition to the warm ground-haze band in the LOWEST rows — never flat-fill the whole bottom half. Verified in-engine (`camera_screenshot`, play mode): the retuned `sky_tropical_day.vmat` reads vibrant blue at the zenith fading to a golden horizon band with NO grey void at eye level, where the prior cream-lower-hemisphere sky showed the void. Rule of thumb for any equirect sky: paint color THROUGH v=0.5, not just above it.
- **Don't plan on per-vertex COLOR painting through `complex.shader` — its source is not shipped and there's no evidence it reads vertex color as albedo; the reliable runtime color-per-surface lane is a baked TEXTURE + `Material.CreateCopy` + `Set("Color", tex)`.** Verified on the installed build (engine 26.07): `complex.shader` exists ONLY compiled (`core/shaders/complex.shader_c` — no `.shader` source under `addons/base/assets/shaders/`), and a scan of its embedded identifiers shows no vertex-color/paint feature names (the engine's `vVertexColor` TEXCOORD4 plumbing in `common/pixelinput.hlsl` is used by shaders like `blendable.shader` as a layer MASK, not an albedo multiply). Meanwhile `Sandbox.Engine.xml` documents the whole runtime override path: `Material.CreateCopy(string)` ("Create a copy of this material"), `Material.Set(string, Texture)` ("Override/Sets texture parameter (Color, Normal, etc)"), plus `Material.Create(name, shader, anonymous)` for from-scratch. So for per-chunk/per-instance surface coloring: bake a small `Texture.Create` → `Update(Color32[])` texture (the proven minimap recipe), `CreateCopy` a base vmat, and `Set("Color", tex)`. **VERIFIED in-editor (engine 26.07.08e): the `"Color"` parameter name DOES take in-editor — the Smooth world renders its real per-chunk blend colors (not magenta/white), so the `"g_tColor"` fallback is NOT needed on this build.** Also confirmed: this whole path (CreateCopy + Set + Texture.Create/WithDynamicUsage) passes the in-editor code WHITELIST (compile_status green; ~900 same-named per-chunk `{cx}_{cy}` material copies per generate re-created across a 20-regen slider sweep did NOT leak — editor working set fluctuated with GC and fully reclaimed, no unbounded climb). Chosen over vertex colors for one project's smooth-terrain style (per-chunk cell-color blend textures).
- **A DCC (Blender) preview/contact-sheet render of a low-poly asset can make its body colors read MUCH darker/muddier than the same tint renders in-engine — do color sign-off IN-ENGINE, not from the offline render.** One project's asset kits shipped with a flagged concern that the Blender contact sheets rendered all three signature colors dark (orange→mustard, acid green→olive). In-engine (s&box daylight, `complex.shader`, `g_vColorTint` flat-color recipe at roughness 0.9 / metalness 0) the SAME unchanged tint values read vivid and on-brief: `[0.93 0.42 0.03]` = vivid orange (not mustard), `[0.80 0.05 0.07]` = bright signal red, `[0.58 0.83 0.07]` = acid green. Root cause is render lighting/tonemap divergence, not the asset — Blender's default preview lighting + view transform (Filmic/AgX desaturates and darkens saturated primaries) is not the engine's. **Fix: never re-tint an asset to "fix" a muddy DCC render; spawn it in-engine in daylight and eyeball the tint there before changing any `.vmat` value.**
- **`Material.Load` does NOT signal a missing/uncompiled vmat — it silently returns a non-error placeholder, UNLIKE `Model.Load`.** Verified in-editor (2026-07-13, engine 26.07.08e) by probing two deliberately-bogus paths: `Material.Load("materials/.../does_not_exist.vmat")` returned a NON-null material with `IsError == false`, `IsValid == true`, and `Name`/`ResourcePath` == the REQUESTED path (no "error" marker) — indistinguishable from a real load in every readable property. `Model.Load` on a missing vmdl, by contrast, returns the ERROR model (`IsError == true`, Name contains "error"), which is why the model-loader triple-gate `m is null || m.IsError || m.Name.Contains("error")` works. That SAME idiom is USELESS for materials: a truly-absent vmat renders as an s&box placeholder rather than tripping any of the three checks. Consequence: a "required material readiness" gate on `Material.Load` can only catch a genuine null (malformed/ empty path) or an IsError-flagged resource — it can NOT prove a missing/uncompiled material fails. For real missing-asset protection, path-existence-check the vmat (FileSystem) instead of trusting the loaded resource. Don't write comments claiming a `Material.Load` null/IsError gate protects against deleted/uncompiled materials.
- **Coplanar-face z-fight only VISIBLY shimmers where the two faces differ in MATERIAL; and the 2.5 mm inset law applies WITHIN a part, not just across parts.** The flat-shaded box kits are riddled with coplanar coincident faces (two boxes sharing a bounding plane) -- most are harmless: two faces of the SAME flat vmat draw the same colour so the depth-fight is invisible, and back-to-back faces with OPPOSING normals are mutually occluded. A coincidence only flickers when BOTH (a) the outward normals point the SAME way (two stacked exterior surfaces) AND (b) the faces carry DIFFERENT materials (a colour boundary to shimmer). The pickup bed shipped a body-vs-trim fight: the trim rail-cap top sat flush (z equal) with the body-colour side-wall tops, so the bed rails flickered viewed from above -- a WITHIN-part coincidence the earlier de-Kenney sweep missed because it eyeballed a static sheet (z-fighting needs camera motion to show) and had no numeric check. Fixes: (1) drop the subordinate/covered panel 2.5 mm at the shared plane so the visible panel alone owns it (the panel-gap inset law -- it applies part-internally too, e.g. a rail cap flush with its wall); (2) a numeric coplanar census must flag only SAME-direction + DIFFERENT-material overlaps, else it drowns in the benign same-colour coincidences every kit has (a scripted `check_coplanar.py` census is such a gate); (3) when the flush panel is SANDWICHED between two faces of its neighbour, a perpendicular 2.5 mm inset just lands it on the neighbour's OTHER face (a fresh coincidence) -- instead shift the panel 2.5-4 mm ALONG the shared plane. The census gates on coplanar AND projected-overlap, so removing the OVERLAP clears the flicker while leaving the plane untouched and the panel flush on its host (hatch tailgate: the number-plate recess top edge grazed the raked hatch-glass bottom edge on the shared lid plane; nudged down-tailgate along the rake tangent, not into the lid).
- **Runtime deformation (a dented panel) reads WEAKLY for two independent reasons — fix the cheap one in the material, know the code one.** Reported symptom: the material reads so flat it is hard to see any deformation at all. (1) MATERIAL: the flat-color body vmat was `TextureRoughness "[0.90 0.90 0.90 1]"` (near-matte) + `g_flMetalness 0` — a matte surface has **no specular highlight**, so faces are shaded by weak Lambert diffuse only and a crumple (a cluster of faces at varied angles) barely differs in tone from a flat panel. Dropping body roughness to **0.35** (glossy dielectric clearcoat, metalness left 0 so the highlight stays white and the tint hue survives) gives a tight highlight that is far more sensitive to surface-normal direction than diffuse — the crumple's concentrated angle variation now breaks the highlight and reads at chase distance. Palette unchanged; this is readability, not restyle. (2) CODE CEILING you can't fix in the vmat: a mesh-rebuild deformer that moves vertex **positions** but reuses the source `Vertex` struct wholesale does **NOT recompute vertex normals** — a folded face keeps its pre-dent normal, so no lighting term reflects the fold's new orientation. The glossy read above comes only from the crumple concentrating faces whose *original* normals already varied; the largest win (folds that catch light because their normal actually changed) needs a smooth-normal recompute after the position pass in the mesh rebuilder, not a material change. Lesson: if deformation still reads flat after making the paint glossy, check whether your runtime rebuild recomputes normals before blaming the vmat. (sedan crumple readability, 2026-07-16)
- **A rope/chain end-cap (knob, weight, handle) positioned at the rope's tip WITHOUT writing its rotation renders world-vertical — it only looks flush while the rope hangs straight down; the moment it swings, a gap opens on the swing side because the cap never rotates with the rope.** Fix: every frame, align the cap's up-axis to the rope's end direction, and derive its POSITION from the rope's RENDERED end, not an analytic straight-line tip — a rendered rope bends, so the analytic tip drifts from the drawn curve at large swing angles. Derive both position and rotation from the rope's own rendered geometry, never from the swinger's body (that isn't flip-safe as the swing direction changes). Verified in-editor with rest-pose and mid-swing screenshots.
- **A Blender `from_pydata` mesh has NO UV layer, so a scripted OBJ export of a pure-pydata primitive ships ZERO `vt` lines even with `export_uv=True`** — and the flat-vmat route keys texturing off UVs, so that prop would compile untextured (same failure family as the `export_materials=False` drops-usemtl trap, different cause). `primitive_cube/cylinder/ico_sphere_add` all come WITH a UV map, so a mixed prop that includes any one primitive masks the bug after `join` (Blender back-fills zero UVs for the layerless faces); a prop built ENTIRELY from `from_pydata` (a triangular-prism ramp, a custom flag) exports with no `vt` at all and trips the pipeline's per-OBJ `vt ` assertion. Fix: `me.uv_layers.new(name="UVMap")` right after `from_pydata`/`update` and before export — the coords can stay default (0,0), the flat white.png route only needs `vt` to EXIST, not be meaningful. Keep the grep-assert for `vt ` on every exported OBJ so it's caught at generation, not at engine compile.
- **A vmdl `RenderMeshFile.filename` that escapes the Assets content root fails to compile.** A generator wrote OBJs to `tools/out/<kit>/` and referenced them from the vmdl (in `Assets/models/<kit>/`) as `../../../tools/out/<kit>/<id>.obj`. Every vmdl `asset_compile` returned `Success:false`; `read_console` showed `ERROR: Could not determine dependency search path and relative path: '...\tools\out\...\<id>.obj'`. The compiler only resolves mesh sources that live UNDER the content root. Fix: put the OBJ (+MTL) inside `Assets/` (e.g. `Assets/models/<kit>/src/`) and reference it CONTENT-ROOT-RELATIVE, exactly like the vmat remaps already do — `filename = "models/<kit>/src/<id>.obj"`, NOT vmdl-relative and never `../` out of Assets. Keep the generator as the single source of truth (edit its OBJ_DIR + the vmdl filename field, then re-run headless) so on-disk vmdls never hand-diverge. Verified via the editor MCP `asset_compile` (fail on `../`, Success on the content-root path) on all 16 kit vmdls.
- **The s&box OBJ→vmdl importer treats OBJ's bottom-up `vt` V as engine top-down UV — write `vt u (1-v)` when exporting, or every face samples the VERTICALLY-MIRRORED atlas row.** A runtime-terrain exporter dumped each chunk's live `TexCoord0` straight into the OBJ (`vt u v`). The mesh geometry, collision, and byte-for-byte determinism all passed — but rendered, the terrain was red/brown badlands **speckled black** instead of the live green grass. Cause: the importer flips V on import (OBJ V is bottom-up, engine samples textures top-down), so a raw `v` samples `1-v`. With a palette atlas whose colored strata cells live in the UPPER rows and whose lower half is empty/black, the mirror landed grass on the wrong colored row and many faces on the black lower cells (the speckle). Fix: pre-compensate — write `vt u (1-v)` in the render OBJ (collision OBJ has no UVs, so it's unaffected). PROVEN by a same-pose top-down of the exported central block vs the live world: **41.8 % mean pixel diff pre-fix → 0.00/255 (pixel-identical in the block interior) post-fix.** The load-bearing lesson: **geometry + collision + determinism passing does NOT prove the render is faithful — a UV/material/normal fault is invisible to those gates. Always run a same-pose live-vs-export pixel-diff on a central block.**
- **A low-poly wheel that renders as a featureless black blob has TWO compounding causes, both geometric — a lighter rim material alone will NOT fix it.** (1) A `cylinder` tire has a SOLID outboard end-cap (a disc of radius R in the tire colour). Any rim/spoke/hub geometry authored at or inboard of that cap plane is hidden BEHIND it — the face you see is the dark tire cap. The alloy face must ride PROUD of the tire cap (outboard), e.g. spokes/hub at wheel-local `y ~ tireHalfWidth + 0.01..0.02`, still inside the arch-lip plane so it never pokes the fender. (2) If the fender/quarter wheel arch is a SOLID flat panel with no cutout, it covers the wheel from outboard and the wheel is "swallowed" — only the bottom tread shows below the body. Cut an actual wheel opening: on a subdivided (`panel`) arch, delete the grid faces whose centre is within `r_open` of the hub in the part-local X-Z plane (`r_open >= tire R` so the tire also stops clipping the fender skin). Both fixes are deterministic (proud primitives + geometric face-delete, no RNG) and cost ~0 tris. Diagnosis tip: tint the wheel/arch parts a bright flat colour and re-render — if the tint never appears, the part is occluded, not mis-coloured. PROVEN on a sedan's views/ortho sheets: black-blob → readable 7-spoke silver alloy in an open arch. (2026-07-14)
- **"The glass doesn't fall in line with the A-pillars" is usually the UPRIGHT side-window (DLO) leading edge poking past the raked pillar — NOT the raked windshield, which is invisible edge-on in profile. Verify which glass actually disagrees before changing the windshield.** A raked windshield/backlight box that is co-planar with its pillar line renders as a thin sliver (edge-on) in pure profile — so in a profile screenshot the windshield CANNOT be what disagrees; what disagrees is the front DOOR window, an upright box whose vertical leading edge juts forward past the raked A-pillar (worst at the top). Confirm by (a) a numeric co-planarity check of the windshield slab normal vs the pillar centreline, and (b) an edge-on ortho + a bright-tint render (the raked glass shows NO broad face in profile; the door glass does). Fix the DOOR glass, not the windshield: deterministic bmesh `bisect_plane` of the front-window slab on the A-pillar/windshield plane + `contextual_create` cap, so its leading edge becomes co-planar with the pillar. The load-bearing lesson: a paraphrased art-defect ("windshield") can point at the wrong part — reproduce the exact defect on the sheets and isolate the culprit part (tint) before editing generator geometry.
- **An offline assembled-views sheet can show wheel rims as black blobs even when the in-engine wheels are fine — if the sheet's poses show the side whose wheels the sheet does not mirror.** The kit generator's views renderer imports the single wheel OBJ at all four hubs UNMIRRORED, while the runtime assembler mirrors the right-side wheels so the authored outboard rim face points outboard on BOTH sides. Default poses (front −90 / three-quarter −55 / side 0 / rear +90 with the camera at −Y) all show the AUTHOR-RIGHT side, where the unmirrored wheels present their featureless inboard face — so the wheel-readability eyeball gate judges the wrong thing (bit on one vehicle kit: sheet showed dark discs, geometry was correct). Fix: judge wheel readability on LEFT-showing yaws (front −90 / three-quarter −125 / side 180 / rear +90), made a per-kit plan override (`views.poses`) in the kit generator; alternatively mirror right-hub imports in the sheet. (2026-07-14)
- **On a tall OPEN-TOP vehicle the seated-citizen sit tuple derived from closed-car precedent puts the driver's feet visibly BELOW the body.** The citizen root is at the FEET; the proven closed-car relation (seat-pan top ≈ tuple-z + 0.47, sedan) parks the feet 30+ cm under the interior floor — invisible on a sedan whose body sides drop to ~0.16 m, but a high-riding open 4x4 (floor at 0.42+, nothing below but frame rails) shows feet/shins hanging under the tub from the side. Two-part fix, verified on the views-sheet mannequin of one 4x4 kit: (1) raise the tuple so the feet land inside the underbody band while the head stays under the rollover bar; (2) author a dark drivetrain/skid block between the frame rails spanning that band (0.30–0.42 m) — it screens the residual clip AND reads as authentic 4x4 underbody. Final in-engine tuple tune still applies (the offline mannequin exaggerates by ~7 cm — its feet sit below its root, the engine citizen's root IS the feet). (2026-07-14)
- **On a flat-shaded box vehicle kit (no real wheel-well cutout) a wheel-arch flare authored OUTBOARD of the tyre's outer face occludes the wheel from the side — the wheel reads as buried behind the body, and if the rim disc is also coplanar with the tyre sidewall it flickers as a body-colour disc plastered on the fender.** The wheel reads only if EVERY body/trim panel across the wheel silhouette sits inboard of the tyre face (`track/2 + wheel_width/2`), so the tyre is the outermost surface. Law: the flare outer edge = that axle's tyre face − 2.5 mm. Two traps: (1) front and rear tyres often differ (wide rears) — a flare tuned to the wide rear tyre sits ~2 cm proud of the narrower front tyre and swallows the front wheels, so compute the flare centre PER AXLE (a coupe buried its front wheels this way; a pickup's flares sat 1 cm proud on both axles). (2) A rim/hub disc at the tyre's full width is coplanar with the black tyre sidewall → guaranteed z-fight; recess it inboard (Wd−0.04..0.05) for a deep-dish look that never fights. A coplanar-face census does NOT catch the occlusion (an occluding flare is ~1 cm proud, not coplanar) — it needs a face-based (not vertex-based: a box flare's verts sit at its X-Z corners, OUTSIDE the wheel disc, while the face spans across it) outboard-of-tyre test over the wheel silhouette (a `check_coplanar.py --arches` mode).
- **`Bounds.Maxs.z` is the mesh's FULL extent (incl. invisible thin tips), NOT the visible bulk — and with an `import_translation` origin shift it is NOT "distance to the visible top".** A rope-end knob mesh is a bulbous BALL topped by a thin twisted NUB running the top ~50% of its long axis. Its vmdl `import_translation [0,-0.501,0]` (OBJ-Y → model-Z) parks the mesh ORIGIN at the ball/nub junction (= the visible ball top). Code shortened the rope ribbon by `Bounds.Maxs.z * scale` to "meet the knob's top", but `Maxs.z` measures origin → nub TIP (the invisible thin end), not origin → ball top (which is 0). So the ribbon over-shortened by a full nub-length: it ended high, the invisible nub spanned a ~0.3-0.5m clear-air gap, and the ball floated a nub below with its tip pointing up — reading as DETACHED. Fix: for a mesh whose origin already sits at the visible attach point, anchor by the ORIGIN (place origin at the target, offset 0), do not add a `Bounds.Maxs.z` term. Reserve the `Maxs.z·scale` "top" trick (see g-art-model-top-ui-markers) for grounded meshes whose origin is at the BASE, where Maxs.z really is the visible top. Confirm which by checking the vmdl `import_translation` and eyeballing in-engine, not by assuming Maxs.z == visible top.
- **A Forge/Tripo gen for a WEARABLE/HELD item comes back as a whole CHARACTER wearing the item, not the isolated item.** Prompts like "a rocket jetpack" or "a pair of rocket boots" bias the text-to-image concept toward a person modelling the gear, and Tripo then builds that person. Tells: the build-result `stats.dimsM` height ≈ 1.0 with a humanoid silhouette, and the farm judge notes complain about "character proportions / facial features / head size" for what should be a prop. A delivered jetpack that is silently the whole character scaled to ~0.5 m will stick a tiny person on the citizen's back. Two recoveries: (1) if the gen produced a DETACHED copy of the item alongside the character (Tripo often drops a standalone pair of boots on the ground next to the figure), isolate it in headless Blender — join, ground min-z→0, histogram the vertex Z to find the empty gap between the item cluster (low) and the character (high, often floating), then `bmesh.ops.delete` everything above the gap. Verify with a 4-view inspect render. (2) if the item is worn/attached (jetpack straps against the back — no clean split), REGENERATE with an isolation-hardened prompt: "…as an ISOLATED standalone object on a plain empty background, absolutely NO character, NO person, NO body, NO legs, NO head — JUST the device, product-shot, centered…". Always 4-view-inspect a Forge item mesh before finalizing, exactly because of this.
- **Isolating ONE clean object from a Tripo multi-object mesh (e.g. a boots PAIR) that is diagonally STAGGERED and shattered into dozens of unwelded greeble islands.** Per-vertex 2-means on XY cuts a straight bisector THROUGH both overlapping elongated parts, so each cluster is a malformed mix (cuffs but no feet). Cluster the ISLAND CENTROIDS instead: union-find the connected components, then 2-means on their centroids (weighted by vert count) — no island ever spans the air gap between the two objects, so each object comes out whole. Loose-part `separate` is useless here (46 tiny islands, none a whole boot). To then get a symmetric PAIR, MIRROR the denser object on Y (scale y=-1 + `recalc_face_normals`): UVs are per-loop and unaffected by object scale, so both halves sample the intact atlas — and a single mirrored object sidesteps the per-part re-split that CORRUPTS a shared texture atlas. **Aligning the isolated object's heel-toe axis to +X: a PCA major axis is ILL-CONDITIONED on a near-square footprint** (a boot's round ankle shaft makes X≈Y spread, so PCA picks a diagonal/wrong axis) **and sign-AMBIGUOUS** (a taller-half toe test flipped it a full ~167°, toe → −X). Derive the direction vector DIRECTLY: ankle = centroid of high-Z verts (the vertical shaft column), toe = the low-Z (sole) vert FARTHEST in XY from that column; rotating `(toe − ankle)` onto the target axis fixes angle AND sign in one shot. **Also: a white/untextured Blender preview AFTER bmesh surgery + mirror + join is a render-SETUP bug, not lost UVs** — confirm by re-importing the EXPORTED obj fresh and applying the atlas (the proven render_icons path); a strong sun + `view_transform='Standard'` on a 0.8-albedo atlas blows it to white. Decouple asset-quality checks from the in-memory preview.
- **When a flicker/FX effect cycles between several mesh FRAMES of differing length by swapping the model on ONE GameObject, the model ORIGIN is the only point pinned in space — every other vertex moves the instant a frame swaps.** So the origin MUST sit at the visually-dominant / attachment end (for a thrust plume: the WIDE MOUTH at the nozzle exit), and ALL cycle frames must share IDENTICAL geometry at that anchored end (same mouth radius), with per-frame variation confined to the FAR (tip) end. Authoring the origin at the NARROW apex while the wide end is free — AND letting frames differ in BOTH length and the free-end radius — makes the visible wide end swing and pulse at the cycle rate: one project's thrust flames were apex-at-origin with the wide base free across three frames of height 0.24/0.32/0.40 m and base radius 0.090/0.080/0.074, so at 10 Hz the mouth bounced ~0.16 m and breathed width ("flames bouncing/flipping unnaturally"). Fix = flip so the wide mouth is at z=0 (unchanged origin — the baked mount PosM still seats the same point, only which END sits there flips) and give every frame ONE shared mouth radius; only `height` (tip depth) varies → the mouth is motionless, the tip flickers downward. **Second trap: a uniform `LocalScale` pulse scales about the origin, so once the anchor IS the mouth a uniform pulse breathes the mouth radius.** Scale the plume-LENGTH axis only (non-uniform `LocalScale`, mesh Z = plume axis — innermost in the transform, so it stretches length regardless of the child's `LocalRotation` aim, no skew) to keep the mouth ring invariant and confine the pulse to tip length. Measured headless before/after (mouth r=0.085 @ z=0 on all three frames, tip r=0 @ z=−height). **Unverified:** the in-engine look is not confirmed; it needs a real game-window check by hand.
- **One project's playground kit author→engine frame = `(-bY, +bX, bZ)`** (engine.x = −authorY, engine.y = +authorX, engine.z = +authorZ), IDENTICAL to a sibling project's: same export recipe (Blender 5.1 `wm.obj_export forward_axis='NEGATIVE_Z', up_axis='Y'`, vmdl `import_rotation [0,0,0]`, `import_scale 39.37`, engine 26.07.08e). The chain is self-consistent and worth recording as ONE contract: the exporter writes OBJ `= (bX, bZ, -bY)`; the s&box import is the PLAIN cyclic `model=(objZ, objX, objY)` (the un-negated variant in this file); composing gives net `(-bY,+bX,bZ)`, det = +1 (a proper rotation, never a mirror). Consequence to watch: a collider/panel authored THIN on author-Y (e.g. a 2.0×0.315×2.0 m climb panel) becomes thin on ENGINE-X, so a loader that skips the map places the collider thin on the wrong axis and it no longer matches the rendered mesh — the map is load-bearing, not cosmetic. Verified numerically at the exporter half (the `frame_probe` OBJ: red handle authored +X → obj x-max 0.8; blue knob authored +Z → obj y-max 0.7; symmetric author-Y → obj z symmetric), and a boot audit (`PlaygroundKit.ResolveFrameMapping`) confirms the import half at runtime by matching `Model.Bounds.Size` to the per-axis-distinct probe extents within 5% (expected `(39.37, 51.18, 47.24)` u) and reading the handle/knob protrusion signs off `Bounds.Center`, deriving the symmetric axis sign from det = +1. Determine each pipeline's map from an asymmetric probe — do not port another kit's constant on faith even when the recipe looks identical.
- **A rotation maps LOCAL +X->Forward, +Y->Left, +Z->Up -- NOT +X->Right.** A rotated-AABB envelope builder that took the local +X edge as `Rot.Right * halfX` and the +Y edge as `Rot.Forward * halfY` TRANSPOSES the X/Y footprint of an axis-aligned box (a 4.4x0.4 E-W wall was audited as a 0.4x4.4 N-S slab and false-overlapped a neighbour). Invisible for symmetric/square/well-spaced props; bites the first non-square box. Correct: local (1,0,0)->`Rot.Forward`, (0,1,0)->`Rot.Left`, (0,0,1)->`Rot.Up` (abs the result so Left-vs-Right sign is moot).
- **Per-part pivot/bounds checks stay ALL-GREEN while the assembled vehicle is visibly wrong.** A generated part kit passed its whole in-script battery (hinge-side one-sided bounds, envelopes, hub-centred pivots) while the windshield leaned FORWARD over the hood, the rear glass overhung rearward ("floating hatch lid"), and the hood sat sunken between flat fender boxes reading as an open trough — slope DIRECTION and panel FLUSHNESS are invisible to bounds asserts (a slab rotated +40 and −40 has identical bounds envelopes). Root cause was the R_y sign rule (rot **+θ about Y tips a slab's +X edge DOWN / its +Z top toward +X**, so in a +X-forward frame windshields need NEGATIVE θ and rear glass POSITIVE — the existing rotation-sign gotcha), but the durable fix is the GATE: render an **assembled multi-pose sheet** (front/3-quarter/side/rear, parts placed at their attach-table offsets) in the same headless Blender run and eyeball it before shipping — it caught the inverted glass, the trough hood, and tire-face/arch-lip coplanar z-fights that no numeric check flagged.
- **The INVERSE of the missed `* M`: a helper that already returns WORLD UNITS, fed into an API that re-applies `* M`, double-scales by ~39x and flings the body OFF-MAP.** A pilot waypoint builder returned `pos = new Vector3(xm,ym,zm) * M + originU` (world units), but the routine interpreter's Teleport/MoveTo treat their arg as METRES and multiply by M again, so the run leg teleported the character to ~39x its intended coordinate; it free-fell, was recovered to spawn, then steered off the safe corridor into a void (a fall-through invariant fired). Sibling legs that passed METRES (`FaceCenterU / M`) worked -- the one odd consumer was the tell. Symptom = target ~39x too FAR / off-map free-fall (vs the missed-`* M` "marches in a fixed wrong direction, never arrives" symptom). Rule: know whether a position API's arg is metres or units and convert AT the boundary; a self-consistent world-units helper must be `/ M`'d before entering a metres API.
- **A visual box PARENTED to a yaw-rotated anchor and scaled long on LOCAL X renders its long axis 90° off from the anchor's `.Left` — because scale is applied in the child's LOCAL frame, then rotated by the inherited rotation.** A horizontal swing-bar's grab code read the bar axis as `anchor.WorldRotation.Left` (the anchor's local +Y in world space; anchor built with `Rotation.FromYaw(90)`), but the visible crossbar was a child of that anchor scaled `(1.6,0.12,0.12)` = long on LOCAL X. Yaw+90 rotates local X onto `anchor.Forward`, which is PERPENDICULAR to `.Left`. Result: the beam rendered across the grip axis, so the character hung with its body ALONG the beam and swung THROUGH the bar plane instead of around it (caught in playtest). Sibling bars looked right because their visual mesh was a DECOUPLED sibling at yaw 0 (long axis = world X) that `.Left` runs parallel to — only the child-of-anchor variant inherited the yaw. Fix: scale the child long on the LOCAL axis that its inherited rotation maps onto the intended world axis (here LOCAL Y → `.Left`), i.e. `(0.12,1.6,0.12)`. Rule: when a child visual must line up with an axis you derive from the PARENT's rotation (`.Left`/`.Forward`/`.Up`), reason in the child's LOCAL frame — `WorldScale` does not re-align a box to world axes; the box still renders rotated by its (inherited) WorldRotation. Purely visual: a determinism/placement hash over element type/position never covers a cosmetic scale, so the fix is hash-neutral.

- **Per-shape `collision_tags` in a vmdl PhysicsShapeList are INERT at runtime on a scene `ModelCollider` — every shape ends up with the GameObject's tags, NOT its authored tag.** `ModelCollider.CreatePhysicsShapes` reads only Surface/BoneIndex (never collision_tags), then `Collider.ConfigureShapes` does `shape.Tags.SetFrom(GameObject.Tags)` over every shape. A multi-hull model authored with per-shape tags cannot be filtered per-shape by `Scene.Trace.WithoutTags` — all shapes carry the collider GameObject's tags. To get per-CLASS trace filtering, split the shapes across SEPARATE collider GameObjects, each with its own `GameObject.Tags` (those DO surface to shapes). Symptom: a wide canopy hull acted fully solid — blocked the character mover far from the trunk and ate projectiles aimed at players under the tree.
- **`ModelRenderer.Tint` is dropped in reflection passes: a glossy floor mirrors tinted models as WHITE ghosts.** Per-renderer tint applies only in the main view; screen-space reflections and environment probes render the untinted albedo. A fully matte override (`TextureRoughness` 1.0) does NOT remove it (probe term still draws recognizable shapes). Content fix: bake color into per-variant materials instead of renderer tint when models appear in reflections, or keep reflective floors away from tinted models. For captures: disable SSR for the session and frame with a shallow vertical FOV.

- **A time-of-day sky must never crossfade by swapping the sky texture or `SkyBox2D.SkyMaterial` discretely — a hard material swap is a visible, jarring pop.** Stacking two `SkyBox2D` components and crossfading via `Tint` alpha does NOT composite either: the sky pass renders the far plane opaque (pixel shader always outputs alpha 1, no blend state), so whichever draws last overwrites outright regardless of alpha. `SkyBox2D` exposes only `SkyMaterial` and `Tint` (a Color multiply) — no native blend knob. Fix: one custom sky shader holding ALL time-slot textures simultaneously, outputting a weighted sum in the pixel shader; CPU-side driver pushes blend weights every frame via `Material.Set(...)`, smoothstepped so the outgoing weight reaches exactly 0 at each boundary. The material reference never changes mid-cycle — only its blend weights do. → [fix article](/fix/sky-hard-swap-pops-weighted-blend-fix)

- **A brand-new custom `.shader` committed WITHOUT its compiled `.shader_c` fails its first in-editor load with a misleading error chain, even when the HLSL is correct.** The sequence is "Invalid Dependency Information" -> "Failed on-demand recompile" -> "Error loading resource file `<shader>_c` (File not found)", while the engine's own background compile of the same shader succeeds seconds later and writes a valid `_c`. The engine loads shaders only from `_c`; a never-compiled shader has no dependency record yet, so the on-demand path fails while racing that background compile. Fix: commit the `.shader` source TOGETHER WITH its `.shader_c` (a re-save regenerates it). `.shader_c` IS tracked in source control; `.vmat_c` conventionally is NOT. Also: a headless `dotnet build` compiles C# only and can never catch a shader problem, and the editor `asset_compile` tool does not support shader assets at all (throws "has no source file" even on a known-good shader).
- **A crossed-quad "card" mesh (two perpendicular double-sided quads, the cheap billboard substitute for a smoke/exhaust puff) rendered through a plain `ModelRenderer` reads as a flat glowing plus/cross once the camera is far away and no longer roughly perpendicular to either quad.** `ModelRenderer` never camera-faces its mesh, so the crossed-card illusion only holds at its home use case (small, viewed close and near-perpendicular); a large self-illum crossed card viewed across a map shows its literal two-plane geometry instead of a puff. Fix: for a distant self-illum FX element use an orientation-invariant mesh -- a small self-illum UV sphere -- which is identical from every angle, can never present a flat silhouette, and needs no billboarding code; reserve crossed cards for close, roughly-front-on FX. Note: the engine ships NO runtime particle/spark `.vpcf` assets to reuse (a sweep of the install's core/addons trees found only a template plus editor-gizmo sprites), so game-side FX built from pooled primitives is the expected path, not a gap to work around.
