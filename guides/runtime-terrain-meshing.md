---
title: Runtime terrain meshing — chunked greedy voxel/heightfield terrain
slug: runtime-terrain-meshing
date: "2026-07-13"
updated: "2026-07-17T09:14:00-04:00"
lanes:
  - writing-gameplay
  - making-it-perform
tags:
  - terrain
  - meshing
  - runtime-mesh
  - procedural
summary: >-
  The method for large runtime-generated terrain in s&box: a persistent cell
  grid as the single source of truth, chunked greedy meshing (tops + skirts),
  collision decoupled from render grain, palette-atlas UVs, and dirty-chunk
  remesh for a live terrain brush.
verifiedOn: "26.07.15a"
sourceRev: a18fad046546
relatedFixes:
  - runtime-world-building-helpers
  - sbox-units-are-inches
  - edit-mode-destroy-query-lag
  - heavy-work-no-hitches
  - saveload-without-drift
unverified: false
---

The method for building large runtime-generated terrain in s&box: a persistent
cell grid as the single source of truth, chunked greedy meshing (tops + skirts),
collision decoupled from render grain, a palette-atlas material with constant
per-face UVs, and dirty-chunk remesh for a live terrain brush.

Official docs cover the raw API (`new Mesh(material)`,
`CreateVertexBuffer/IndexBuffer`,
`Model.Builder.AddMesh().AddCollisionMesh().Create()`) — this guide is the
method on top. See also [runtime-world-building-helpers](runtime-world-building-helpers).

## Architecture: grid → mesher → chunks

```
Generation passes (pure C#, deterministic)      ← noise, rivers, quantize…
   ▼
WorldGrid  (persistent: heights/steps[], material[], water[], flags[])
   ▼                                            ← the brush mutates THIS
Mesher (reads grid ONLY — per chunk: render Model + collision)
   ▼
Scene: one GameObject per chunk (ModelRenderer + static ModelCollider),
       all under ONE world-root GameObject
```

The **mesher-reads-grid-only rule** is what makes everything else cheap: swapping
meshers, live editing (mutate cells → remesh dirty chunks), and save (persist
grid deltas, not geometry) are all consequences. Never let gameplay or editing
code touch vertices — only cells.

A 2.5D **column grid** (per cell: quantized integer height step + material id +
flags) is ~10× cheaper than true 3D voxels and is the right model unless you need
caves; the mesher interface is the migration seam if you ever do.

## 1. The seam law (get this right FIRST)

Chunk seams/cracks come from one mistake: sampling vertices on per-chunk math.

- **Chunk size AND world extent must be integer multiples of the cell size.**
- **Every vertex XY comes from the GLOBAL cell-index lattice** —
  `worldMin + index * CellSize` — never `round((x1-x0)/grid)` per chunk.
  Fractional overshoot is the silent seam generator.
- Greedy runs never cross a chunk boundary, so both sides of a shared edge sit
  on the same lattice by construction.

Audit shared-edge heights as bit-identical on every regeneration. Note the audit
checks *lattice math*, not stale geometry — a missed dirty chunk shows as a
visible crack, not an audit offender.

## 2. The greedy mesher (mandatory at density)

A naive per-cell mesher cannot carry a dense world. Greedy meshing and coarse
collision go in **with** the mesher, not after. Per chunk:

- **TOPS** — classic 2D greedy meshing: merge maximal rectangles of identical
  `(step, material)` over the chunk mask. One quad per merged rectangle.
  Terraced/flat terrain merges 5–15×.
- **SKIRTS** — per direction, merge collinear runs where
  `(ownStep, neighbourStep, material)` match; **one quad spanning the FULL
  drop**, not one per step. Skirt faces get a darkened palette variant — cheap
  fake AO.
- **Flat shading**: face normals only. The faceting IS the look; smoothed
  normals ruin it.

### Winding — verify with a screenshot, not a cross product

The front-facing pattern for a quad `a=origin, b=a+u, c=a+v, d=a+u+v` is
`{a,b,c},{b,d,c}` with front = `u×v` (plain CCW): tops `u=+X, v=+Y` → front +Z;
skirts choose `u` (run direction) and `v=+Z` so `u×v` equals the outward wall
normal. **Do the 60-second above/below check on the first meshed build**: a shot
from below must show almost nothing (tops cull from below); a world solid-colored
from below is inside-out. Do NOT "fix" verified winding when a cross product
reads −Z.

### Units

Author every pass in **meters**; exactly one `× 39.37` at vertex emission. Two
conversions (or zero) is the classic scale bug — see
[sbox-units-are-inches](sbox-units-are-inches).

## 3. Collision is NOT the render mesh

At density, per-poly concave collision from the render mesh is wasted cost and
hurts movement. Decouple them:

- Render model: the greedy mesh above.
- Collision: a per-chunk **coarse grid** of blocks, each ONE flat quad at the
  block's MAX cell height — simple, non-terraced, fed to `AddCollisionMesh`.

Consequences: characters/vehicles ride the coarse surface, not the visual
terraces; anything that needs the *climbable* surface must read the collision
grid, not the render mesh. Empty chunks must not emit zero-length buffers.

**The render-to-collision gap has a KNOWN sign and bound when the render
surface is continuous** (smooth/LowPoly, not the per-cell voxel step). On a
local MAXIMUM the block-max collapses to the peak cell's FLOOR, so the render
surface sits ABOVE collision by `frac(peakHeight)` (up to one StepHeight) --
visual character BURIAL on crest/plateau tops. On SLOPES the block-max rides
above the render so the body FLOATS. Remedy without touching physics: raise
the rendered body child by `max(0, render - collision)` at the feet XY when
grounded -- visual-only, proxy-safe (each peer computes its own),
smooth-render-only (Voxel has no burial: its render top is the per-cell step
`≤ block-max`).

**Mover-side alternative (the more complete fix).** The visual-lift above only
patches the crest burial (`max(0, render−collision)` clamps away the slope case),
and it is a per-frame visual child offset. A more complete approach moves the
**mover's vertical ground-follow onto the render surface** on continuous styles:
reproduce the mesher's surface at an arbitrary feet-XY (the per-block `CornerH`
corner lattice with the style's own snap flag, the `SplitAlongAD` diagonal,
barycentric interpolation) and ride it in the **fixed tick** (written into the
`OnFixedUpdate` `WorldPosition`, so engine interpolation carries it — no visual
offset). One change kills burial (crest), float (slope), and the discrete
step-bounce the coarse collision otherwise imposes on a visually smooth slope.
Scope it to the vertical walk-over-terrain follow only — keep the raw coarse
trace for the horizontal wall/object test and guard columns where the trace
stands above the coarse terrain block-max (standing on a prop, not terrain). A
trace-based mover has no collider, so riding a height below the block-max never
fights physics; the fall-through audit must read the same ridden surface or it
rescue-pops the offset back up. Do this in the fixed tick — never as a per-frame
visual-Z model offset (that is the separate documented flicker trap of a second
smoother fighting `FixedUpdateInterpolation`). Voxel style stays unchanged.

## 4. One material, palette atlas, constant per-face UV

One draw call per chunk, crisp flat pixel color:

- A single small **palette atlas PNG** (grid of flat colors + darkened skirt
  variants).
- Every merged face gets the **CONSTANT atlas cell-center UV of its material**.
  Constant UV across a face ⇒ zero UV derivatives ⇒ the GPU never mip-blends
  between atlas cells — no color bleeding at any distance.
- Band/biome transitions are **hash-dithered per cell** (salt-and-pepper), never
  a hard line.
- Regenerated atlas PNGs need an editor kick to recompile.

### Reskinning a vendored atlas to a project palette

When you **vendor** another project's mesher, its general-biome atlas often reads
wrong for your art direction. The whole recolor is a **render-side remap** -- you
never touch the vendored code:

1. **The PNG is the color source, not the C# array.** The mesher points a constant
   per-face UV at a cell center in the atlas PNG; the C# color array is only for
   UI (minimap/legend). A LowPoly consumer recolors purely by regenerating the PNG.
2. **Regenerate a project-owned atlas matching the vendored cell layout.** Replicate
   `CellCenterUv`'s geometry exactly: `col = cell % Cols`, `row = cell / Cols`,
   center sampled at `((col+0.5)/Cols, (row+0.5)/Rows)`. Fill each cell as a solid
   block; the constant-UV trick samples the dead center, so any cell size works
   with zero mip bleed.
3. **Point `Material.Load` at the project atlas**, keeping the vendored one as a
   `??` fallback so a missing asset degrades to the old look, not magenta.
4. **Determinism is free:** the grid's per-cell material **byte** is unchanged --
   only the color it maps to changes -- so the WorldHash is byte-identical.

## 5. Chunk lifecycle and the stale-root class of bug

- One GameObject per chunk under **one world root**; rebuild = tear down the old
  root, build the new one.
- **Tear down with `DestroyImmediate()`, not `Destroy()`**: in edit mode
  `Destroy()` is deferred and the destroy queue doesn't process between
  tool-driven regenerations — the superseded world keeps rendering ON TOP of the
  new one. Invisible when specs match, "doubled/wrong world" when they differ.
  See [edit-mode-destroy-query-lag](edit-mode-destroy-query-lag).
- Assert scene invariants on every regen: `worldRootCount == 1`,
  `chunkGOs == expectedChunks`.
- Budget habit: log a census line (`chunks / tris / ms`) on every rebuild; keep a
  tri budget audit. Cell-count/regen-time binds before raw render tris.

### Sizing a bigger world: cost is cell-count-bound, so CellSize is free area

The load-bearing sizing law: **render/collision tri counts and generation time
scale with `WorldSize` squared (the cell count) and are INDEPENDENT of `CellSize`.**
Render tris = `2 * (WorldSize/decimation)^2`, collision =
`2 * (WorldSize/CollisionBlockCells)^2`, gen time is approximately O(WorldSize
squared) at fixed pass counts. `CellSize` only scales the physical FOOTPRINT
(`WorldSize * CellSize` metres). So the cheapest way to make a world BIGGER is a
**coarser CellSize at the same cell count** -- pure free area, zero tri/gen cost.
The one cost is the **facet size = `CellSize * decimation`** (the low-poly grain),
which grows with CellSize.

The real ceiling on this lever is the **facet size you can visually tolerate**, not
performance. Pull CellSize first (free area), then raise WorldSize toward the
proven ceiling, and keep decimation at 2 (dropping to 1 quadruples tris). Gen time
scales by the cell-count ratio and is the felt cost (a one-time boot stall).

**Changing WorldSize or CellSize changes the WorldHash** -- re-bless it.

## 6. Determinism (the correctness contract)

The grid must be a pure function of the spec: **no `System.Random` in the gen
path**, constant-seeded integer-hash value noise only, pure functions of (x, y).
Same spec = byte-identical grid — provable with a process-independent content
hash over the grid arrays (with per-array sub-hashes that localize a divergence).
That hash is what makes regression testing, save-as-delta
([saveload-without-drift](saveload-without-drift)), and
[spec-replication networking](/guides/networking-methods) possible.

Clear any static per-gen capture at the top of every generation.

### Re-blessing the WorldHash offline (no engine needed)

Because the grid hash is process-independent by design (the MP contract -- two
peers on different machines MUST agree), you can compute the exact live hash in a
plain console app: copy the PURE gen slice into a harness, shim the handful of
engine types (`Color`/`Color32`/`Vector`/`Log`) -- they never feed the hashed
arrays -- and run `BuildGrid -> Hash.Compute` twice. Two guards make the offline
value trustworthy as a BLESSING, not a guess: (1) determinism -- the two runs are
byte-identical; (2) **ACID validation** -- the SAME harness must reproduce a KNOWN
live hash of the OLD spec exactly; once it does, it reproduces them all. So a
config change's new hash lands in the same commit as the change, no live
round-trip. Reproducing two known hashes (double-ACID) is strictly stronger and
cheap.

## 7. Live editing: dirty-chunk remesh (the brush)

The payoff of grid-as-truth:

- Brush ops mutate **cells** (never vertices), then mark dirty chunks; only those
  chunks remesh in place. A small-radius stroke remeshes in **single-digit ms**.
- **The seam corollary**: a mutated BORDER cell must dirty the chunk it belongs
  to PLUS its seam neighbours — the neighbour's skirt quads sample this cell's
  step across the seam. Corner cells add the diagonal chunk. Derive the dirty
  footprint from the *widest read* any mesher makes.
- Post-edit reconciliation: reclassify materials for touched cells + 1-ring,
  reseat/clear props on cells that moved > 1 step, reconcile water against sea
  level.
- Test hook: a scripted-strokes McpTool returning dirty-chunk count + remesh ms +
  the full audit suite — see [/guides/agent-test-harness](/guides/agent-test-harness).
- **Aim the interactive brush at the GRID, not at the colliders you rebuild.**
  The in-place remesh swaps each dirty chunk's `ModelCollider.Model`, which
  rebuilds that collider's physics body -- so a `Scene.Trace.Ray` cursor aimed
  at those chunks intermittently misses on the frames the body is rebuilding,
  degrading a hold-to-paint stroke to click-click-click. Target instead by
  marching the camera ray against the heightfield (grid-as-truth is read-only
  and physics-independent, so it's immune to the rebuild window and works in
  edit mode where there are no play colliders). Apply the metres-to-units
  conversion only at cursor emission. Watch the march bound: a ray parallel to
  both footprint axes leaves the slab exit unbounded -- clamp it.

## 8. Making generated terrain traversable (drivable / walkable)

Un-tuned procedural output hard-stops a road car (walls/banks/terraces block it
within metres) and can produce unwalkable cliffs. The conditioning recipe that
keeps real rolling relief:

1. **Condition the PRE-QUANTIZE float heightfield, not the mesh.** Transform the
   float field before `QuantizeSteps` so render, collision, and content hash all
   agree. Gate it behind an append-only spec field (default off = byte-identical
   legacy worlds).
2. **Slope cap: a Lipschitz LOWER-ENVELOPE min-cap, not symmetric relaxation.**
   Sweep rows then columns forward+back capping
   `h[i] <= h[nbr] + maxGrade * CellSize`, repeat to a fixpoint — a hard
   no-slope-over-grade guarantee, erosion-only (cliffs become ramps, hills
   untouched), deterministic. Symmetric "split the excess" relaxation converges
   only asymptotically and leaves residual car-stopping faces after dozens of
   iterations.
3. **Curvature: smooth BEFORE the cap.** The grade cap does not bound curvature;
   a long chassis beaches on a sharp in-grade crest. A few dozen 3x3 box-blur
   passes round crests/pits.
4. **Size the collision quantization to the VEHICLE.** Block-max collision risers
   must stay under the car's ground clearance. Character-tuned defaults may
   high-centre a vehicle on terrain whose render mesh looks fine.
5. **Cap cruise speed or wheels tunnel.** Raycast wheels penetrate rising coarse
   collision at speed and the car ends up under the surface.
6. **Verify with a scripted roam + audits.** Waypoint ring, speed-governed; audit
   hard-stops, flips, fall-throughs, NaNs, path odometer; hash the grid twice
   per seed.

**The same recipe makes terrain walkable-everywhere** -- the Lipschitz
lower-envelope cap is grade-agnostic. For a walkable consumer, steps 4-5
(collision-quant-to-vehicle and speed-cap) can be dropped since they're car-only
concerns; the character step tune is already sized to the coarse block. The pure
conditioning pipeline is a stable reusable static lib.

7. **The slope cap -- NOT the amplitude -- bounds the relief the camera sees.**
   On a bounded world a low grade cap clips amplitude away -- a landform of
   half-wavelength L can rise at most approximately `cap * L / pi` before the cap
   erodes it. RAISING amplitude alone does nothing; you must **raise the cap and
   lengthen the wavelength together** (a taller permitted amplitude at the same max
   steepness), then set amplitude to fill it. Expose amplitude/wavelength/
   ruggedness/grade-cap as **named constants** and gate the target on a
   **relief-span probe** (min/max heightfield height), because `maxSlope` alone
   pins to the cap regardless of how flat or tall the world reads. Changing any
   relief constant **changes the WorldHash** -- re-bless it.

## 9. Hydrology on a slope-capped world (coastline + river)

Adding water to a slope-capped terrain surface:

1. **Coastline is post-quantize.** The coast is a SEA LEVEL threshold applied AFTER
   `QuantizeSteps` + slope conditioning. A cell with a step below `seaLevel` gets
   `CellFlags.Sea` + a water surface step; the mesher skips tops below sea for
   render (the ocean covers them) but collision still uses the block-max so
   underwater blocks are walkable/driveable.
2. **The flat world edge floods back.** The slope cap flattens the outer world to
   the lowest amplitude; if sea level is above that flat, the coast wraps the WHOLE
   map edge. Size amplitude + wavelength so the highest ridge stays above sea level
   across the world's footprint.
3. **Rivers and lakes use the same proven carve algorithm** -- a momentum walk +
   monotonic floor/surface terrace + upstream chain. Sub-cell-width rivers are
   invisible on coarse grain: own the width constants at your cell scale.
4. **Curate seeds with an OFFLINE grid search.** The offline harness measures
   sea/river/lake cell counts, shoreline length, river-reaches-sea connectivity,
   start-cell dryness/flatness, then scores with hard gates plus preference terms
   and renders a downsampled preview PNG for the eyeball pass. Parallelize over
   seeds (each build is pure/independent).
5. **"Dry start" needs a dry FOOTPRINT, not a dry cell.** After adding a coast +
   lakes, the flattest cells ARE the flat shelf -- so a "flattest cell, reject
   water" picker snaps the start onto the shoreline. Fix: a dry-FOOTPRINT
   predicate (whole footprint dry land AND above sea level), search flattest among
   qualifying cells with a deterministic widening fallback.
6. **Pipeline order helps but does NOT guarantee every river reaches the sea.**
   The river carve walks steepest-descent on the pre-lake-pass field, so a
   river that walks into an interior depression stalls and the later lake pass
   floods it into a landlocked lake. Detect with a **rim flood** (flood through
   all water starting from the map rim -- on an island the rim IS the ocean; a
   river-flagged water cell not reached is stranded). Fix with a post-hash
   **breach**: label each stranded river body, bottleneck-Dijkstra the lowest
   saddle (lexicographic max-ground-crossed then path-length, so the breach is
   the shallowest cut) to the nearest sea, and carve a mature-width channel
   with a descending water surface (body spill level down to sea level). For a
   stranded mouth pool (already at sea level) the breach runs flat through the
   berm. Run it post-hash like the road: a pure fn of the grid ensures
   multiplayer peers agree, and gate it so it fires only for stranded rivers
   (healthy seeds are byte-identical no-ops). Cap the breach depth so a deeply
   enclosed lake doesn't get a slot-canyon -- past the cap, leave it feeding
   its lake.

## 10. A routed road between gameplay POIs (post-hash carve, zero-GO material band)

Connecting two gameplay sites with a routed road:

1. **Injected endpoints, NOT the vendored node-picker.** A game that must connect
   specific fixed sites passes the endpoints in, orders them with nearest-neighbour
   chain, and A-stars each consecutive edge.
2. **Run it POST-HASH (cosmetic-over-fixed-geometry).** The endpoints are gameplay
   sites picked *after* the pure grid exists, and the road is a pure function of
   the seed. Run it in the consumer after `WorldHash.Compute` -- both MP peers
   carve the identical road on the identical grid. The general rule: *any
   seed-derived scene content keyed on post-pure-grid gameplay sites belongs
   post-hash, not in the hashed pipeline.*
3. **Render as a MATERIAL BAND in the existing mesh -- ZERO GOs, ZERO tris.** Paint
   the corridor cells a road strata via a cell flag and they draw through the same
   one-chunk-one-draw-call atlas. A chunk that gains road cells is still one draw
   call -- the road adds exactly zero GameObjects and zero triangles.

## Consuming generated terrain in a flat-z0 game (the ground-service seam)

Making a game that assumed a flat z=0 world stand up on generated terrain:

- **One ground-height service with a degenerate classic path.** A single static
  `HeightAt(x,y)` that returns **0 everywhere in the flat world** and the terrain
  height in the generated world. Every consumer (prop spawn, player movement,
  cursor projection, save load) routes through it -- one terrain-agnostic code
  path, no per-scene branches.
- **Kinematic consumers sample the CONTINUOUS analytic heightfield, NOT the
  collision mesh.** The faceted render/collision mesh differs by up to one step;
  sampling it makes the player stair-step and desyncs cursor-vs-prop.
- **The ground datum is a LARGE global offset.** A walkable consumer's jump height,
  fence-clear threshold, and wall-trace start must stay *relative to local ground*
  -- never an absolute z threshold.
- **Save the (seed, spec), DERIVE z on load.** Persist `(worldMode, seed,
  specVersion)`, not geometry; regenerate the byte-identical world from the seed
  and re-derive every placed entity's z from `HeightAt(x,y)` at spawn.
- **Reset the service on every boot.** The service is a process-wide static; a
  scene that plays the flat world after the generated one must call `SetClassic()`
  in its bootstrap, or the stale Generated mode leaks across the play session.

## Build order (condensed)

1. Grid type + deterministic noise + a stub flat world; census log; content hash.
2. Seam-law chunking + naive mesher just long enough to verify winding by
   screenshot.
3. Greedy tops + merged full-drop skirts; palette atlas + constant cell-center
   UVs.
4. Coarse collision grid, separate from render.
5. Boot audits (seam, tri budget, NaN scan, water-above-terrain) as target-0
   greppable lines; wire them into every regen.
6. DestroyImmediate world-root lifecycle + single-root/chunk-count asserts.
7. Dirty-chunk remesh + brush ops (only now — the architecture has been waiting
   for it).
