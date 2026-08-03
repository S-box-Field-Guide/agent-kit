# Writing gameplay — world gen & terrain

> Topic sub-file of this lane — router: `writing-gameplay.md` (its "Where everything lives"
> table maps every topic). Load `_core.md` first. Bullets below are moved verbatim
> from the lane pack; the sync appends new bullets for these topics here.

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

- Runtime meshes: `Mesh` + `Model.Builder.AddMesh.AddCollisionMesh`; if winding is
 ambiguous (Clipper2 + earcut), emit triangles double-sided. Yield with
 `await GameTask.Yield` every N items to keep loading screens alive.

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

- **`wb_generate` leaves a transient `wb_world` terrain GameObject in the open scene — it
 is a STEP-TERRACED diorama, so props spawned for a clean side-by-side verification land
 on it at random heights (float/sink), not on your own flat floor.** Before a prop-audit
 loop, `set_game_object {enabled:false}` on `wb_world` (don't delete — it's session-
 transient and regenerated), spawn your own flat floor (a scaled `box.vmdl`), do the
 shots, then re-enable it to leave the editor as found. Also note `find_game_objects`
 returns `{"Total":N,"Results":[…]}` (objects under `Results`, each with `Id`/`Name`),
 NOT a bare list — and its `name` filter is a substring, so a `"wb_"` query also matches
 `wb_world`; filter by exact prefix before deleting so you don't nuke the terrain root.

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

- **Collision-fidelity study (the project default 960²): halving CollisionBlockCells 4→2 (0.8→0.4 m blocks) =
 EXACTLY 4× collision tris (115 200 → 460 800 world-wide), NEGLIGIBLE regen delta (2095 vs 2132 ms), render
 unchanged.** 461k is still << the 2 M budget and < 754k render tris, so collision cost is not the blocker;
 the blocker is that the whole step/slide dial set (StepUpMax 0.9 m etc.) is sized to the 0.8 m block, so a
 finer collision pass must re-tune + re-validate. Kept 4 as default; the switch is one Tuning const.

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

- **Absolute-altitude biome thresholds break when height amplitude changes.** Scale every climate
  altitude by `max(amp, refAmp)/refAmp`; clamp k >= 1 to prevent snow-on-mesa fraction bugs;
  leave sea-relative dials unscaled.

- **The AddWater brush is spill-guarded: it refuses to place water on open/flat/sloped ground** (it early-returns when the pond surface would sit at/below the disc's lowest cell — i.e. when the lowest DRY rim just outside the disc isn't higher than the basin floor). So on a drained terraced world an `add_water` stroke almost always touches ZERO cells — a scripted regression case built on it is a silent no-op (audits "pass" trivially). To script a real pond: dig a bowl FIRST (`lower` a few reps), THEN `add_water` into it; and always assert `cellsTouched > 0` before trusting an audit-clean result. Reliable brush water-invariant failures instead come from `remove_water` on a below-sea (ocean) cell and from `lower`-ing a dry bank next to an above-sea lake.

- **A hold-to-paint terrain brush that aims with a physics ray degrades to click-click-click, because the ray traces the very chunk colliders each application rebuilds.** A dirty-chunk remesh swaps each touched chunk's `ModelCollider.Model` (`col.Model = newModel`), which rebuilds that collider's physics body; for the frame(s) the body is rebuilding a `Scene.Trace.Ray` against that chunk intermittently returns `!Hit`. If the brush's no-hit branch hides the cursor and resets the apply cooldown, a continuous LMB hold keeps missing over the spot it's editing and the stroke is dropped — so the user has to click repeatedly instead of holding. Root-caused by the source chain (aim trace → the same colliders RemeshChunks rebuilds), not by "input lag". Fix: aim by marching the camera ray against the GRID heightfield (pure, read-only, deterministic, no physics) instead of tracing colliders — immune to the rebuild window AND to edit-mode collider blindness, and it never touches the grid/hash. General rule: never point-query the physics representation you are actively rebuilding on the same frames; query the source data (heightfield/grid) instead.

- **Any LINEAR projection gradient over a map (dot the position onto a direction, smoothstep the result) produces dead-straight iso-lines — a region boundary driven by it reads as an artificial diagonal seam at every seed.** M9.5c r4 (owner screenshot, the desert edge): fix by DOMAIN-WARPING the scalar projection before the smoothstep — proj += lowFreqFBM(x, y, freshSalt) · halfWidth · warpAmp (warpAmp ≈ 0.35 of the half-width, wavelength ≈ 0.6× the map so the seam bows in 1-2 broad lobes, not wiggle noise). The region stays coherent (it is still one monotone-ish gradient), the boundary meanders organically, and the field stays a pure fn of (spec, x, y) so downstream passes recompute it identically. Mint a FRESH salt for the warp field — reusing the direction-pick salt correlates the warp with the pole choice.

- **A one-click world-class preset that parks a climate slider at/near its extreme produces a degenerate single-biome world ('s Alpine Snow at Temperature 0.12 → ~94% white; the owner: "just looks stupid") — and warm material families leak through feature overrides (river beds / beach rings painted warm tan THROUGH snowfields).** Fix pattern: presets land INSIDE the expressive range (the snow line above the lowest valleys → snow-dominant massif + green valley pockets), extremes stay reachable via the slider itself; gate material FAMILIES on the same dimensionless climate axis the biome bands use (own-ground tEff ≤ rock-line constant ⇒ river beds/beaches paint an earth/stone family, never sand — a strict no-op in warm worlds since the constant is exactly the rock-line altitude there); and pin the class with a numeric biome-census assertion in the suite (snow band + green floor + desert==0) so the class can't silently drift.

- **A graph-reachability audit ("does this cell's flood reach any target-set cell?") that checks `targetSet.Contains(start)` ONCE at the top, then floods neighbours WITHOUT ever testing the discovered nodes against the target set, ALWAYS returns false unless the start node itself is in the set.** In 's `town_road_access` audit the BFS enqueued Road neighbours but the `Visit` closure never called `centerline.Contains(neighbour)` — so it reported "Road BFS never reaches segment centerline" for 100% of buildings even where the spur plainly connected (the door's touch cell is never itself an exact A* centerline cell). Fix: test membership as each node is DISCOVERED (`if (targetSet.Contains(n)) return true;` inside the visit, plus the start-cell short-circuit). Classic "BFS that explores but forgets to check the goal" — the reachable-set test must run on every visited node, not just the seed.

- **A pad/lot placement validator that rejects "water/river/already-developed" cells but silently omits ONE conflicting flag (roads) lets development stamp ON TOP of that feature — invisible until an audit is finally wired.** 's `TownPass.ValidateRect` rejected water/river/lot but not `Road`, so in road-dense worlds a lot core stamped `Lot` over a *crossing* main road → 165 `town_flag_semantics` offenders (`Road|Lot` outside a spur throat) the moment the audits were connected. The lot's OWN road is cleared by the setback (>=1 m gap here), so a `if (AnyRoad(core)) reject` gate catches only the crossing-road overlap and never a valid lot. Lesson: when a placement pass has an exclusion list, it must name EVERY flag that is semantically incompatible with the thing being stamped — and wiring the audit is what surfaces the omission (a pre-existing latent bug, not a regression). Beware: on a *marginal* seed the added gate can drop placement to zero (measured evidence the world was only "placeable" by violating the rule) — root-cause and report, don't relax the gate.

- **A -generated world is NOT car-drivable un-tuned, and the MESHER STYLE decides it — pick HeightfieldMesher (LowPoly/Smooth), never VoxelMesher.** Vendoring the vp raycast-wheel car onto a WB `WorldGen.BuildGrid` + `VoxelMesher.BuildChunks` terrain ( B1): collision/units/spawn/determinism all worked first try (wheel down-shapecast hits the per-chunk `ModelCollider`s, 4/4 grounded, `Tuning.M` == vp `Units.MetersToUnits` == 39.37 so no scale mismatch, spawn-at-equilibrium settles clean, same seed → identical `WorldHash`). BUT the car is blocked within metres in every default config: (1) **Voxel style is terraced** — 0.25 m quantized steps with vertical faces stop a car at the first riser (grounded=4/4 but wall-blocked). (2) Even **LowPoly heightfield emits deliberate near-vertical "wall blocks"** for mesas/cliffs (it was authored for a CLIMBING game) — the body box stops against them. (3) **Rivers/roads carve banks** that wall the car in. Only a near-flat preset (amplitude ≤ ~3 m, `Rivers=0`, `Plateau=0`) gave a clean high-speed cross-chunk traverse (~40 m at 57 km/h across ~6 chunk boundaries, no hitch, 225 chunks meshed in ~470 ms). Takeaway for a driving game consuming WB: use `HeightfieldMesher.BuildChunks(..., smooth:false)` for LowPoly, and build a **drivable generation preset** (low amplitude + cliff suppression / slope ramping) — the raw WB world needs it before free-roam driving is fun. Blockout BOX colliders also catch on undulations; fitted kit/model colliders do better. ( B1, docs/b1-verdict.md)

- **A generation parameter denominated in CELLS silently changes its PHYSICAL size when the voxel grain (CellSize) changes — so the "same seed" reads as a differently-PROPORTIONED world at a finer grain, not a finer version of the same world.** A river carved "N cells wide" is half as wide in metres at 0.1 m grain as at 0.2 m; the fix (owner directive "meters, not cells"): author every LOOK length (channel/road width, bank/shoulder feather, ramp/maturity distance, shore-band and blend-ring radii) in METRES and derive cells at the USE SITE via `metres / grid.CellSize` (fractional widths) or `ceil(metres / grid.CellSize)` (integer radii). LEAVE genuinely grain-invariant things alone: slopes already computed as rise_m/run_m (`Δh / (2·cs)`), cone/decay fields that multiply by `cs` to become per-metre, wavelength multipliers of a metre TerrainScale, quantized STEP-delta thresholds (step-native — correct under step coupling), and fraction-of-cell placement (grain-invariant at a fixed extent). Audit the CODE, not a remembered checklist: several "expected" offenders (cell-count basin-area thresholds, cell adjacency thresholds in the audits) did not exist — those were already metres/step-native.

- **Converting a cell-denominated constant to metres CAN be byte-identical at the reference grain, but you must verify per-constant and keep the downstream cell-expression structurally unchanged.** If the grid hash folds QUANTIZED integer arrays (steps/material/…, as 's does), a sub-step float epsilon usually doesn't move the hash — but a comparison boundary (`d <= halfW` with d an exact `sqrt(int)`) will flip a cell if the derived width drifts by a ULP. Two things make it exact: (1) author the metre literal as `oldCells × referenceGrain` (e.g. 2 cells @ 0.2 m = `0.4f`); float32 `0.4f / 0.2f == 2.0f` EXACTLY — but DON'T assume, a struct-pack round-trip test is one minute and caught that my hand-arithmetic (0.3/0.2) was wrong (it IS exact). (2) Convert EACH constant to cells individually, then feed the original cell-space expression — e.g. keep `start + (end-start)·t` with `start = StartM/cs`, `end = EndM/cs` — instead of computing the ramp in metres then dividing; reordered float ops round differently and can drift a boundary the per-constant test wouldn't catch. Result: default 960²@0.2 m grid hash byte-identical before/after the whole audit.

- **To make a spec field's DEFAULT track another field (e.g. couple StepHeight to CellSize) without breaking existing saved specs/goldens that set it explicitly, use a SENTINEL default + resolve in the one validation choke point — never just change the literal default.** A plain `= 0.25f` default can't tell "unset" from "explicitly 0.25", so a coupled default would either be ignored or would silently rewrite specs that meant 0.25. Instead default the field to a sentinel (a NEGATIVE value, so an accidental 0 also derives instead of dividing by zero downstream) and, in the record's `TryNormalize`/validation boundary that every entry point already funnels through, resolve `field > 0 ? field : Derive(otherField)`. This is append-only (no new member — the Editor-tools contract holds), honours an explicit value untouched (slider override, saved spec, the test harness DEFAULT_SPEC that pins it), and is byte-identical at the reference grain because the derived value equals the old literal there (1.25 × 0.2 == 0.25 exactly). One display wrinkle: any UI that reads the field back into a draft slider must resolve the sentinel too, or it shows the raw sentinel on first boot.

- **A symmetric pairwise slope-relaxation pass ("move both cells half the excess") only reduces steep faces ASYMPTOTICALLY — after 64 iterations a carved ridge still carried a residual super-grade face that hard-stopped the car; a Lipschitz LOWER-ENVELOPE min-cap gives a HARD guarantee.** The working construction ( DrivablePass): repeat { forward+backward sweep each row capping h[i] <= h[i-1]+maxDelta, then each column } until a fixpoint. On convergence EVERY 4-neighbour edge satisfies |dh| <= maxGrade x CellSize by construction — erosion-only (cliff tops cut into ramps, drivable hills untouched), deterministic (fixed order, no RNG, byte-identical WorldHash across regens), a handful of rounds to converge at 1024^2. Two companion facts measured the same session: (1) a slope cap does NOT fix crest high-centering — the cap bounds gradient, not CURVATURE, and a long chassis beaches on a sharp in-grade crest, so pair it with a few box-blur passes BEFORE the cap; (2) collision-block quantization must be sized to the vehicle: the block-max staircase (0.8 m blocks at 0.25 m steps) exceeded the pickup's 0.22 m ground clearance, high-centring it on terrain whose render mesh looked (and was) in-grade — StepHeight 0.125 m + CollisionBlockCells 2 put the risers under clearance. ( B3 DrivablePass + drivable preset, 2026-07-13)

- **A grid-derived feature placer with a min-width cull silently drops every DIAGONAL feature edge — the majority of natural terrain.** A cliff edge that runs diagonally across the collision block grid decomposes into single-block faces (each qualifying on height, each 1 block wide), so a "≥ 2 blocks wide" accident-filter culls them ALL: ' cliff-climb pass accepted only 1652 of 7077 qualifying faces (77% culled), leaving most real cliff surface with no climb lattice exactly at corners and stair-stepped edges — which is where players run into walls. Fix pattern: accept a single-block face when the SAME-direction edge continues diagonally beside it ((a±1, run∓1) qualifying face — a stair step of a longer edge), keep culling isolated slivers. Determinism ripple control: emit the new patches into a SEPARATE list with its OWN placement hash so the original list/count/hash stay byte-identical and every downstream consumer (aerial net, seed scorer, pilot leg picks, MP probes) is provably unchanged — declare only the new hash.

- **A single thin `Model.Builder.AddCollisionMesh` triangle SHELL over a curved ramp acts as a WALL to shapecast/raycast wheels on a SHORT-STEEP kicker at speed -- the car stops dead instead of launching.** vp playground: a small curved kicker (0.6 m rise / 3 m run, ~22 deg lip) whose render AND collision came from one closed mesh via `AddCollisionMesh` stopped a full-speed car cold (owner: "it acted like a wall"). A thin CONCAVE triangle shell gives the downward wheel shapecast an unreliable hit and there is no solid volume beneath, so the chassis belly catches the ramp face; the failure is scale-dependent (a long/gentle ramp of the same build rides fine, a short/steep one walls). FIX (drive-verified): keep the visual mesh, but build COLLISION as a stack of solid convex TANGENT BOXES -- one `BoxCollider` per arc segment on a child GameObject pitched to the local slope (`Rotation.FromPitch(-slopeDeg)`), its top face on the segment chord, body buried ~1.5 m below grade so overlapping neighbours form one gapless solid. Convex primitives are never hull/AABB-simplified, give the shapecast a clean solid the whole way up, and the base segment reads a genuine ~0 deg tangent. After the swap a small 0.6 m and a big 6 m kicker both launch at full speed (0.60 / 2.40 s airtime, measured via the jump maneuver). Note the wheel trace is a SPHERE-cast (`Scene.Trace.Radius(1)`), which the convex boxes suit far better than a concave mesh. **SUPERSEDED IN PART (2026-07-21, engine 26.07.22, live A/B, four days after the fix above): the "stack of overlapping tangent boxes" recommendation is now proven UNSAFE for driveable surfaces at speed and must not be used as the default fix.** Chained/overlapping convex box primitives create buried INTERNAL faces that the engine's speculative narrowphase clamps integration against without ever raising a touching manifold: per-tick displacement on the face measured 11-31% of velocity*dt while `Rigidbody.Velocity` stayed perfectly smooth and NO collision event fired on any collider — an event-silent stutter locked to the segment pitch, easily misread as a rendering/interpolation bug rather than a physics one (a collision-event probe cannot falsify it; only a per-tick integration audit can). A controlled A/B settled it: the identical arc built as one closed `AddCollisionMesh` solid integrated at a clean 1.00 ratio versus 0.31 for the box chain. NEW RULE: build driveable curved-surface collision as ONE closed/solid collision mesh (or otherwise strictly non-overlapping primitives) — never a chain of overlapping convex boxes — even though boxes do solve the WALL failure this entry originally documented. If a closed mesh still walls a short-steep face the way the thin shell above did, the fix is giving that mesh real sealed volume (or a coarser tangent geometry), not reaching for overlapping box primitives; internal faces near a drive surface are a solver hazard even when nothing can geometrically touch them.

- **A dirty-chunk remesh system's dirty-marking encodes ONE specific read footprint — adding a second mesher whose reads reach FURTHER silently breaks the contract (stale geometry/lighting at seams the original mesher would never produce).** 's M8 `MarkDirtyChunks` dirties the neighbour chunk only for BORDER cells, because the voxel mesher's widest cross-seam read is 1 cell (skirts sample `GetStep(gx±1)`). The M9.9 Smooth heightfield mesher reads deeper: a border VERTEX's smoothed normal central-differences the corner lattice ±decimation cells across the seam (cells 2-3 in from the border at decimation 2) — so a brush stroke near-but-not-on a border would rebuild only its own chunk and leave the neighbour's border normals stale (a lighting seam; caught in code review before it shipped). Fix pattern: either re-derive the dirty footprint per mesher, or (cheap + robust) dilate the dirty set by one chunk ring for the deep-reading style before remeshing — a few extra small chunk rebuilds beat a visible seam. Rule: when adding a mesher/generator to an incremental-rebuild system, audit its WIDEST read distance against what the dirty-marking guarantees, not just whether it "reads the grid".

- **A decimated heightfield mesher renders carved cliffs as alternating sawtooth teeth, and the "obvious" fixes (consistent diagonals, majority-vote corner snap) leave the crest serrated.** Root cause is TWO stacked artifacts, and only probing the real numbers separated them: (1) mid-wall: the smaller-delta diagonal rule flips orientation block-to-block when both diagonals carry similar (huge) deltas — force ONE diagonal on wall-relief blocks; (2) crest: the cliff LINE runs diagonally through the cell lattice, so the mixed 4-cell corner column drifts ~1 cell every 2-3 rows and corner AVERAGING smears a 45-degree ramp along several block rows of crest — the sawtooth fringe. A MAJORITY-vote cluster snap does NOT fix it: on a 1-2 cell wide carved wall the transition cells carry intermediate heights, so mixed corners are mostly 2-2 splits (majority never fires) and where it fires it snaps in ALTERNATING directions. The working rule: sort the 4 samples, find the largest gap; if it exceeds wallSlope x cellSpan, take the mean of the cluster ABOVE the gap — a UNIFORM plateau bias (<=1 cell dilation, matches the voxel style's plateau-first silhouette) that keeps the lip polyline level; blend the snap in over [gap, 2x gap] so near-threshold graded ramps can't flicker between snapped and averaged corners. Corollary: the snap is for FACETED styles only — on a smooth-shaded mesh the residual cluster wobble on graded ramps punches a NEW grazing-angle sawtooth into the skyline, so thread a per-style flag instead of sharing the rule.

- **A top-down (plan-projected) terrain color texture stretches ONE texel row over the whole height of a near-vertical wall — cliffs render as smeared vertical streaks.** Mesh-only fix without shader work: route wall-steep blocks into a second mesh on the SAME base material, with UV.v mapping raw world-Z into a small per-chunk altitude->strata gradient texture (Texture.Create -> Update, Material.CreateCopy + Set("Color", tex) — the proven per-chunk blend-texture path). Bake the gradient from the chunk's cliff-wall cells (the cells the strata classifier already bands LEVEL by altitude), bucketed one texel per step on the GLOBAL step lattice so bands align across chunk seams. TRAP (the hard-halo failure): if the gradient samples only wall cells, the cliff/top material boundary — which zigzags per block along every diagonal crest — reads as a sawtooth of contrast triangles at the lip; include the wall cells' 1-ring FLANK neighbours in the bake so the gradient's end buckets average toward the surrounding ground colors and the join loses contrast. Duplicate the shared lattice positions AND normals verbatim for the second mesh so the join can't crack or shade-seam.

- **`Mesh.CreateIndexBuffer` throws `ArgumentException: Index buffer size can't be zero` — and partitioning triangles across two meshes makes the empty case REACHABLE where it wasn't before.** A shared-vertex chunk mesher always has vertices (the lattice), so `vertices.Count > 0` used to imply triangles; after routing a subset of blocks to a second mesh, a chunk whose EVERY block routes away still has a full vertex lattice but zero indices. Gate each mesh on its INDEX count, not its vertex count.

- **A per-generation static registry must be CLEARED at the start of EVERY generation, not only for the code paths that populate it.** Symptom: a mesh-boundary audit that reads a static capture map reported thousands of phantom offenders for the Voxel style — but only AFTER a Smooth generation ran first. Cause: the capture map was cleared+filled only on the heightfield path; the Voxel path skipped the clear, so the audit read the PREVIOUS (heightfield) run's boundary data. Fix: always call the `Begin` that clears the static, unconditionally, before the style dispatch — the populate step stays gated, the clear does not. General rule for process-global state surviving the editor→play boundary: reset on ENTRY to the producer, never rely on the consumer's path to have reset it.

- **A grid-only "seam" audit that re-derives lattice coordinates can never see a real emitted-geometry crack** — it's algebra over the grid, always clean by construction, so it gives false confidence. To actually catch a mesher indexing/decimation regression you need a check that inspects EMITTED vertices. Key asymmetry when you build it: the continuous-heightfield meshers emit the SAME shared boundary corner vertex on both sides of a seam (compare heights AND per-vertex normals for equality — a mismatch is a crack / shade-seam), but a GREEDY voxel mesher emits COMPLEMENTARY skirt walls (only the higher chunk walls the seam, spanning down to the neighbour's top) — so adjacent voxel tops are NOT equal at a seam by design and a naive equality check flags every step. Split it: keep the cheap lattice invariant for all styles, run the emitted-boundary equality check only for the heightfield styles.

- **When deriving procedural climb lattices (or any character-facing geometry) from a voxel world, sample the COARSE COLLISION heightfield, NOT the render mesh.** wb terrain carries two surfaces: render (0.2 m cells, 0.25 m steps, per-cell skirt quads) and collision (a per-block heightfield, `.CollisionBlockCells`=4 → 0.8 m blocks, each at the block's MAX cell height — the reduction `VoxelMesher.BuildCollision` uses). The character's traces, node standoff and body clearance all interact with the COLLISION surface, so a lattice built from the pretty render skirts floats up to ~0.6 m off the real face (block-max vs per-cell height) and nodes fail the 5 cm surface audit. Build the cliff-face algorithm entirely from a `BlockMaxStep(bx,by)` reduction (max `GetStep` over the 4×4 cell block — byte-identical to BuildCollision), never `GetStep` of a single render cell. VERIFIED LIVE ( M5, seed 42, engine 26.07.08e): 30 auto-placed planar `ClimbNodeField`s, analytic audit `worstPerp=3.0cm` (exactly the movement-tuning `NodeProud`, i.e. grips sit dead on the collision plane) and `worstBand=0.0cm` (every node inside the re-derived block-max vertical band) → 0 violations. The audit itself must re-walk the block-max field analytically (no raycasts), which is also what makes it independent proof the lattice is collision-derived. Companion law (mantle-cap-overhang): only accept a wall whose block ONE step behind the lip is walkable and not higher than the top (no auto-placed lattice whose top node sits under a lip).

- **Rebuilding a MULTI-MATERIAL compiled part from `GetVertices`/`GetIndices` and applying `Materials[0]` paints the WHOLE part that first material — which renders BLACK when the first `usemtl` is a dark colour.** A compiled OBJ with N `usemtl` groups is ONE mesh (`Model.MeshCount == 1`) carrying N materials; `GetVertices/GetIndices` flatten it, so the naive single-material rebuild (`new Mesh(model.Materials[0])`) recolours everything. In the pickup `cab`/`bed` and every kit `chassis_shell` list `trim` (0.17,0.18,0.21 — near-black) as their FIRST usemtl, so a dented part rendered solid black on the owner's screen. **The fix — a true per-submesh rebuild — is available because the flattened index buffer is GROUPED INTO PER-MATERIAL DRAW-RANGES IN `Model.Materials` ORDER, which equals the OBJ `usemtl` DECLARATION ORDER** (PROVEN 2026-07-13: a probe split the flattened `cab` indices by offline per-usemtl counts [324,504,72,36,84] and each range's referenced-vertex Z-centroid was material-coherent — glass verts high z≈60, chrome low z≈13, body mid z≈42 — i.e. contiguous, non-interleaved ranges). So: emit per-part `submesh_index_counts` in the manifest (usemtl order), split the flattened `GetIndices` into contiguous ranges, and build ONE `Mesh` per range with `Materials[k]` (share the deformed vertex buffer; `Model.Builder.AddMesh` each). Guard hard — counts must sum to the flattened index length and be ≤ `Materials.Length`, else fall back to single-material — so a stale manifest can't emit garbage. Two more facts: `Material.Name`/`.ResourcePath` return the vmat path (e.g. `.../materials/body_red.vmat`), so a never-black FALLBACK is `Materials.First(m => m.Name.Contains("/body_"))`; and `Model.MeshInfo`/`ModelMeshInfo` (the per-drawcall API that would give ranges directly) is undocumented with no whitelist precedent — the manifest-counts route sidesteps it entirely.

- **To make gen pass B cull against pass A's output when B runs BEFORE A, both must read a PURE grid-derived field — B cannot read A's placed list (it's still empty).** builds the aerial swing net BEFORE the tree scatter (trees zone off the net's routed lane), so an owner ask to "cull the net where trees are dense" could not read `TreePass.Placed` at aerial-build time (0 entries). Fix: a pure `AnchorFieldM(grid, spec, seed, offset)` that re-runs the tree pass's deterministic placement FILTERS (on-land + flat + min-spacing) over a LOCAL list — same positions the later Build will place, minus any post-placement zoning — computed from the grid alone, so the net culls against it and host/client derive it identically (MP-safe). Reusing the placed list would have silently culled nothing. Keep it read-only of the shared statics so it doesn't perturb the real placement (the actual pass hash must stay byte-identical). SECOND trap when you get there: a per-cell "≥N neighbours within R" density threshold over a MIN-SPACED (near-regular) scatter is RAZOR-SHARP, not gradual — on a ~20 m-spaced island forest, R=20 m gave ~5 trees at the mean, so N=3 culled 99.6% (net vanished) and N=8 culled ~0; only N=6 (just above the LOCAL-island mean, not the whole-grid mean — trees concentrate on the land hull, not the water) split it ~59/41. Sweep it live against the real seed with a temp convar; don't guess from grid area.

- ****Generated terrain that has real relief still reads DEAD-FLAT from the gameplay iso camera — and raising `HeightAmplitude` does nothing.** The slope cap, not the amplitude, bounds the relief the camera sees. 's `homestead_gen` shipped `FlatMaxGrade 0.08` (4.57°) + amplitude 6 m + TerrainScale 160 m and the heightfield genuinely varied (max adjacent slope pinned at the 0.08 cap), but the total **relief span was only 4.32 m over the 204.8 m world** (~2% grade) — invisible from the steep top-down iso view, so the owner reported "completely flat surface" even though props/pond/textures placed fine. On a bounded world a low grade cap clips the amplitude away: a landform of half-wavelength L can rise at most ≈ `cap·L/π`, so at cap 0.08 / L 80 m the 6 m amplitude was eroded to ~2 m regardless of the amplitude setting. FIX: raise the cap AND lengthen the wavelength **together** (taller permitted amplitude at the same max steepness), then set amplitude to fill it — 's P1 retune cap 0.08→0.24 (13.5°, still walk-anywhere), amp 6→22 m, TerrainScale 160→260 m took the span 4.32→14.77 m and it visibly rolls. Gate the target on a **relief-span probe (min/max heightfield height), NOT `maxSlope`** — maxSlope just pins to the cap whether the world is flat or tall and tells you nothing about visibility. Expose the knobs as named constants. Changing any relief constant **changes the deterministic WorldHash** — re-bless it and update the specs in the same landing. Also: a low sun / night time-of-day makes editor-camera screenshots render with luminance-tracked alpha (dark pixels → transparent → a checkerboard artifact); shoot low-pitch framings with a lit sky band, or use daylight.**

- **Seed-derived scene content keyed on gameplay sites picked AFTER the pure grid (a road to the market, a pond, scatter dressing) belongs POST-HASH — carving it inside the hashed pipeline forces a needless re-bless of every curated seed.** 's W3 road marks `CellFlags.Road` + re-quantizes `Steps`, and `WorldHash` folds Steps+Material+Flags, so a road inside `BuildGrid` would move the blessed hash. But the endpoints (start+market) are picked from the finished grid, and the carve is a PURE fn of the seed (hash-derived endpoints → deterministic index-tiebroken A* → deterministic flatten). Run it in the CONSUMER after `WorldHash.Compute`: `BuildGrid → WorldHash → PickSites → RoadCarve → re-QuantizeSteps + re-Classify → mesh`. Both MP peers carve the identical overlay on the identical pre-road grid (no desync — the hash still validates the shared pre-road grid), and the blessed hash is byte-identical — verified offline, default `a19c446f9733ebd8` + 4 curated seeds byte-unchanged, SpecVersion unbumped, no re-bless ( W3 2026-07-15). The carve MUST still run BEFORE the mesher so corridor cells bake graded heights + UVs.

- **A vendored road/path generator that PICKS ITS OWN POIs will not connect the specific gameplay sites your game already chose — bypass its node-picker and inject the endpoints.** 's `RoadPass.PickNodes` hash-ranks its own flat/low/dry nodes; enabling it as-is would draw roads between invented cells, not the homestead↔market sites 's `PickSites` fixed. The reuse move: author a consumer carve that takes a LIST of POI cell indices as an argument (`Carve(grid, heightsM, poiCells, spec)`), order them with the vendored `NearestNeighbourChain`, and A* each edge — reusing the vendored A*/`MinHeap`/ flatten verbatim, only node-SOURCING (+ the iso-readable width constants) is consumer-owned. Take a list, not two args, so a future N-POI network reuses the same pass without a rewrite (v1 passes `[start, market]`). W3 2026-07-15, offline-verified reaches-market.

- **Render a road as per-cell MATERIAL BYTES in the existing terrain mesh (a strata band), NOT its own ribbon mesh — the band adds ZERO GameObjects and ZERO triangles; a ribbon adds draw calls to an already-at-ceiling scene for no visual gain.** 's scene is already ~2,800 GOs vs 's proven 2,304 draw-call ceiling, so a road GO budget is the binding constraint. Mark corridor cells `CellFlags.Road` → the classifier paints `Strata.RoadDirt`/`RoadStone` (already in the terrain atlas) and they draw through the same one-chunk-one-draw-call atlas as grass: a chunk that gains road cells is STILL one draw call. The carve must run before the mesher so the cells carry graded heights + road UVs when the chunk bakes. Corollary: no bridge PROPS either — v1 fords rivers (the flatten yields at water cells: no mark, no fill, a ~1-cell gap) rather than spanning them with a GO. W3 2026-07-15, offline GO/tri delta = 0.

- **A "zero faces in the forbidden height band by construction" terrain contract will NOT reach zero against block-max collision quantization — plan for an irreducible floor, not 0.** The collider is `block-max over N×N cells` (: 4×4 of 0.2 m = 0.8 m blocks, quantized to 0.25 m steps). A face = the step delta between adjacent blocks. Designing procedural terrain so every relief transition is EITHER a gentle walkable slope (grade ≤ cap ⇒ face ≤ cap·0.8 m ≤ the exempt line) OR a ≥2 m cliff is sound ON PAPER but leaks in-engine because: (a) block-max SPLITS a curved/near-vertical radial riser that straddles a block boundary into sub-2 m halves (raise the riser sharpness so the rise happens within ~1 cell — a single-cell riser is always captured clean); (b) an ANGULAR shape-warp on radial domes adds a TANGENTIAL skirt grade the radial grade cap never sees (cap the warp amplitude, or lower the walk-grade cap so the crossover sits in the gentle-tangential zone); (c) the shared ISLAND-FALLOFF coastline produces sub-2 m faces near/below the waterline that are NOT walk/climb surfaces at all. Measured ( PG4 reshape): the count fell 3480→1068 (−95% vs the shipping mesa's 19809) but never 0; of the residual ~40% were SUBMERGED (below sea level). Make the audit report a `submerged=N` split so the gameplay-relevant residual is legible, drive the mound faces down with sharpness/warp/grade constants, and treat the remaining coastline + quantization tail as a contract decision, not a bug to grind to 0. Verify against a live roam battery (real eject-loops/fall-throughs), which is a truer warp gate than the raw audit count.

- **To render a whole procedurally-generated world as a live 3D PREVIEW inside a ScenePanel, mesh the throwaway grid straight into the panel's own `RenderScene` — DON'T stand up a second live world.** 's center-stage reshape preview (, M16) reuses the project meshers' per-chunk `BuildChunkModel` entry points (`VoxelMesher.BuildChunkModel(grid, mat, cx, cy)` / `HeightfieldMesher.BuildChunkModel(grid, heightsM, atlas, smooth, cx, cy, smooth)` / `WaterMesher.BuildChunkModel(...)`), which RETURN a `Model` (not scene GOs). Key facts that make this drop-in: (1) chunk-model vertices are ABSOLUTE world-space and already `×Tuning.M`, and the world is centred on the origin (`WorldMinM = −extent/2`), so every chunk GO sits at LOCAL zero (`go.SetParent(root, false)`) and the diorama self-assembles around (0,0,·) — the orbit camera just circles the origin, no per-chunk offset math. (2) Hang each Model on a `ModelRenderer` in the RenderScene (`using (RenderScene.Push) { … CreateObject … Create<ModelRenderer>.Model = m; }`, the rig) and SKIP the `ModelCollider` — a preview needs render only, and the Models still carry a baked collision mesh you simply don't attach. (3) The candidate grid is built PURE (`WorldGen.BuildGrid` off the draft spec) so the LIVE world/grid/hash are never touched — determinism-safe. COST: the one-time `BuildGrid` is the same ~1–2 s stall a live regen has (hide it behind a "building…" state + a 2-frame spinner-paint defer); mesh the ~hundreds of chunks a fixed BUDGET per frame (: 24/tick) so no single frame stalls and the world visibly builds up. FULL fidelity is the honest choice (the preview must match the committed world) — the per-tick budget is the only decimation dial; a coarser-grain downsample would DIVERGE from the commit. Light it with the recipe (warm key + cool ambient + `IsMainCamera` cam, dark BackgroundColor) so biome strata read.

- **A code-built world's floor slab must cover the FULL footprint of every prop AND every scripted teleport/waypoint — not just the "main" area.** ' playground had a 40 m ground slab centred on origin (y∈[−20,+20]) but the courtyard's south prop row (and a pilot routine's teleport) sat at y≈−27, over VOID — the character fell through the world after the routine placed it there. The boot prop-overlap/transform audits only check props against each other, never against floor coverage, so nothing caught it. Fixes: (1) size the slab to the used footprint with margin (widened to 60 m); (2) add a standing per-tick FALL-THROUGH INVARIANT to the autopilot (z below floor−2 m → fail the routine, advance) so a void placement is loud on run 1 instead of surfacing as a downstream step timeout.

- **To get a REAL swing in a code-built scene you must actually spawn a SwingRope component — a lone grabpoint-tagged collider only yields a stubby point-pendulum, and a `swingbar`-tagged kit collider spins about the wrong axis** (the kit loader gives tagged collider-children IDENTITY rotation, so the grabpoint GO's WorldRotation must encode the bar axis — the yaw-convention trap). Spawn SwingRope on a GO at an ELEVATED pivot (set Length; set RaycastMountToRoof=false in an open scene with no overhead structure, or its up-raycast snaps the visual mount to whatever floats above); it builds its own segmented visual + knot tagged grabpoint+rope. That knot is COLLIDERLESS by design (a route piece read by TAG), so any "climbable/grabpoint must carry a real collider" census has to EXEMPT `rope`-tagged GOs or it false-fails. Keep the knot well clear (≈5 m) of any other grabpoint so the autopilot's grab window can't confuse them.

- **A pitched/rolled box seated by its centre z sinks its low corner THROUGH the floor and trips the prop-overlap audit.** A rotated box's world AABB half-height is `Σ|R·localHalf|`; for a pitch θ about Y that is `hx·sinθ + hz·cosθ` (NOT just hz). ' −12° ramp (5×4×0.30 m) has envelope half-height 2.5·sin12°+0.15·cos12° ≈ 0.667 m, so a centre at z=0.30 dropped the low vertex to z≈−0.37 and PENETRATED the ground slab (prop-overlap=1). Fix: seat the centre at the rotated half-height (z≈0.67) so the low vertex rests AT grade (touching, penetration < the 1 mm audit eps). Compute the envelope the SAME way the overlap audit does before placing any rotated primitive on a surface.

- **A long, thin placeable's placement-spacing radius must be its SLIM cross-section (`Size.x/2`), NOT a length-based bounding radius (`max(x,y)/2`).** A length-based radius is a fat circle — ≈47u for a 94.5u fence rail — so adjacent end-to-end pieces and perpendicular corner pieces sit INSIDE each other's circle and the placement check false-denies legitimate builds (owner could not close a fence run/rectangle). Real walking collision is the oriented BoxCollider; the placement radius is only spacing, so a slim value is correct and does not weaken collision. Compute footprint per-shape: wall/rail ids → `Size.x*0.5`; everything else → `max(Size.x,Size.y)*0.5`. Runtime-confirmed: after the slim-footprint fix the owner builds flush fence runs and left-turn corners with no false blocks.

- **A SERIAL in-lane ladder of discrete graded ramps (5%..45% one after another, each starting at ground level) makes a hill-grade test measure an OBSTACLE COURSE, not grade-holding — every ramp's far edge is an elevated cliff (a 20 m ramp at 40% crests ~7 m up), so a car driving to its rated grade must jump off every lower ramp's crest en route.** 's first live hillclimb battery on the serial layout: pickup FLIPPED off a crest drop (flips=1), coupe read climbed=false at its rated 35-40% (indistinguishable from a landing crash), wheelspin spiked 7.4-9.7 s on jump landings. Fix: rearrange the same ramps into a PARALLEL FAN — one grade per row, all bases at the same X, rows offset laterally (14 m pitch for 10 m-wide ramps) — and have the scripted driver pure-pursuit to its rated row on flat ground, climb that ramp alone, and END the run ~75% up the slope (never over the crest's drop edge). Same battery after the fan: all four cars climbed=true, flips=0, rollbackM=0. Also keep the ladder layout as ONE shared code table (TestTrack.HillLadder) that both the geometry builder and the measuring maneuver read, so they cannot drift.

- **A prop placed at the MIDPOINT (or any derived position) between two grid-eligible cells can land in a masked-out cell even though BOTH source cells pass the mask.** M9-A2 climb poles were placed at the boundary midpoint between two lattice host cells; each cell was ≥1 block inside the island hull (shoreline law), but on an island world two terraces can be lattice-adjacent across a narrow water inlet, so the midpoint fell in the sea — the over-water audit then flagged the pole footprint (2 violations at 640). The lattice grabs used the strict per-cell eligibility test and were never over water; only the derived pole position skipped it. Fix: re-run the eligibility/water test at the DERIVED point, not just at the source cells (`BlockEligibleAt(midpoint)` before placing). Same family as the copied-trace-filter lesson — re-derive the predicate at the new call site; a value proven for the inputs is not proven for a point interpolated between them.

- **A "default = 1.0" amplitude/relief dial that scales a value ABOUT a pivot — `v = pivot + (v - pivot) * k` — must HARD-GUARD the identity case (`if (k != 1f)`), or the "no-op" default silently perturbs a byte-identical determinism hash.** In IEEE float, `(v - pivot) + pivot` does NOT reliably round-trip to `v` when `v` and `pivot` differ in magnitude (the subtraction loses low bits the add can't restore), so applying the formula even at `k == 1.0` shifts some cells by 1 ULP. In a procedural generator whose output is quantized to integer voxel steps and FNV-hashed as the correctness + multiplayer-sync contract (same seed+spec ⇒ byte-identical grid), a single perturbed height that lands on a quantization boundary flips a Step, changes the grid hash, and desyncs a joining client — from a dial the owner left at its supposedly-inert default. Context: ' new `pg_terrain_relief` (WorldSpec.ReliefScale, default 1.0) compresses terrain height about sea level in HeightPass to flatten slopes for more tree placements. The fix is a one-line guard that SKIPS the scale entirely at the default, so `relief == 1.0` reproduces today's hashes exactly; only a deliberately non-1 value is a declared hash bump. General rule: any post-noise transform gated by a "neutral default" multiplier (scale-about-pivot, lerp-toward-target with t=0, bias+0) must branch out of the arithmetic at the neutral value — never trust the algebra to be a float no-op — whenever the pipeline's output is hashed for determinism. Same family as the seed-hash-multiplier hygiene law: in a hashed deterministic path, every arithmetic op is load-bearing.

- **Composing a "scale about a pivot" transform BEFORE a blend toward a FIXED (un-scaled) target silently moves every threshold crossing the blend produces — order the scale LAST (and make it one-sided if the far side must stay invariant).** Scaling heights about sea level (`h' = sea + (h−sea)·k`) preserves the sign of `h − sea` EXACTLY, so in isolation it can never flip land to water. But ' island falloff then blended the scaled height toward a FIXED rim floor (`sea − 6`): land survives where `(1−t)·k·(h−sea) > 6t`, so the pre-scale height needed to stay dry is `6t/(k(1−t))` — at k = 0.5 the coastal drown threshold DOUBLES across the whole falloff annulus. Result (owner live screenshot, relief-0.5 world): sprawling sea-level inlets flooding every marginal coastal corridor, land reduced to a web of thin strips — the flatten- for-more-trees dial was manufacturing lakes. The trap generalizes: `lerp(v, C, t)` after `v ← pivot + (v−pivot)·k` is NOT the same predicate-preserver as the reverse order whenever C is not scaled with v; any sign/threshold invariant you proved for the scale alone dissolves in the composition. Fix (verified by the water predicate: LakePass reads `dry ⟺ h ≥ sea` strictly): apply the scale AFTER all blends, to the side being reshaped only (`h > sea` cells), so the final `h − sea` sign — and thus the entire coastline — is byte-identical at every dial value, and the un-scaled side (ocean depth, moat rim, wade shelves) cannot degrade at extreme dial values either. Bonus: above-sea basin depths compress, so a min-lake-depth basin gate then yields FEWER lakes at low relief, never more.

- **Lowering the sea level does NOT drain interior lakes in a spill-fill water pass — depression lakes are PERCHED, filled to their own spill surface, so the "make the world drier" lever is the per-basin depth gate (and a land floor for below-sea valleys), not the sea dial.** A priority-flood water pass ( LakePass lineage) keys water to sea level ONLY for sea-connected below-sea regions; every enclosed basin fills to its own rim and doesn't care where the ocean sits. Proven live ( dry-world pass, seed 47 @ 2x): sea 3.0 → 1.0 → 0.5 m left the interior "water webs" visually intact (waterTris 19448 → 17952) — only the coastal rim moved — and a 2.5 m per-basin min-depth gate barely helped because inter-mesa basins run DEEP. What actually dried the interior: (a) raising the per-BASIN min-depth gate out of reach (no perched lake survives) — waterTris 17966 → 4108 (−77%) in one step — and (b) an interior LAND FLOOR in the height pass raising island-core cells that dip below sea up onto land (those webs are sea-CONNECTED and immune to the basin gate), feathered by the island drown fraction (full in the core, zero across the shore band) so the closed-coast moat is untouched. Bonus: drained basins re-opened tree sites (100 → 132 trees) and exposed more climbable cliff (919 → 1648 patches). Real-hydrology "water level" intuition misleads here — each basin has its OWN waterline.

- **Procedural "flattest cell" siting sites INTO water once you add a sea/lakes — the flattest terrain becomes the flat sea/lake shelf.** placed the player start + market with a "flattest cell near a point" search that rejected only a WATER-CENTER cell. After W2 added a coastline + interior lakes, the flattest ground was the coastal/lake shelf, so the market snapped onto the shoreline and — when the hashed target landed in open water with no dry cell in its snap radius — the search FELL BACK to the clamped water target and spawned the market IN the sea; the homestead hugged the shore. A dry-CENTER test is not enough: a 1-cell dry spit surrounded by water passes it. Fix = a dry **FOOTPRINT** predicate — the whole build footprint (a small radius, not just the center) must be dry land AND at least a small margin ABOVE sea level (off the beach) — and search for the flattest cell AMONG qualifying cells, with a deterministic widening fallback (never return a water cell). For a second site constrained to the same landmass (market vs start), reject candidates whose straight segment to the anchor crosses OPEN SEA (a DDA walk; distinguish sea — waterSurfaceStep ≤ floor(seaLevel/stepHeight) — from lakes/rivers, which are walkable-around) and re-pick deterministically by rotating the bearing. Ponds: require the disc footprint clear of water so the authored pond never overlaps the sea. NOTE: this siting runs AFTER the WorldHash is computed and never touches the grid, so tightening it is HASH-INVARIANT (no re-bless).

- **A generation pass that ROUTES against a height/cost field a LATER pass mutates will route wrong.** In 's hydrology pipeline (`Height → Coast → Flat → RiverCarve → Quantize → LakePass → …`), `RiverCarve` walks steepest-descent on the **pre-`LakePass`** float field. Interior depressions are still present there (above sea; `LakePass` floods them into lakes only later), so a river that walks into one **dir-collapses at its floor and stops** — then `LakePass` floods that basin and the river ends up **draining into an interior lake, not the sea** (ALL FIVE curated seeds shipped broken: three rivers stranded in interior lakes, and a subtler MOUTH-BERM variant on the rest — the carve descends below sea level near the coast, the lake pass floods the channel AT sea level, but the last dry berm cells between channel and bay are never cut, leaving a detached look-alike pool). TWO probe traps hid it: a body-inclusive flood treats lakes as valid termini, and even a "flood from cells at/below sea level" probe seeds from the detached mouth pool and verifies it connected against ITSELF — the only correct ocean set is the RIM-connected water flood (on an island design the frontier ring is sea). The trap is pass ORDERING: the router's picture of the world (no lakes yet) differs from the final world. Fixes: (a) route against the post-mutation field (reorder, if the later pass doesn't itself depend on the router's output — here it does, a cycle); or (b) a **POST-pass correction** that fixes only the stranded cases — added `RiverCarve.ExtendToSea`, a deterministic bottleneck-Dijkstra breach from each stranded river's water body over the lowest saddle to the nearest sea, run AFTER the world hash like the road carve, so it's a pure fn of the grid (MP peers agree) and the blessed hash is byte-identical — no re-bless, and it fires ONLY for stranded rivers so healthy seeds are byte-identical no-ops. When you measure "did the router reach its goal", flood from ground truth the goal cannot fake — the map RIM for an ocean — never from a classification (surface level, water type) the router's own carve can produce.

- **A projected `Sandbox.Decal` conforms to a hit surface via `Rotation.LookAt(hitNormal)` — its projection axis is local +X, so orienting +X to the trace normal makes the box straddle the surface.** `Depth` sets wrap reach, `AttenuationAngle` (0=paint all faces, 1=fade at grazing) controls corner wrap. `LifeTime=0` is persistent; `Transient=true` hands eviction to the engine `DecalGameSystem` (`maxdecals`, default 1000). Runtime chunk meshes are normal ModelRenderers so decals project onto them — confirmed live on voxel-terrain chunks in play. A brush REMESH drops its decals (acceptable — repainting terrain clears its paint).

- **A world-space `Sandbox.Decal` CANNOT follow a moving/animating character — parent it under the character and re-pin its WORLD transform to a live bone each frame to paint a moving body.** At spawn pick the nearest skeleton bone (`SkinnedModelRenderer.TryGetBoneTransform`) and store the impact in that bone's LOCAL frame; each frame re-pin `WorldPosition`/`WorldRotation` from the current bone pose. The decal re-projects onto the animated skinned mesh live — paint rides the body through the run cycle on every peer. Set world transform at spawn (frame-0) to avoid a flash at character root. Projection Depth must span the clothing shell (the hit sits inside outer cloth renderers).

- **`Sandbox.Decal` instances are lightweight scene objects (one box projection each, frustum-culled, no per-frame allocation while static), so a persistent-paint system can hold THOUSANDS with no hard engine cap and no crash cliff.** Three practical bounds, all gradual: scene-object count, app-side bookkeeping (O(n) ring-sweep per spawn stays trivial), and FILL RATE for the on-screen subset (worst when many decals overlap the same pixels). Pattern: ring-buffer cap behind a convar (recycle oldest with brief fade), keep visual derivation a pure fn of replicated inputs so peers at different caps render the same marks. Bench method: per-frame census overlay, spam paint into one overlapping area, escalate cap until 1-percent lows sag, back off to a margin.

- **A projected `Sandbox.Decal` seated on a character's analytic hit surface with a shallow projection Depth paints the BASE SKIN mesh but ends BEFORE the clothing renderers' outer shell, so paint shows only where bare skin peeks out.** Layered citizen clothing is separate renderers outside the analytic capsule. Fix: make projection Depth SPAN the clothing shell beyond the seat point. Tradeoff: deep enough to reach outer cloth vs shallow enough not to punch through thin limbs onto the far side.

- **On a track that crosses itself (a figure-eight or any lap that revisits the same ground), nearest-waypoint lookups gain or lose roughly half a lap right at the crossing, because two physically close points on the ring can be arclength-distant.** Three fixes, all required together: (1) drive track position off a MONOTONE CURSOR that advances along the waypoint ring rather than a fresh nearest-waypoint search each frame — the cursor only ever moves forward along the branch it is already committed to, so it cannot jump to the geometrically nearer but lap-distant crossing point. (2) Do lateral/offset math (how far left or right of the racing line a car sits) in a LEFT-OF-TRAVEL frame, not a fixed world-outer-normal frame — the "outward" direction flips sign at the crossing because the two branches run through it in different headings, and a frame that isn't relative to travel direction silently mirrors the offset on one side. (3) When discriminating which of several branches a position belongs to at a sharp crossing (e.g. a ~90 degree intersection of two lobes), the angular acceptance cone must be meaningfully TIGHTER than the branches' angular separation, or a position near the crossing gets claimed by the wrong branch — a cone of roughly two-thirds the branch separation is a safe starting ratio (60 degrees worked for a 90 degree crossing). Segment-clamping each branch's distance query to its own extent (rather than letting it report an unbounded distance past its own end) is what actually resolves the four wedges a crossing creates: a branch pointing away from a wedge clamps to its own endpoint and reports a much larger distance, so the wedge is always classified against the branch that genuinely bounds it — this falls out for free once segment clamping is in place and is worth knowing is load-bearing before someone "simplifies" it away.

- **A sight-line/visibility gate that checks only the tallest or most obvious occluder can pass while a nearer, shorter occluder blocks harder — the gate has to walk EVERY occluder between eye and target and test against each one's own requirement, not just the max-height feature.** An arena's sight-line gate checked the containment wall crest (the feature the design law names) and passed, while the viewing deck's OWN lip — nearer the seats, easy to miss because it reads as the stand's own floor edge rather than a "wall" — occluded harder and left the front row unable to see past 14.8 m of a much larger bowl. Per metre of stand radius the crest cost 0.600 m of required eye height and the deck lip cost 0.720 m, so the lip bound FIRST at every radius even though the crest is the taller absolute feature. **Raising the platform cannot fix its own lip**: the lip's height IS the deck's height, so lifting the deck lifts both the eye that has to see over it and the lip itself by the same amount, and the height term cancels out of the requirement entirely — the surviving variable is how far back the seat sits from the lip, not how high either one is. The levers that actually work are moving the seats back from the lip, raising the seats relative to the deck (a stepped/tiered stand), or lowering the deck. **Rule: enumerate every edge between eye and target as a candidate occluder, compute each one's own required eye-height independently, and gate on the MAXIMUM of the per-occluder requirements** — a gate keyed to one occluder, even the one the design law explicitly names, is a false pass waiting for whichever other edge turns out to be nearer.

- **"Lift a flat overlay clear of the ground" is only half the rule: overlays z-fight EACH OTHER too, and a full-lap overlay on a self-crossing path z-fights ITSELF (no lift value fixes that).** Writing lifts as arithmetic on a couple of shared constants collapses several overlays onto the same height → coplanar faces wherever any two meet in plan; the defect lives in the SET, so a per-call-site review never finds it. Half the symptom arrives as "markings missing" (white paint losing the depth race over dark ground reads as never-painted). Fixes: (a) a named rung PER overlay role, no two sharing a rung — pick a spacing that isn't a whole divisor of the marking thickness (e.g. 11 mm rungs vs 20 mm marks) so a face collision is arithmetically impossible; (b) for a self-crossing closed path, a triangular seam ramp keyed to arclength (0 at one crossing, 1 at the other) so the two passes sit half a lap apart at the ramp extremes. Order the ladder as paint layers (seen-over-wear outranks wear). Gate with a source-text census on 0.5 mm coplanar tolerance; ~7 mm separation proved stable.

- **Offsetting a closed polyline (a road loop split into lanes) needs MITRED points, not per-segment offsets: offset each point along its own corner bisector scaled by `1/cos(half-angle)`, don't shift each segment sideways and rejoin.** Per-segment offsetting leaves GAPS outside a corner and OVERLAPS inside it (each shifted segment is correct along its length but the two no longer meet at the original corner point). A consumer sampling continuously across that seam (a car/agent walking the lane) TELEPORTS by the full offset at each corner. The mitre construction (bisector direction, magnitude `1/cos(half-angle)`) closes the seam exactly for any interior or exterior angle.
