# Getting art in — skill pack

> Lane pack. Load `_core.md` first, then this file. Denser than the full articles by design;
> for a matching bullet's full write-up, follow that gotcha's article link in `coverage.md`
> (full articles live on the Field Guide website, not in this pack). Sanitized public
> advice; unconfirmed details marked `(needs verification)`. The sync appends new bullets here.

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
- `ModelRenderer.Tint` multiplies — usable for cheap state visuals (watered soil,
 ghost previews with alpha, team colors). Values > 1 brighten.
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
- **DOUBLE-TINT: a flat-color vmat override × a non-white renderer tint = a void slab.** The
 another project flat materials bake their color into `g_vColorTint` with `g_flModelTintAmount 1.0`;
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
 `g_vSelfIllumTint`. Working recipe for a flat GLOWING material colored per-instance at
 runtime: `F_SELF_ILLUM 1` + white albedo (`TextureColor` white.png) +
 `g_flModelTintAmount 1` + `g_flSelfIllumAlbedoFactor 1` — then `renderer.Tint` colors
 BOTH the surface and the glow from one shared material (no per-color vmat). Add
 `F_TRANSLUCENT 1` + an alpha texture for a glowing decal (ring/marker). General rule:
 when a template omits a field you expect, grep the compiled `*.shader_c` for the param
 string before concluding it's unsupported — combo-gated features are invisible in the
 template dump.
- **`PointLight` is a usable game Component even with no sibling precedent and thin XML
 docs.** The engine XML lists no `Radius`/`LightColor` on `Sandbox.PointLight` (only the
 base `Light.LightColor`), and no game project uses it — but the install's EDITOR addons
 do, with the real config: `var l = go.GetOrAddComponent<PointLight>; l.LightColor =
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
 `world = (-objZ, -objX, objY)` and "author +X faces world −Y, +90° yaw to face +X"
. On one project's pipeline (Blender 5.1.2 `wm.obj_export
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
- **A Forge/Tripo vehicle-shaped mesh's raw bbox can't tell you WHICH horizontal
 axis is length vs width by magnitude alone if the ratio is close — but "length ≥
 width" for any real vehicle is a free constraint, so the LARGEST of the two
 horizontal OBJ-space dimensions is safely assumable to be length** (confirmed by
 eye against the judge's contact-sheet render for both a dune buggy and a jet ski —
 side-view renders showed the long axis nose-to-tail in both cases). Still flag
 this as unverified-in-engine in any handoff doc — a `spawn_model` + screenshot is
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
- `.vmat` essentials: `shader "shaders/complex.shader"`, `TextureColor`,
 `TextureRoughness "[r r r 1]"`, `g_flMetalness`. Tiling via `g_vTexCoordScale "[n n]"`.
 Sky: `shader "shaders/sky.shader"` + `SkyTexture` (equirect PNG works).
- `ModelRenderer.Tint` multiplies — usable for cheap state visuals (watered soil,
 ghost previews with alpha, team colors). Values > 1 brighten.
- **Blender OBJ import `up_axis='Y'` puts Y→Z rotation in `matrix_world`, not vertices** — raw `.co.z` reads the file's horizontal axis. Apply transforms after import (`bpy.ops.object.transform_apply`) to bake world-Z-up into vertex coords.
- **`bpy.ops.object.duplicate()` in headless Blender can share the mesh datablock** — a bmesh edit to one mutates both. Re-import per output or force `obj.data = obj.data.copy()` for independent meshes.
