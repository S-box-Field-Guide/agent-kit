# Asset pipeline: Blender → s&box

The proven flow.

## Stage 1 — model generation (Blender headless)

```
blender --background --python tools/gen_models.py
```
(Blender install: `C:\Program Files\Blender Foundation\Blender 5.1\blender.exe`)

Conventions per model function:
- `bpy.ops.wm.read_factory_settings(use_empty=True)` — clean slate each model.
- Build from primitives in **real-world meters**; chunky low-poly, shared flat-color
  palette. Materials: `use_nodes=True`, set Principled `Base Color` **and**
  `diffuse_color` (that's what the OBJ exporter writes as `Kd`).
- Join everything, `transform_apply`, ground at z=0
  (`obj.location.z -= min_z`) — **except** parts with joint pivots (see below).
- Export: `bpy.ops.wm.obj_export(filepath=…, export_materials=True,
  forward_axis='NEGATIVE_Z', up_axis='Y')` → Y-up OBJ + MTL.

**Animated parts:** export limbs/rotors as separate models with the origin AT the
joint/axle (`ground=False`). Assemble in C# as child GameObjects and drive
`LocalRotation`. Character = torso + 2 legs + 2 arms (swing via `Rotation.FromRoll` —
sideways axis is local X for a −Y-facing model). Rotors (turbine blades, water
wheel) spin via `Rotation.FromPitch` (axle along Blender X). Compute child local
offsets by mapping Blender coords through `world = (-bY·s, -bX·s, bZ·s)`.

**State-swap models** (picked berry bush): generate variants with the **same random
seed** so the silhouette matches, swap `renderer.Model` at runtime.

## Stage 2 — asset conversion (pure python, no Blender)

```
python tools/gen_assets.py
```

Does four things:

1. **Textures** — dependency-free PNG writer (zlib + struct, 8-bit RGB) + tileable
   value-noise/fbm generators for grass/dirt/water/snow, equirect sky. Copy the
   `write_png`/`noise_grid`/`fbm` trio verbatim.
2. **Materials** — one `.vmat` per palette color (white.png + `g_vColorTint`; see
   gotchas: constant-color TextureColor doesn't compile), world materials with
   `g_vTexCoordScale` tiling, sky material with `shaders/sky.shader`.
3. **Models** — copy OBJ+MTL into `Assets/models/<proj>/`, emit a `.vmdl` per model:
   KV3 text header + `MaterialGroupList` remaps (**both** `Name` and `Name.vmat` →
   your vmat) + `RenderMeshFile` with `import_scale` and zero rotation/translation.
4. **The C# catalog** — `Code/Game/Models.generated.cs`: model name → vmdl path +
   world-space `Size`/`Center` (computed via the axis transform
   `world = (-objZ, -objX, objY) * scale`). Colliders and placement footprints read
   from this — single source of truth, regenerates with the art.

### Scaling: two approaches

- **Uniform scale:** author in meters, one `import_scale = 39.37`
  for everything. Sizes are automatically real-world.
- **Per-model target size:** for imported kits (Kenney), parse OBJ
  bounds and compute `scale = target_units / native_extent` per model. Needed when
  you don't control the source scale.

## Kenney / external kits

- CC0 kits import the same way (copy OBJ, generate vmdl). City kits use one shared
  `colormap.png`; nature kits are flat Kd colors → per-color vmats.
- Model "front" is a 50/50 guess — hard-code a facing yaw constant per model and
  verify visually.

## Checklists

New model:
1. Add generator fn to `gen_models.py` + register in `GENERATORS`.
2. Add its name to `MODELS` in `gen_assets.py`.
3. Run both tools; check the printed world-space size is sane.
4. Reference via `GameModels.PathOf("name")` (or your project's catalog).

Sanity-check before batching many models:
- One angled piece (roof, ramp): confirm the rotation sign visually (we shipped
  upside-down roofs — Blender +Y-rotation tips +X *down*).
- One placed instance: confirm facing (Blender +X → world −Y; yaw+90 → +X).
- Flat ground decals (water/roads): top surface must be ABOVE the ground plane top.
