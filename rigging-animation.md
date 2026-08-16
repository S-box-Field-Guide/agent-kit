# Rigging & animation — skill pack

> Lane pack. Load `_core.md` first, then this file. Denser than the full articles by design;
> for a matching bullet's full write-up, follow that gotcha's article link in `coverage.md`
> (full articles live on the Field Guide website, not in this pack). Sanitized public
> advice; unverified material is held privately until verified. The sync appends new bullets here.

## Skeletal rigging & animation (FBX)

- **Animated models: use `ModelModifier_ScaleAndMirror` (scale 0.3937 for cm sources),
  NOT per-file `import_scale`** — the modifier scales mesh AND animations together;
  import_scale on the RenderMeshFile leaves AnimFile data unscaled. Blender-meters →
  FBX writes raw centimeters (apply_unit_scale) → 0.3937 → engine inches. This is the
  citizen convention (see the note inside citizen.vmdl).
- **The citizen addon source is the vmdl schema reference** for anything animated:
  `sbox/addons/citizen/Assets/models/citizen/citizen.vmdl` + its `prefabs/*.vmdl_prefab`
  give exact KV3 for AnimFile/AnimationList/BoneMarkupList fields. AnimationList wants
  `default_root_bone_name = "pelvis"`; keep pelvis the TRUE root bone (no roots above
  it), set `bone_cull_type = "None"` to keep helper bones.
- **Blender FBX export recipe that works** (verified in-engine, orientation + scale
  match the OBJ path so facing-yaw constants stay valid): default axes (forward −Z,
  up Y), `bake_space_transform=True`, `add_leaf_bones=False`, `primary_bone_axis='X'`,
  `secondary_bone_axis='Z'`, meters authoring, one FBX for mesh+skeleton
  (`bake_anim=False`) plus one armature-only FBX per clip (`bake_anim_use_all_actions=
  False`, active action only). Binary FBX is what Blender writes — required.
- **Bone-heat auto-weights fail wholesale on AI-generated meshes** ("Bone Heat
  Weighting: failed to find solution", ALL vertex groups empty — even for a 2-bone rig
  on a cleaned single-island mesh). Fix that works: scripted weights using GEODESIC
  (along-surface Dijkstra) distance to per-bone seed tubes, top-3 bones, inverse-power
  blend, ~10 diffusion passes, cap 4 influences. Euclidean nearest-bone is NOT enough —
  chibi proportions put cheek verts closer to arm bones than the head bone. See
  tools/rig_hero_character.py.
- **Scripted keyframes: keep quaternion keys hemisphere-continuous** — converting
  euler poses per-key can land on q vs −q between neighbours and the interpolation
  takes a violent 360° detour (poses explode only BETWEEN keys). Negate the quat if
  dot(prev, new) < 0.
- **Blender's OBJ importer puts the Y-up→Z-up fix on the OBJECT transform** —
  `mesh.vertices[i].co` stays in file-local Y-up coords. Any scripted geometry
  analysis must use `obj.matrix_world @ v.co` or seed/landmark math is silently
  wrong.
- **Per-bone procedural override via `SetBoneTransform` is UNSOUND on clip-animated
  bones.** The API exists (`TryGetBoneTransform[Local]`, `SetBoneTransform(in Bone,
  localTx)` — verified by reflecting Sandbox.Engine.dll) but behaves inconsistently:
  overrides PERSIST on bones the active sequence does not key (reads return your own
  prior write → unbounded accumulation → tail wound through the floor), yet get
  STOMPED on bones the sequence DOES key (a delta-backout then corrupts the clean
  pose → torso spazz through shared skin weights). Read-modify-write against live
  bone state cannot be made safe from component code. Do secondary motion at the
  whole-visual level, bake follow-through into clips, or use a proper AnimGraph
  additive layer.
- **`SkinnedModelRenderer.SetIk` is ANIMGRAPH-GATED — it does nothing on a direct-sequence
  rig.** Its XML docstring (Sandbox.Engine.xml): *"Sets an IK parameter. This sets 3 variables
  that should be set in the ANIMGRAPH: ik.{name}.enabled/position/rotation."* So working hand/foot
  IK needs a `.vanmgrph` with those params wired — our character plays sequences directly (no
  AnimGraph), so SetIk/ClearIk are inert. There's ALSO a newer "Procedural Bones" path
  (`GetBoneObject(i)` → move the bone GameObject → `ReadBonesFromGameObjects` copies it back to
  the anim bone), distinct from the unsound `SetBoneTransform` write above — but the bone must be
  flagged Procedural (a model/AnimGraph authoring step) and read-modify-write against clip-keyed
  bones is still unsound. VERDICT for a sequence-only rig: no runtime hand IK without authoring an
  AnimGraph. When you need hands to grab a moving world target on such a rig, use PROXY PROPS welded
  to the target in world space (small tinted meshes parented to the CHARACTER ROOT, not the visual
  child that carries squash/flip) — cartoon-acceptable, zero rig work.
- **Pace looping locomotion clips by the clip's OWN authored stride, not the
  controller's top speed.** A clip authored as N frames @30fps implies a fixed
  ground distance per loop; depicted travel = PlaybackRate × (stride / loopSeconds).
  Set `PlaybackRate = actualSpeed / thatDepictedMps` for zero foot-slide. Keep the
  depicted-mps as its own const (e.g. `WalkClipMps = 1.125` for a 24f/0.8s ~0.9 m
  walk) — do NOT reuse the movement top-speed dial, they are independent. `SetSeq`
  writing `PlaybackRate = rate` unconditionally every frame means a hard clip switch
  (walk↔run gait) can never leave a stale rate from the outgoing clip.
- **Pair a procedural whole-body rotation with a clip that shapes the body — don't do
  both in one place.** The barrel roll composes a fresh 360° spin about the forward axis
  each frame (on the character visual component), while a one-shot "tuck" clip balls the body up; the clip
  owns the pose, the rotation code owns the spin. Author the one-shot ~1 frame LONGER
  than the move's duration and pace it `rate = clipLen / moveTime` so fold→hold→unfold
  spans the move exactly (rate lands just above 1). Both ENDS of such a one-shot must
  key a NEUTRAL pose that blends from/to the neighbouring states (here: a midpoint
  between the jump air-tuck hold and the fall spread) or it pops on entry/exit. The
  poser's per-key hemisphere negation keeps big folds (thigh −120°, forearm −125°)
  continuous for free. Generalizes to a character driven by the FULL citizen animgraph
  (`CitizenAnimationHelper`): there is no cheap way to splice a one-shot custom clip in from
  a headless/scripted pipeline (the animgraph owns the whole pose every frame and fights any
  `renderer.Sequence` override), so apply the same split instead — leave the animgraph as the
  sole pose writer and layer the procedural trick onto the existing single writer of the
  visual model's `LocalRotation`.
- **A new NPC clip in `add_humanoid_clips` must ALSO be added to BOTH `CLIP_ORDER`
  and `CLIP_FADE` in the NPC rig library.py, or `build_vmdl_anims` KeyErrors** (it iterates
  `CLIP_ORDER` and indexes `CLIP_FADE[sem]` to build the vmdl AnimationList — the
  Poser exports every action it holds, but the vmdl only lists what's in those two
  tables). Adding the clip authoring alone exports the FBX but silently drops it
  from the vmdl (or crashes). The rig scripts (the humanoid NPC rigs)
  need NO edit — they just call `add_humanoid_clips`, so all four characters
  inherit a new clip from one library edit + one rebuild each. WandererNpc.cs drives
  clips by literal sequence NAME (`_skinned.Sequence.Name = "idle"` etc.), so a new
  clip is inert until Code references its name — authoring is decoupled from wiring.
  To IMPROVE an existing idle without a Code change, rebuild the clip IN PLACE under
  the same name (Code plays `"idle"`); to add the migration-target name too, author
  the body once and `P.clip` it under both names (run→gets its own; the improved
  stand idle was registered as both `idle` and `stand_idle`).
- **Mixamo mocap retargets onto the NPC lane by REST-DELTA + PARENT-RELATIVE
  rotation transfer — and the Poser needs NO edit to consume it.** The proven
  retarget (tools/retarget_mixamo.py) transfers only motion AWAY FROM EACH
  SKELETON'S OWN REST so the different rest poses cancel: per source bone at frame
  f, `dq_src = M_anim @ M_rest^-1` (a pure WORLD rotation, rest-independent),
  reframe into our armature world with a fixed frame quat `F` (Mixamo world→our
  armature world = Rz(+90): Mixamo faces −Y/left +X, ours faces +X/left +Y), then
  the KEY subtlety — feed the Poser the PARENT-RELATIVE delta `Q = dq_parent^-1 @
  dq_bone`, NOT the raw world delta. the rig library.Poser composes bone_world = dq_parent @
  Q @ rest_world, so the raw world delta double-counts every ancestor rotation (the
  classic forward-HUNCHED-idle bug: Hips' yaw carried into Spine/Chest/Neck/Head on
  top of the pelvis's own). Dividing out the parent's world delta fixes it. The
  Poser's `key(bone,f,rot_deg)` builds `q_local = rest^-1 @ q_world @ rest` so the
  bone's world = `q_world @ rest` — i.e. the Poser's q_world argument IS a
  world-delta-from-rest, so you can bypass euler and key a quaternion directly with
  a 20-line `key_world_q(P, bone, f, q, loc)` helper in the retarget module (reads
  P.arm/P.REST_Q/P._last_q — no the rig library edit, keeps hemisphere continuity).
- **Never `transform_apply(scale=True)` on a Mixamo armature you're reading animated
  world translation from.** Mixamo imports at 0.01 armature-object scale;
  `matrix_world` ALREADY folds that in, so pose world matrices come out in METERS
  as-is. Applying the scale leaves the animated pose-bone LOCATION fcurves (authored
  in the pre-apply unit) unscaled, blowing Hips world translation up ~100× (a 1.6 m
  walk read as 163 m → an absurd 70 m/s stride measurement). Leave the object scale
  ON, read everything through `matrix_world`. Rotations are unaffected — only the
  root-motion/hip-bob translation.
- **Naturalistic mocap idles DON'T loop perfectly — pick the lowest-seam sub-window
  and let the vmdl fade cross-blend the residual.** Long ambient takes (Terrified
  601f, Talking-On-Phone 1166f) never return to an identical pose; even the best
  scanned window has ~5–8°/bone seam. That's fine for a NON-locomotion loop (no
  foot-slide to betray a soft seam) — the cyclic AUTO-handle pass + CLIP_FADE
  cross-fade smooth it. For true locomotion (walk/run) Mixamo's own take DOES loop
  (frame 1 == frame N, 0.0° seam): drop the duplicate seam frame and the wrap is one
  clean inter-frame step. Retarget preload MUST run BEFORE building the rig (importing
  a take does read_factory_settings and wipes the scene); the extracted quats are
  pure mathutils and survive later wipes, so cache-then-build (retarget_mixamo.
  preload_all at the top of each rig script). Root-motion rule: strip Hips world
  XY for locomotion (runtime moves the char), keep the vertical bob scaled by
  our_hip_z/mixamo_hip_z; keep full XYZ (scaled, window-relative) for sit/collapse.
  Depicted speed the retargeted in-place clip implies = Mixamo XY travel × hip_scale
  / window_seconds — report it as the pacing HANDOFF const, don't re-time the clip.

## Animation blending (smooth transitions on direct-sequence playback)

- **`SkinnedModelRenderer.Sequence.Blending` (a `bool { get; set; }`) is the cross-fade
  switch for DIRECT sequence playback — no AnimGraph required.** Engine XML docstring
  (Sandbox.Engine.xml, `P:Sandbox.AnimationSequence.Blending`, inherited by
  `SequenceAccessor.Blending`): *"Get or set whether animations blend smoothly when
  transitioning between sequences."* Set it ONCE after creating the renderer
  (`_renderer.Sequence.Blending = true;`) and every subsequent `Sequence.Name = "x"`
  hard-switch cross-fades instead of popping. This is the fix for the "walk↔run /
  ground↔air / idle↔walk snaps read as jank" problem — the whole `SetSeq`
  name-switch pattern in CharacterVisual/WandererNpc keeps working unchanged, it just
  stops cutting. Verified by reflecting Sandbox.Engine.dll (net10.0 scratch project —
  net8 crashes on Vector3 binding) + reading the shipped XML docs; the member resolves
  under `dotnet build`.
- **The blend DURATION comes from the vmdl's per-clip `fade_in_time` / `fade_out_time`
  (ModelDoc `AnimFile` fields), which our rig lane ALREADY authors** — the rig library's
  `_anim_file_block` writes them (default 0.2 s) and the NPC rig library's `CLIP_FADE` table sets
  per-clip values (idle 0.25, walk 0.20, run 0.15, shocked 0.05-in/0.20-out, etc.),
  written into the `AnimationList` by `build_vmdl_anims`. So the fade curves are baked
  into every `*_rigged.vmdl` (27 fade fields in hero_character_rigged.vmdl) and have been
  DORMANT the whole time — nothing in Code ever enabled `Sequence.Blending`, so the
  engine ignored them and hard-cut. Turning the flag on is the ENTIRE downstream change;
  no rebuild, no new clips, no AnimGraph. `Blending` is the on/off; the per-clip fade
  times are the shape.
- **AnimGraph is the heavier alternative and is NOT needed for cross-fades.** A `.vanmgrph`
  is text KV3 (`format:animgraph2`) but authored as an editor NODE GRAPH — GUID-keyed
  nodes with canvas positions (`m_vecPosition`), comment nodes, connection maps
  (see `addons/base/Assets/animgraphs/tutorial/*.vanmgrph`, esp.
  `tutorial_05_simple_state_machine.vanmgrph` at 1400 lines for a trivial 2-state
  machine, and `addons/citizen/Assets/models/citizen/citizen.vanmgrph`). Generating one
  per rig from a script is possible-but-brittle (you'd be emitting editor layout), and
  it's editor-authored in practice. The AnimGraph parameter API on the renderer is
  `renderer.Set("param", value)` / `renderer.Parameters.Set(...)` /
  `renderer.SetLookDirection(...)` / `renderer.UseAnimGraph` / `renderer.AnimationGraph`
  (all confirmed by reflection; `CitizenAnimationHelper.cs` is the reference caller —
  `Target.Set("move_speed", ...)` etc.). Use AnimGraph only when you need true LAYERING
  (additive secondary motion, bone masks, IK, aim-blend) that `Sequence.Blending` can't
  give — for plain state-to-state cross-fades it's overkill. There's also a
  `CDirectPlaybackAnimNode` (`SceneModel.DirectPlayback.Play(name)` /
  `Play(name, target, heading, interpTime)`) that plays a one-shot inside a graph and
  blends back — only relevant once you're already on an AnimGraph.
- **Two-renderer manual cross-fade is the WRONG path — don't.** With `Sequence.Blending`
  built in, spawning a second SkinnedModelRenderer and lerping opacity would double the
  skinning cost per character (a crowd of NPCs), need alpha-capable materials, and still
  look worse than an engine bone-space blend. `BoneMergeTarget` exists on the renderer
  but is for attaching a second skinned mesh to a parent's skeleton (clothes/props), not
  for blending clips.

## Ragdoll physics (scripted-rig NPCs — crumple without authoring collapse clips)

- **A scripted-rig NPC can RAGDOLL via engine physics — you do NOT author
  collapse/faint/get-hit clips.** Put a `PhysicsShapeList` + `PhysicsJointList` in
  the vmdl (capsule per major bone + joints), and the engine's built-in
  `Sandbox.ModelPhysics` component builds one physics body per bone, simulates them,
  and writes the results back onto the `SkinnedModelRenderer`'s bones. Ragdoll is
  therefore pure engine physics — NOT per-bone C# posing (that's the unsound
  SetBoneTransform trap above). Toggle: `Components.GetOrCreate<ModelPhysics>`,
  set `.Renderer` (the SkinnedModelRenderer), `.Model` (the same physics-bearing
  vmdl), `.Enabled = true`, `.MotionEnabled = true`; shove it via
  `_physics.PhysicsGroup.Bodies` → `body.ApplyImpulse(v)`. To stand back up:
  `_physics.Destroy()` (bone control returns to the renderer's Sequence next frame),
  snap the root to the pelvis body's rest position (`PhysicsGroup.Bodies[0].Position`,
  x/y only). All of `ModelPhysics.{Renderer,Model,MotionEnabled,Enabled,PhysicsGroup}`
  + `PhysicsGroup.Bodies` + `PhysicsBody.{ApplyImpulse,Position}` resolve under
  `dotnet build` (the type itself does NOT enumerate via reflection GetTypes — the
  engine registers it natively — but the members compile fine; trust the compiler,
  not the reflector, here). Verified in-engine in a real project.
- **The vmdl physics node schema (copy from CITIZEN):** two nodes in the RootNode
  children list — `PhysicsShapeList` (children = capsules) and `PhysicsJointList`
  (children = joints). A shape is `PhysicsShapeCapsule` with `parent_bone` (bone
  name), `surface_prop="flesh"`, `collision_tags="solid"`, `radius`, `point0`,
  `point1` (capsule axis in the bone's LOCAL frame; our rig's bones run down local
  +X, so a capsule is point0≈[r/2,0,0]..point1≈[len-r/2,0,0]). A joint names the two
  shapes by BONE NAME via `parent_body`/`child_body`: `PhysicsJointConical`
  (ballsocket — `enable_swing_limit`/`swing_limit` + `enable_twist_limit`/
  `min_twist_angle`/`max_twist_angle` + `friction`) for spine/neck/head/shoulder/hip,
  `PhysicsJointRevolute` (hinge — `enable_limit`/`min_angle`/`max_angle`) for
  elbows & knees. `anchor_origin` is the pivot in the PARENT body's local frame =
  the child bone's head = `[parent_len, 0, 0]`. Every joint's parent_body AND
  child_body must have a shape or the body floats disconnected (so give the NECK a
  body — it bridges chest→head). Reference verbatim:
  `sbox/addons/citizen/Assets/models/citizen/prefabs/citizen_physics{shape,joint}
  list.vmdl_prefab`.
- **Physics shape coords are in the SAME UNIT as the mesh+bones BEFORE the
  ScaleAndMirror modifier — for our meters→cm rig lane that means CENTIMETRES,** and
  the vmdl's `ModelModifier_ScaleAndMirror 0.3937` scales the physics shapes cm→inch
  TOGETHER with the mesh and anims. Proof: citizen.vmdl carries BOTH a 0.3937
  ScaleAndMirror AND cm-authored physics (radius 10.0 = a 10 cm pelvis capsule; see
  the note field in citizen.vmdl). So author capsule point0/point1/radius in cm
  (bone-length-meters × 100) and let the one modifier convert. Do NOT pre-scale to
  inches.
- **Opt-in additive authoring without editing the read-only the rig library:**
  `the NPC rig library.write_vmdl_physics` calls the rig library's `write_vmdl` to author the base
  animated vmdl, then STRING-SPLICES the two physics nodes in before the
  `MaterialGroupList` node (which write_vmdl always emits). Zero duplication of the
  vmdl schema, the rig library untouched, and a rig opts in by calling write_vmdl_physics
  instead of write_vmdl (only one humanoid NPC rig script does, this spike). Radii are a
  FRACTION of each bone's own length (PHYS_BODY_RADIUS_FRAC) + abs clamps, so it
  scales with proportions — no hardcoded human dims. SPIKE SIMPLIFICATION left as a
  tuning knob: `anchor_angles = [0,0,0]` (identity anchor frame; the clean +X rig
  keeps hinge/twist axes bone-aligned) with deliberately-generous swing/twist limits
  so an exact anchor-axis match isn't needed to read as a crumple — if a limb hinges
  around the wrong axis in-engine, tune `_anchor_angles` first.
- **The MODEL COMPILER sanitizes `.` → `_` in bone names, so physics KV3 that names a
  mirrored limb bone by its BLENDER name (`upper_arm.L`) references a bone that no
  longer exists in the COMPILED skeleton (`upper_arm_L`) — every limb body compiles as
  "Physics shape node references unknown bone / Unknown parent|child physics body" and
  the limb ragdoll floats disconnected on daze.** The FBX skeleton AND skin deformers
  keep the DOT name (`upper_arm.L`), so static FBX inspection looks fine and misleads;
  the truth is in the compiled `*_rigged.vmdl_c`, whose bone strings are `upper_arm_L`,
  `thigh_L`, `foot_L`… (dot gone). Torso bones (`pelvis/spine/chest/neck/head`) have no
  `.`, so they always resolve — which is exactly why only the LIMBS break and the torso
  ragdoll works. The citizen physics reference confirms the convention: it names mirrored
  bones `arm_upper_L / leg_upper_R` with UNDERSCORES, never dots. FIX: sanitize
  `.L`/`.R`→`_L`/`_R` ONLY at the string written into `parent_bone`/`parent_body`/
  `child_body` (the NPC rig library `_phys_bone_name`, applied inside `_capsule_block`/
  `_conical_block`/`_revolute_block`); keep the `bones` dict keys, the radius base-name
  lookup, and all FBX/armature/skin-weight authoring on the DOT names (those must match
  the FBX). This is a WHOLE-LANE defect — it hit every physics-bearing NPC rig
  (write_vmdl_physics), not just newly-added ones; a rig that "compiled Succeeded" with
  16 warnings looked fine in a headless build. VERIFY via the editor MCP asset_compile +
  read_console (warnings are timestamped; a fresh recompile that adds NO new-timestamp
  ModelDocCompiler warning is the proof — read_console returns the whole buffer, so an
  old `.L` warning lingers and must be dated to be dismissed). Same `.`-is-illegal-in-a-
  bone-name family as the material `.001`-dedup gotcha.
- **The stock citizen animgraph ships combat params (`b_attack`, `holdtype_attack`,
  `special_movement_states`) that `CitizenAnimationHelper` does NOT wrap.** Drive them with
  `renderer.Set(...)` by name. They are NOT networked -- replicate persistent state via
  `[Sync]` fields and fire triggers via `[Rpc.Broadcast]`.
- **Blender FBX export can be made byte-reproducible; until the two fixes below are applied it is NOT, so an unfixed pipeline gates rig-lib refactors on vmdl TEXT diff plus FBX SIZE, never FBX hash.** Two rebuilds of the same character with identical code produce FBX files with the same byte SIZE but about 1170 scattered differing bytes (offsets 339 to end), because Blender bakes an export timestamp and object ids into many records, so `sha256` differs run to run. DATED CORRECTION, engine 26.08.05, verified 2026-08-08: diffing two runs down to WHICH bytes differ isolates two caller-controlled causes, both fixable from the calling script: (1) `FBXHeaderExtension` stamps a `CreationTimeStamp` from the wall clock at export time; (2) every FBX object id comes from `fbx_utils._key_to_uuid`, which is `hash(key)` on a string, and Blender's embedded interpreter IGNORES `PYTHONHASHSEED` (confirmed present in `os.environ` and confirmed inert), so do not spend a round on that env var. Fix: rebind the export module's `datetime` to a fixed value before calling the exporter, and replace `_key_to_uuid` with a deterministic counter. Measured before the fix: 176 differing bytes on a static rig, 590 on an animated rig; after the fix: zero, held across multiple rebuilds. Once both fixes are applied, gate on FBX bytes directly: the file-SIZE gate is then the wrong default, because it only catches a changed vertex count and passes an export whose animated bone travel changed by tens of millimeters. Keep size-only gating as a fallback for a caller that has not applied the fixes. The vmdl text stays deterministic regardless (pure string formatting, byte-identical across runs).
- **A new blocky/primitive character reuses an existing armature + the ENTIRE shared clip library by building the mesh AROUND the bone table — no OBJ, no clip re-authoring.** Instead of the rig library's scene-import path (which imports+clobbers to a single material), build the mesh from primitives (bmesh boxes/discs) DIRECTLY in armature space (X-fwd, Y-left, Z-up, meters, identity object transform), one chunky box wrapping each bone segment, then call the same rig-library functions the OBJ characters use (build_armature, bind_geodesic_weights, Poser+add_shared_clips, finalize_interpolation, export_fbx_set, write_vmdl). Keys: (1) DISCONNECTED per-bone boxes are fine — the geodesic seed-tube weighter assigns each box to the bone whose seed radius covers it; forward-PROTRUDING parts (muzzle/belly beyond any tube) take the euclidean nearest-bone fallback, which is the correct rigid bone — 0 zero-weight verts. (2) A bone with 0 weighted verts (e.g. `spine` when only hips+chest boxes exist) STILL deforms correctly because its motion propagates through the bone hierarchy to its children's boxes (chest inherits spine⊕pelvis). (3) Multi-material: give the mesh named slots (fur/belly/paw) and pass write_vmdl a `remaps` list — each pair emits a bare + ".vmat" remap, so a chunky blocky character reuses the flat playground palette (wood/tan/grey_dark) with one DefaultMaterialGroup. Result: same 30 sequence names as the hero rig (byte-identical AnimationList names/loop/fades) so the character visual component drives it unchanged; 320 tris.
- **Geodesic seed-tube auto-weighting is the WRONG tool for a mesh built from disconnected primitives — use explicit rigid per-primitive assignment.** The seed-tube weighter (the fix for AI meshes) silently misfires on primitive islands: an island whose verts ALL miss every seed tube takes the per-vert euclidean nearest-bone fallback, which picks absurd bones (the blocky character's pelvis box bound to CHEST + both SHINS — the hip block followed the legs); a box whose corner diagonal exceeds its bone's seed radius (tail box: r·√2 = 0.051 > seed 0.05) seeds ONLY on neighbour bones and gets ZERO weight to its own bone; and a fat seed radius (head 0.16) claims verts of adjacent boxes (chest/neck/belly), shearing them when the head moves. Diagnose with a per-island dominant-bone histogram (union-find islands, sum group weights per island, flag islands whose dominant bone segment is far from the island centroid). When the mesh is ASSEMBLED from primitives you KNOW the intended bone per part: tag it at build time and bind each vert 1.0 to that one bone (the rig library's rigid-weights binder) — deterministic, shear-free, keeps every box a box. Weight inference is for meshes where the bone-per-vert is unknown.
- **Segmented rigid rigs: size joint overlap by the BALL-AT-THE-PIVOT rule, checked against extreme poses — rest-pose adjacency guarantees nothing.** Extend every child box THROUGH its joint pivot into the parent volume; a box whose inboard face is `e` past the pivot with cross-section half-width `c` always contains a ball of radius min(e, c) centred on the pivot regardless of bend angle (balls are rotation-invariant), so if the parent volume also covers part of that ball, NO clip pose can open a gap — the child provably emerges from inside the parent at every angle. Aim e ≈ c ≈ 4-5 cm at character scale. Corollaries: (1) pivots that sit OUTSIDE the parent box (hero shoulder y=0.16 vs chest half-width 0.112; tail root 16 cm behind the pelvis box) need the parent widened or a dedicated block (rump) covering the pivot; (2) oversized end-effectors keep their cube silhouette by bridging with a small hidden PLUG box rigid to the same bone (wrist plug into the paw, ankle plug into the foot slab) — two boxes on the SAME bone never move relative to each other, so they only need static intersection; (3) verify by rendering the EXTREME clips (climb_reach, swing, charge, mantle, bar_spin), not idle.
- **When reusing another character's armature, mesh parts built AT a bone's position inherit THAT character's proportions — a blocky head half as wide as the hero's left the ear discs floating 15 cm off the head** (the hero ear bones sit at y ±0.24..0.32 because the hero mesh was wide there). And you can't just slide the part inboard while keeping its bone weight: a part weighted to a bone but placed far from that bone's pivot TRANSLATES in an arc when the bone rotates (the idle ear-twitch would pop the disc ~4 cm sideways). Fix: attach the part to the volume it should ride (ears buried 1.5 cm into the head box sides) and weight it rigid to that PARENT bone (head), accepting the loss of the decor bone's micro-animation on this character.
- **Blender 5.1 `bmesh.ops.create_icosphere(subdivisions=N)` is +1-offset from the face count you expect: N=1→20 faces, 2→80, 3→320, 4→1280** (each step ×4, but the count starts at the base icosahedron for N=1, not N=0). Building a round head for a primitive character, `subdivisions=2` looked like it should be ~320 tris but gave 80 (a faceted lump); bumping 2→3 only added ~240 tris, not ~960 — the tri budget was quietly ~4× under target. Probe once (`for n in 1..4: create_icosphere(subdivisions=n)` and print `len(bm.faces)`) and pick N by the actual count, not the nominal "subdivisions". A flat-shaded (`use_smooth=False`) N=4 icosphere is the low-poly "chunky round" sweet spot for a cartoon head.
- **A whole roster of DISTINCT-silhouette characters (small/thin, tall/lanky, heavy) can be pure SKINS on ONE shared skeleton + ONE clip library — vary only the per-primitive mesh geometry, never the bone table.** Proven building a 4-character roster (Duke chimp, Chunk orangutan, Zip small/thin, Stretch tall/lanky) that all reuse `HERO_BONES` + the 30-clip shared library byte-identical (a SHA gate, `assert_shared_clip_identity`, hard-asserts it each rig build). The silhouette levers that keep clips + collider untouched: (1) **thin/heavy** = shrink/grow the limb prism cross-section radii and narrow/widen the torso box half-extents — keep every box CENTRE on the same pivot so the z-overlap chain (pelvis→spine→chest) never gaps; (2) **long limbs** = extend the EXTREMITY geometry (hand/foot) OUTWARD past the terminal bone as one rigid piece off that bone — the joint bend swings the whole long piece cleanly, no seam (the "long-armed reach" without a longer forearm bone); (3) **tall / small head** = build a thin NECK COLUMN + a shrunk head rigid on the HEAD bone (which on this rig already spans neck-base→crown), its lower end reaching down through the neck pivot for overlap — a bobble-on-a-long-neck read on a fixed skeleton; scale a head-feature CLUSTER toward one centre point (`c + (p-c)*k`) to shrink the whole face self-consistently. Because it's all rigid-per-primitive skinning, `bind_rigid_weights` gives 0 zero-weight verts and the clip signature is unchanged — so the ONLY per-character files are a per-character mesh+palette script and a ~90-line per-character rig script (writes its fur vmats, calls the shared rig library, exports FBX+vmdl). HeightScale stays 1.0; the collider is genuinely identical (characters-are-SKINS law).
- **The rig library's scripted-rig lane is PROJECT-PORTABLE — a new game gets rigged, clip-animated characters by copying `` verbatim + writing ONE per-character script, no engine-side re-authoring.** Proven by reproducing the lane in (a farmhand-style character, replacing a 5-part box puppet). The recipe: (1) copy the rig library module into the target project's `tools/` (it only imports bpy/os/heapq/math/mathutils — runs under Blender anywhere); (2) write `rig_<char>.py` = a biped landmark table (pelvis root; spine/chest/neck/head; 3-bone arms & legs; NO tail/ears) + a BLOCKY primitive mesh built AROUND the bone table (boxes/discs/icosphere, one primitive per bone, joint overlap per the ball-at-pivot rule) + `bind_rigid_weights` (KNOWN bone-per-primitive, so no geodesic inference) + hand-authored idle/walk/carry clips keyed by BONE NAME in armature space, then `finalize_interpolation` (the AUTO-handle + cyclic-freeze pass) → `export_fbx_set` → `write_vmdl(remaps=...)`. (3) Point the vmdl material remaps at the TARGET project's EXISTING flat vmats (: shirt/overalls/skin/straw/wooddark) so the rigged char reads identical to the box puppet it replaces — no new materials. SCALE lands for free: authoring in meters → FBX raw cm → the vmdl's ScaleAndMirror 0.3937 = the SAME 39.37 units/m as the project's static-prop `import_scale`, so a rigged char matches static-prop scale with zero extra tuning. VERIFIED end-to-end headless (Blender build clean, 0 zero-weight verts, 296 tris, well-formed vmdl); the in-engine COMPILE + gait LOOK are a separate owner-eyeball pass (this lane's vmdl schema is copied from the proven character rigs, so it is expected to compile). This is the SCRIPTED rig+clips proof; feeding downloaded mocap FBX into the same Poser lane (retarget_mixamo) is the next step.
- **To weld a HELD prop to a hand bone on a direct-sequence rig (no AnimGraph), READ the bone's live WORLD transform each frame and set the prop's `WorldTransform` from it — never SetBoneTransform.** `SkinnedModelRenderer.TryGetBoneTransform("hand_R", out var bone)` returns the bone's current world Transform (a pure READ — the SetBoneTransform WRITE path is unsound, see `g-rig-bone-procedural-override-setbonetransform-un`), then `prop.WorldTransform = bone.ToWorld( new Transform( gripOffset, gripAngles, gripScale ) )` welds the prop with a bone-local grip. Because you read the WORLD transform (not local), the prop inherits any whole-visual squash / flip / facing riding ABOVE the skinned renderer for FREE — no need to parent under the bone. Bone name in the COMPILED skeleton sanitizes '.'→'_' (`hand.R` → `hand_R`, same rule as the ragdoll physics-body names — `_phys_bone_name`), so query `hand_R` (fall back to `hand.R`). This is simpler than the proxy-prop workaround in `g-rig-skinnedmodelrenderer-setik-animgraph-gated` — that one is for grabbing a MOVING WORLD target (needs IK); a prop that just RIDES a bone only needs the bone-transform weld. COMPILE-VERIFIED (dotnet build resolves `TryGetBoneTransform(string,out Transform)` + `Transform.ToWorld(Transform)`); the in-engine attach + the exact grip offset/scale are PENDING owner verification (kept as `[Property]` for live trim).
- **Sequence-only rig (no AnimGraph): land hands on a moved prop by RE-SEATING the whole visual, never IK/bone-override.** When a clip already poses the hands in a grip, and the prop they grip moves/rescales, offset the rendered visual child (live ConVar dials the owner tunes in play, then bake) — `SetIk` needs AnimGraph params this rig lacks, and `SetBoneTransform` read-modify-write corrupts clip-keyed bones (the torso-spazz bug). Companion for swings: re-pivot the visual's rotation about the GRIP point (`pos' = grip + R·(pos − grip)`, grip distance self-derived from the tuned seat so the rest pose is unchanged) so planted hands stay planted through the arc instead of sweeping through the prop on a pelvis-centred arc. Owner-verified on the swing-rope knob grip.

- **A quadruped rig's docstring claiming "+Y steps the leg forward" is FALSE for every quadruped — verify leg-swing sign numerically against a built armature, not from the docstring.** Leg bones run DOWN (-Z) in rest, so +Y maps (0,0,-1)→(-sin,0,-cos): the tip swings REARWARD (the same +Y is correct for head/neck, where +X→-Z is nose-down — a leg-specific sign bug, not a bad pitch convention). Fix with ONE multiplier applied uniformly across thigh/shin/foot inside the leg-keying helper (not by hand-flipping authored numbers), and flip ALL THREE — flipping only thigh+foot inverts the recovery tuck (shin-forward/thigh-back). Diagnose from the render: a reversed-looking gait or a recovery leg splayed backward both point here.

- **Keying torso pitch per-bone as if each were an absolute pose COMPOUNDS down the chain — track a running total in the authoring comments, not just the per-bone number.** Armature-space rotations are relative to each bone's rest+parent, so pelvis+spine+chest+neck+head pitches all ADD: a lunge keyed 12/14/16/36/24° put the head 102° nose-down (into the dirt); reworked to 8/9/10/16/12° it lands at ~55°. For a LEVEL head through a moving spine, key the neck to CANCEL the accumulated torso pitch rather than adding on top. And a pose that reads "the animal drops/sinks" wants a root TRANSLATION (Z offset on the root location key), NOT a torso pitch — pitching the pelvis tips the whole animal nose-first.

- **Blender's WORKBENCH render engine ignores the world node tree — renders come back near-black unless the background is set via viewport shading (`scene.display.shading.background_type='VIEWPORT'` + explicit RGB), not `scene.world`.** So the usual EEVEE/Cycles world-node fix does nothing under WORKBENCH. Two neighbours when baking posed duplicates into one shared scene: (1) `object.copy()` carries `hide_render` across — reset `dup.hide_render=False` after copying a deliberately-hidden source or the copy stays hidden; (2) render helpers sharing one live scene contaminate each other — a hero shot rendered right after a clip-sheet render came back with the whole sheet still in frame; purge every object the helpers create (name-prefixed + any camera) at the start of each render pass.

- **A `SkinnedModelRenderer` created THIS FRAME has no attachment objects yet, and reading a bone before the first pose evaluates returns the BIND POSE — resolving a mount in `OnStart` silently gets nulls (`GetAttachmentObject` → null for every name) or T-pose transforms (`TryGetBoneTransform` succeeds but hands back rest geometry), with no exception either way.** Defer resolution and RETRY across frames with a timeout: try attachments first (the engine parents/drives them for free), fall back to bones, else settle on the model root and log the names tried. Once a mount lands on a BONE, re-pin its world transform in `OnPreRender` every frame (that callback runs after the pose evaluates). When seeding an offset relative to an un-inspected rig, never hard-code a bone-LOCAL offset — seed via the character's frame (`WorldPosition = mount.WorldPosition + characterRotation * seedOffset`), then read the resulting `LocalPosition`/`LocalRotation` back as the authored baseline. → [fix article](/fix/attachment-bone-resolve-frame-timing)

- **Direct citizen sequence playback needs no AnimGraph — but `SkinnedModelRenderer.UseAnimGraph` must be set `false` BEFORE the first `Sequence.Name` write, or the write silently no-ops** (the model's own animgraph keeps driving the pose; no error). Order: `renderer.UseAnimGraph = false;` first, then `renderer.Sequence.Name = "Walk_N";`. The compiled citizen model exposes 466 sequences (raw directional `Walk_/Run_/Sprint_*`, `IdlePose_*`) — a full movement set with no rig work; `Sequence.Blending=true` still layers cross-fades. Probe the full catalog with `renderer.Sequence.SequenceNames` off a LIVE renderer from a `[ConCmd]`. → [fix article](/fix/direct-sequence-playback-needs-useanimgraph-off-first)

- **The citizen ragdoll physics rig is countable OFFLINE (plain KV3 text, no editor), and the real numbers beat the folk estimate.** `citizen_physicsshapelist.vmdl_prefab` = 18 shapes (17 capsules + 1 cylinder); `citizen_physicsjointlist.vmdl_prefab` = 16 joints (12 `PhysicsJointConical` ballsockets + 4 `PhysicsJointRevolute` hinges). Common guesses land ~9-13 bodies, roughly half the real 18 — undercounting per-body sim and joint-solve cost. Use 18 bodies / 16 joints as the reference for ragdoll density/perf budgets, not an estimate.

- **The citizen's locomotion clips each carry their OWN authored ground speed in the animgraph's `m_blendValue` coordinates — pacing every clip's `PlaybackRate` against one guessed nominal speed foot-slides every variant except the one it was tuned for.** Measured blend-value speeds: `Walk_N` 49 u/s, `WalkFast_N` 74.5, `Walk2X_N` 151, `Run_N` 177 (`Walk2X_N` is the same source fbx as `WalkFast_N` at a different bake framerate: 74.5×73/36 ≈ 151). Read the blend value per clip and pace against THAT, not one shared speed. Also: the stock citizen ships NO civilian/idle-activity clips (no phone-check, look-around, talk) — only eleven `IdlePose_*` variants plus locomotion and a few prop-hold poses; idle-NPC variety must come from POSE + FACING + DURATION + a held prop, not a clip catalog that doesn't exist on this model.

- **A bone write through `SceneModel.SetBoneOverride` (`SkinnedModelRenderer.SetBoneTransform` routes here) PERSISTS until explicitly cleared** — not reset by the next frame, a new sequence, or switching which write method you pose with. Comparing two write methods back-to-back without a `SceneModel.ClearBoneOverrides` between them compares the first method to ITSELF (the second channel reads the first's leftovers still sitting on the bones). `ClearBoneOverrides` is coarse — it drops EVERY override on the model at once, not a scoped subset.

- **The citizen skeleton carries procedural helper bones (an `AnimConstraint` layer, clavicle/collarbone among them) that MOVE when a clip plays but do NOT move under a live per-bone override write — so comparing a pose across the two paths reads as a bug in the wrong joint.** A live `SceneModel.SetBoneOverride` pose writes only the bones you touch and reports the helper's own delta as zero; a compiled clip lets the rig's constraint solver keep moving the helper underneath. On a shoulder-raise, elbow and wrist round-trip within a tenth of a degree between the two paths while the helper legitimately diverges — account for the constraint layer before blaming a joint.

- **`SceneModel.GetParentSpaceBone` ALWAYS returns the REST (bind) pose — it does not move when a clip plays or a sequence advances.** Right for a rest baseline (an authored pose or a delta-from-rest computation can lean on it), wrong for any live readback: read a currently-playing pose through it and every clip measures as motionless. For the current animated transform read `SceneModel.GetBoneWorldTransform` (the FINAL transform, including any override) or `SceneModel.GetWorldSpaceAnimationTransform` (post-animation, before overrides).

- **A `SkinnedModelRenderer`/`SceneModel` must be given its MODEL before an animation-graph switch (e.g. `UseAnimGraph`) is set on it — set the switch first and the write silently never takes** (the setter forwards to the underlying `SceneModel`; with no model assigned there is nothing to forward to). Tell-tale: the managed property reads back `false` no matter what you set; `Sequence.Name`/`Sequence.Duration` read back CORRECT (they come from the model itself, not playback, so the rig looks healthy); `Sequence.Time` never leaves `0.000` while the body visibly stands still. Assign `Model` first, then the switch, then the sequence.

- **You cannot TOW a ragdoll by driving the light peripheral body a grip fiction points at: a servo on a hand (or any single limb extremity) pulls against a chain of COMPLIANT joints that exist precisely so the ragdoll can crumple, and the chain absorbs the pull instead of transmitting it.** No stiffness/speed/break-distance dial fixes this — the physics is correct; the joints are doing exactly the compliant thing they were authored to do. On a citizen-scale rig, driving a hand body toward a tow target left the hand tracking the target perfectly while the rest of the ragdoll barely moved, the arm stretching through three compliant joints. Drive the HEAVIEST body (pelvis/torso), not the grip limb, when you need the whole ragdoll to follow.

- **The engine's built-in two-bone IK (`SkinnedModelRenderer.SetIk`, animgraph-gated) reaches a hand target correctly but CANNOT steer the elbow — it takes no pole/hint input at all.** Confirmed on the citizen at source: `citizen.vanmgrph` has zero pole/elbow/knee/hint/twist parameters, so the elbow lands wherever the underlying clip puts it, never where the caller wants. For controllable posing (a posing kit, a reach that has to clear geometry, an elbow that must read a specific direction to camera) a hand-written two-bone solve with an explicit pole vector is required.

- **An `AnimFile` whose `name` contains a HYPHEN does not reach the compiled model, and nothing says so.** The fbx bakes, the animation list is written, the vmdl compiles green with zero errors and zero warnings, and the sequence is simply absent. Proved by baking one clip twice from the same source changing only the name: `phone_look_probe` played for 0.63 s and `phone-look` reported 0.00 s; renaming that entry to a hyphen-free word while leaving `source_filename = phone-look.fbx` untouched brought the same fbx back to life. Underscores and digits are fine. Any pipeline that lets a person type a name and hands that string to the model compiler needs the hyphen removed at the ONE point the typed name becomes a stored one: the name is usually also a filename, and filesystem-safe is a weaker rule than compiler-safe.

- **The `SkinnedModelRenderer.Sequence.Name` setter accepts and echoes back a name the model does not have, so the obvious guard against a missing sequence cannot fail.** Assigning `definitely_not_a_sequence` reads back unchanged, reports `Sequence.Duration` of 0.00, and leaves a motionless body in the default pose, which reads as "playback is broken" rather than "that clip is not here". Check membership in `Sequence.SequenceNames` BEFORE assigning, and print that list when the name is not on it.

- **A vmdl `AnimFile` node has NO import-rotation field, so an import-frame error on a RIGGED asset cannot be corrected at the node level: put the degrees on the mesh node and the geometry turns while every clip keeps driving the bones on the old axis.** It is worse than the static case because the REST POSE photographs perfectly, so the parts only travel along the wrong axis while a clip plays and the first evidence says the fix worked. Correct the geometry in the FILE, and for a rigged asset rotate the mesh data AND the armature rest pose by the SAME matrix, leaving the pose curves alone (pose channels are bone-local, so every authored key keeps its number and meaning). Transform the DATABLOCKS (`Armature.transform(m)` and `Mesh.transform(m)`), never the armature OBJECT, or a parented child is double-counted. Spell the matrix with entries of 0 and plus or minus 1 rather than building it from an angle (an angle carries about 6e-17 of dust that fails a byte-identical rebuild gate), and do the rotation LATE, after everything that reads the authoring frame. Prove a rigged correction on the shipped bytes (vertex-array bounds and every bone rest head against the source permuted), not on the builder's own sidecar.

- **The citizen graph's BODY AIM is driven by `SetLookDirection( "aim_body", dir, weight )`, NOT by the `aim_body_pitch` / `aim_body_yaw` floats: writing only the floats reads back perfectly and moves nothing.** `CitizenAnimationHelper.AimAngle` localises a rotation and writes exactly those two floats, so copying the helper looks complete, but the same file also feeds `SetLookDirection( "aim_head" | "aim_body" | "aim_eyes", dir, weight )` and THAT is what the graph consumes. Measured: the renderer read back `aim_body_pitch` of -39.4 with weight 1.00 while the held gun swung 0.0 degrees between a target above and below; adding the three `SetLookDirection` calls moved the gun 75.8 degrees. Keep the floats too, since they are the only part a test can assert a WRITE on. Corollary: a `Set`/`GetFloat` pair on a `SkinnedModelRenderer` is a dictionary that holds any name whether or not the graph declares one, so a readback proves the write and proves nothing about the effect. Pair it with a PHYSICAL assertion that needs no art numbers: stage the character against two opposite inputs, sample the held model world forward in each, and grade the angle between the samples.

- **`SetBoneTransform` takes an OBJECT-RELATIVE transform, not world; `SceneModel.SetBoneWorldTransform` takes world, and on a graph-driven rig a partial-bone write through `SetBoneWorldTransform` is a SILENT NO-OP.** With the animation graph running, writing a subset of bones (a hand's finger chain, not the whole skeleton) through `SetBoneWorldTransform` stores the value, `TryGetBoneTransform` reads it back exact (gap 0.0000, same frame), and it never reaches the skinned mesh, so a twenty-unit displacement photographs identical to no write at all. Feed `SetBoneTransform` the object-relative transform (`renderer.WorldTransform.ToLocal(world)`) and the pose reaches the render. Every readback agrees the write worked, so only a rendered frame separates a call that draws from one that does not; a battery built on transform readbacks alone passes a pose feature that draws nothing. See `g-rig-bone-procedural-override-setbonetransform-un`. -> [fix article](/fix/setbonetransform-silently-noop)
