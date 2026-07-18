---
title: "World scale and coordinate limits: units, the '20k' folklore, and float precision"
slug: world-scale-and-coordinate-limits
date: "2026-07-18T21:10:00-04:00"
updated: "2026-07-18T21:10:00-04:00"
lanes:
  - getting-art-in
  - writing-gameplay
  - making-it-perform
tags:
  - units
  - coordinates
  - precision
  - world-size
  - float
summary: >-
  Disambiguates the recurring "20k world" confusion (units vs metres vs Source 1
  folklore), measures s&box's float-precision curve from origin, confirms the
  engine has no hard coordinate wall or edict cap, and frames the practical
  sizing ceiling for runtime-generated worlds.
verifiedOn: "26.07.15a"
relatedFixes:
  - sbox-units-are-inches
unverified: false
changelog:
  - { date: "2026-07-18", note: "Published." }
---

This guide exists to kill one recurring confusion: **when someone says "a 20k world", they almost never mean the same thing twice.** "20k" is three different numbers depending on whether it is units, metres, or a folk-rounded Source 1 map extent, and they are ~1550x apart. Read the units section first; everything else hangs off it.

Cross-refs: [runtime-terrain-meshing](/guides/runtime-terrain-meshing) (the "grain is free area" sizing lever, framed in coordinate/units terms here but not restated), [sbox-units-are-inches](/fix/sbox-units-are-inches) (the raw unit atom).

---

## 1. Units: the one conversion that resolves "20k" (verified)

s&box measures world space in **units, where 1 unit = 1 inch** (the inherited Source convention). The exact conversion:

- **1 metre = 39.37 units**; **1 unit = 0.0254 m**.
- Do all design math in SI, convert once at the engine boundary (`const float MetresPerUnit = 39.37f`). Two conversions, or zero, is the classic scale bug (see the [runtime-terrain-meshing](/guides/runtime-terrain-meshing) units note and [sbox-units-are-inches](/fix/sbox-units-are-inches)).

So "20k" disambiguates to three wildly different numbers:

| What "20k" was said to mean | In the other unit | Notes |
|---|---|---|
| **20,000 units** | **~508 m** per side | a modest world, roomy for most gameplay |
| **20,000 metres** | **~787,000 units** | a 20 km world; storage quantum ~1.6 mm out there, motion behaviour unverified |
| **"20k x 20k" as Source 1 map folklore** | **~416 m** usable | the plus/minus 16,384-unit cube, folk-rounded up |

The lesson: **never accept a bare "20k" world-size spec.** Ask units or metres, and convert.

## 2. Where "20k x 20k" comes from: Source 1 map history

The "20k x 20k" figure is **Source 1 / GoldSrc map history**, not an s&box limit. Everything in this section describes the *old* engines (per cited community references); it asserts nothing about s&box:

- Source 1 used a signed coordinate cube of roughly **plus/minus 16,384 units** from the map centre, about **32,768 units across**, with roughly **16,384 x 16,384 units freely usable** in practice.
- In s&box units, 16,384 units is only about **416 m**; the full span is about **832 m across**. That is a *small* world by modern standards, which is why the number gets folk-rounded up.
- Exceed that cube in VBSP-era Source and the compiler threw the infamous **"Map coordinate extents are too large!!!"** wall. That hard wall is what people are half-remembering when they treat "20k" as a limit.

Takeaway: **"20k x 20k" is a remembered Source 1 constraint, not an s&box rule.** Treat it as history (~416 m usable), never as a spec ceiling.

## 3. Source 2 / s&box removed the hard coordinate wall (verified, 26.07.15a)

s&box **does not have the VBSP-style "coordinates too large" wall**, and this is now measured. A `GameObject` placed at 16,384 u (the old half-extent), 100,000 u, 787,400 u (20 km), 10,000,000 u, and -787,400 u along one axis is accepted without error, stores finite values, and reads its position back exactly. Physics works out there too: a ray trace against a collider spawned at 787,400 u hits its analytic surface point with zero measured error.

There is no fixed coordinate cube. World size is not gated by a hardcoded extents check; it is gated by the soft fp32-precision behaviour in the next section and by your runtime budget.

## 4. The real modern limit: float precision from origin (measured, 26.07.15a)

The modern ceiling is **32-bit float precision coarsening with distance from the origin (0,0,0)**, not a coordinate box. On 26.07.15a this is a measured curve: at every distance tested, the smallest representable position step exactly equals the theoretical fp32 ULP (unit in the last place). No extra quantisation, no hidden double precision.

| Distance from origin | In units (39.37 u/m) | Measured position quantum | In real terms |
|---|---|---|---|
| 1 km | 39,370 u | 0.00390625 u | ~0.1 mm |
| 4 km | 157,480 u | 0.015625 u | ~0.4 mm |
| 8 km | 314,960 u | 0.03125 u | ~0.8 mm |
| 16 km | 629,920 u | 0.0625 u | ~1.6 mm |
| 20 km | 787,400 u | 0.0625 u | ~1.6 mm |

Ray traces against a collider at each distance hit the surface with zero measured error.

**The famous visibility thresholds are lore, and static measurement could not reproduce them.** Community sources report faint defects past roughly 8 km and very noticeable ones past 20 km. A static render probe (identical arrangements at origin, 8 km, and 20 km; consecutive-frame pixel diffs) found no temporal jitter above the renderer's flat dither floor and no visible geometric displacement.

What those measurements do NOT cover (and where the lore may still hold): a **moving camera in a published build**, physics **resting jitter under live simulation**, and **skeletal animation** far from origin. Treat the 8/20 km figures as unconfirmed community lore about those mechanisms, not as measured engine behaviour.

Watch the trap in the 20 km figure: "20 km" IS metres (~787k units), and it also reads as "20k" if you drop the "m" — a second, independent source of the "20k" confusion.

**Design consequence:** keep gameplay near origin anyway. It costs nothing and buys headroom. But the measured curve says the pressure is mild: a 508 m (20,000-unit) world has a position quantum of ~0.05 mm, and even 20 km out the storage quantum is ~1.6 mm. Only genuinely planet-scale worlds need origin-rebasing tricks, and the first thing to test there is moving-camera rendering, not position storage.

## 5. The 16,384 edict cap is Source-family history; s&box has no edict cap (source-verified)

A separate **16,384** figure gets conflated with world size: the **networked-entity (edict) cap**. That cap is real in older Source-family engines (Counter-Strike 2 is cited at 16,384 edicts). **It does not exist in s&box.** Source-verified against the public engine source:

- s&box's scene networking has no edict table. Networked objects are keyed by `Guid`, not by an index into a fixed-size slot array.
- No cap constant exists: repo-wide searches for `MAX_EDICTS`, `MaxEntities`, and "entity limit" return zero hits.

The practical ceiling on networked-object count in s&box is bandwidth and snapshot cost, not a hardcoded number. A live saturation test remains open for anyone who needs the felt ceiling.

Two different 16,384s float around: the Source 1 coordinate half-extent (a distance in units, historical) and the edict cap (a count of entities, historical). Do not let either masquerade as an s&box sizing rule.

## 6. Practical scaling for runtime-generated terrain

For a runtime-generated heightfield/voxel world (the [runtime-terrain-meshing](/guides/runtime-terrain-meshing) architecture), the binding costs are not the coordinate limits above. They are:

- **Regeneration CPU scales with cell-count squared** (`WorldSize^2`). This is the felt cap, the one that stalls a boot/rebuild.
- **Triangle budget tracks cell count, not footprint.** A world's tri count is set by how many cells it has, not how many metres it spans.
- **Grain (metres per cell) buys footprint at zero regen/triangle cost.** Coarsening the cell size enlarges the physical world for free; the only cost is the visible facet size.

The payoff: **the folklore "20k x 20k" world is comfortably reachable by a runtime-generated world in-budget today.** A 1280-cell grid at 0.4 m grain is 512 m per side, about 20.1k units. That is inside the proven density ladder and nowhere near any measured precision concern (position quantum ~0.05 mm at ~20k units).

## 7. Two things that do NOT scale with world size

In a deterministic replicate-the-seed architecture (replicate the generator spec + edit log, each client regenerates locally):

- **Network cost is world-size-independent.** You ship a small generator spec plus the edit log, not geometry. A 508 m world and a 1 km world cost the same on the wire.
- **A fixed-size minimap downsample stays fixed.** Downsampling the grid to a constant-resolution minimap texture costs the same regardless of footprint; a bigger world just means each texel covers more metres.

So the sizing decision is a local CPU/GPU/precision decision, not a bandwidth one.
