---
title: Runtime terrain meshing — chunked greedy voxel/heightfield terrain
slug: runtime-terrain-meshing
date: "2026-07-13"
updated: "2026-07-15"
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

## 6. Determinism (the correctness contract)

The grid must be a pure function of the spec: **no `System.Random` in the gen
path**, constant-seeded integer-hash value noise only, pure functions of (x, y).
Same spec = byte-identical grid — provable with a process-independent content
hash over the grid arrays (with per-array sub-hashes that localize a divergence).
That hash is what makes regression testing, save-as-delta
([saveload-without-drift](saveload-without-drift)), and
[spec-replication networking](/guides/networking-methods) possible.

Clear any static per-gen capture at the top of every generation.

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

**The same recipe makes terrain walkable-everywhere** — the Lipschitz
lower-envelope cap is grade-agnostic. For a walkable consumer, use a tighter
grade (e.g. maxGrade 0.08 = ~4.6 degrees), low amplitude, and broad terrain
scale. Steps 4–5 (collision-quant-to-vehicle and speed-cap) can be dropped
since they're car-only concerns; the character step tune is already sized to the
coarse block. The pure conditioning pipeline is a stable reusable static lib.

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
