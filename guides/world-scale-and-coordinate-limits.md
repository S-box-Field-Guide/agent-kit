---
title: "World scale and coordinate limits: units, the 20k folklore, and float precision from origin"
slug: world-scale-and-coordinate-limits
date: "2026-07-18"
updated: "2026-07-18T16:00:00-04:00"
lanes:
  - writing-gameplay
  - making-it-perform
tags:
  - world-scale
  - coordinates
  - precision
  - units
  - terrain
summary: >-
  What "a 20k world" actually means (units vs meters vs Source-1 map folklore,
  and they are ~1550x apart), why s&box has no VBSP-style coordinate wall, and
  the real modern ceiling: fp32 position precision that coarsens with distance
  from origin. Measured numbers, the lore separated from the measurements, and
  the reproduction method.
verifiedOn: "26.07.15a"
sourceRev: 1ad54b664846
relatedFixes:
  - sbox-units-are-inches
unverified: false
---

In-engine facts here carry the engine build they were verified on: the unit conversion and the runtime-terrain scaling composition on 26.07.15, the coordinate-extent and precision measurements on 26.07.15a. The Source-1 origin story (sections 2 and 5) is presented as cited history, not engine behavior, and needs no in-engine verification. The one folklore item that survives as lore (visible artifacts at 8/20 km under motion) is explicitly framed that way in section 4, alongside the measured evidence against it. Reproduction method is in "How these numbers were measured" at the end.

This guide exists to kill one recurring confusion: **when someone says "a 20k world", they almost never mean the same thing twice.** "20k" is three different numbers depending on whether it is units, meters, or a folk-rounded Source-1 map-extent, and they are about 1550x apart. Read the units section first; everything else hangs off it.

Cross-refs: the [runtime terrain meshing guide](/guides/runtime-terrain-meshing) (the "grain is free area" sizing lever, which this guide frames in coordinate/units terms but does not restate), and [sbox-units-are-inches](sbox-units-are-inches) (the raw unit atom).

## 1. Units: the one conversion that resolves "20k" (VERIFIED)

s&box measures world space in **units, where 1 unit = 1 inch** (the inherited Source convention). The exact conversion:

- **1 meter = 39.37 units**; **1 unit = 0.0254 m**.
- Do all design math in SI, convert once at the engine boundary (`const float MetersToUnits = 39.37f`). Two conversions, or zero, is the classic scale bug (see the runtime terrain meshing units note and [sbox-units-are-inches](sbox-units-are-inches)).

So "20k" disambiguates to three numbers that are wildly different:

| What "20k" was said to mean | In the other unit | Notes |
|---|---|---|
| **20,000 units** | **~508 m** per side | a modest world, roomy for most gameplay |
| **20,000 meters** | **~787,000 units** | a 20 km world; storage quantum measured at ~1.6 mm out there, motion behavior unverified (section 4) |
| **"20k x 20k" as Source-1 map folklore** | **~416 m** usable (section 2) | the plus/minus 16,384-unit cube, folk-rounded up |

The lesson: **never accept a bare "20k" world-size spec.** Ask units or meters, and convert. A spec that reads fine as units ("20,000 units, ~508 m") is a different planet as meters ("20,000 m, ~787k units").

## 2. Where "20k x 20k" comes from: Source 1 map history (cited lore, not an s&box claim)

The "20k x 20k" figure is **Source 1 / GoldSrc map history**, not an s&box limit. Everything in this section describes the *old* engines, per the cited community references (see Sources); it is included as the origin story of the number and asserts nothing about s&box, so it carries no in-engine verification stamp by design:

- Source 1 used a signed coordinate cube of roughly **plus/minus 16,384 units** from the map center, i.e. **32,768 units across**, with about **16,384 x 16,384 units freely usable** in practice (per the cited references; community memory disagrees on details, and some level-design references say the original freely-movable box was smaller, about 4,096 units from center, with 16,384 the extended figure).
- In s&box units, 16,384 units is only about **416 m**; the full 32,768-unit span is about **832 m across**. That is a *small* world by modern standards, which is exactly why the number gets folk-rounded **up** to a friendlier "20k x 20k" when people repeat it.
- Exceed that cube in VBSP-era Source and the compiler/engine threw the infamous **"Map coordinate extents are too large!!!"** wall (per the cited Source SDK threads). That hard wall is the thing people are half-remembering when they treat "20k" as a limit.

Takeaway: **"20k x 20k" is a remembered Source-1 constraint, not an s&box rule.** Treat it as history to be translated (about 416 m usable), never as a spec ceiling to design against.

## 3. Source 2 / s&box removed the hard coordinate wall (VERIFIED, 26.07.15a)

s&box **does not have the VBSP-style "coordinates too large" wall**, and this is now measured, not assumed (verified on 26.07.15a). A GameObject placed at **16,384 u** (the old Source-1 half-extent), **100,000 u**, **787,400 u** (20 km), **10,000,000 u**, and **-787,400 u** along one axis is accepted without error or exception, stores finite values (no NaN/Inf), and reads its position back **exactly**. Every probe value is an integer below 2^24, so fp32 represents it exactly: any clamp, wrap, or rejection would have surfaced as a readback mismatch, and none did. Physics works out there too: a ray trace against a collider spawned at 787,400 u hits its analytic surface point with zero measured error (section 4's table).

There is no fixed coordinate cube you get bounced out of. World size is not gated by a hardcoded extents check; it is gated by the *soft* fp32-precision behavior in section 4 and by your runtime budget (section 6). Practically: you will not hit a "too large" error by making a big runtime-generated world in s&box. What changes far out is float granularity, and as section 4 measures, that change is gradual and far smaller than folklore claims.

## 4. The real modern limit: float precision from origin (MEASURED, 26.07.15a)

The modern ceiling is **32-bit float precision coarsening with distance from the origin (0,0,0)**, not a coordinate box. On 26.07.15a this is now a measured curve, not a repeated rumor. Positions are stored as **plain fp32**: at every distance tested, the smallest representable position step (set a position to a base value plus a growing epsilon and read it back until the stored value changes) **exactly equals the theoretical fp32 ULP** at that magnitude. No extra quantization, no hidden double-precision.

Measured position quantum vs distance from origin (26.07.15a):

| Distance from origin | In units (39.37 u/m) | Measured position quantum | In real terms |
|---|---|---|---|
| 1 km | 39,370 u | 0.00390625 u | ~0.1 mm |
| 4 km | 157,480 u | 0.015625 u | ~0.4 mm |
| 8 km | 314,960 u | 0.03125 u | ~0.8 mm |
| 16 km | 629,920 u | 0.0625 u | ~1.6 mm |
| 20 km | 787,400 u | 0.0625 u | ~1.6 mm |

Ray traces against a collider spawned at each of those distances hit the analytic surface point with **zero measured error** (at exactly-representable coordinates). Read the table in human terms: at 20 km from origin, the position grid is about **1.6 mm** coarse. That is position-*storage* granularity, orders of magnitude below anything a player can see on typical content.

**The famous visibility thresholds are lore, and static measurement could not reproduce them.** Community sources report faint defects past roughly 8 km and very noticeable ones past roughly 20 km (unverified, web-sourced; see Sources). A static render probe on 26.07.15a (an identical camera-plus-box arrangement rendered near origin, at 8 km, and at 20 km; consecutive-frame and cross-distance pixel diffs computed programmatically) found:

- **no temporal jitter above the renderer's flat dither floor** (max channel delta 5/255 between consecutive static frames, identical at origin and at 20 km; the floor does not grow with distance);
- **no visible geometric displacement at distance**: the 20 km arrangement differs from the origin control by at most 10/255 on any channel with zero pixels above 16/255, i.e. a subtle shading shift, not wobble.

What those measurements deliberately do NOT cover, and where the lore may still hold (unverified): a **moving camera in a published build**, physics **resting jitter under live simulation**, and **skeletal animation** far from origin. Camera/render-space precision under motion is a different mechanism from position storage; treat the 8 km / 20 km figures as unconfirmed community lore about that mechanism, not as measured engine behavior.

Watch the trap in the 20 km figure: **"20 km" is meters (~787k units), and it *also* reads as "20k"** if you drop the "m". This is a *second, independent* source of the "20k" confusion from section 1: the lore's danger distance (20 km) and one reading of the world-size spec (20,000 m) collide on the same "20k" shorthand while being the same underlying number, and both are utterly different from "20,000 units" (508 m). If anyone cites "20k" near a precision discussion, pin down meters-vs-units before believing it.

Design consequence: **keep gameplay near origin anyway.** It costs nothing and buys headroom. But the measured curve says the pressure is mild: a 508 m (20,000-unit) world has a position quantum of about 0.002 u (~0.05 mm), and even 20 km out the storage quantum is ~1.6 mm. Only genuinely planet-scale worlds (hundreds of thousands of units of *gameplay* range) need origin-rebasing / floating-origin tricks, and the first thing to actually test there is moving-camera rendering, not position storage.

## 5. The 16,384 edict cap is Source-family history; s&box has no edict cap (SOURCE-VERIFIED)

There is a separate **16,384** figure that gets conflated with world size: the **networked-entity (edict) cap**. That cap is real in *older Source-family engines* (Counter-Strike 2 is cited at 16,384 edicts plus 16,384 server-only entities on the cited VDC page; presented here as history). **It does not exist in s&box.** Source-verified against the public engine source (Facepunch/sbox-public):

- s&box's scene networking has **no edict table**. Networked objects are keyed by **Guid**, not by an index into a fixed-size slot array: `engine/Sandbox.Engine/Scene/Networking/NetworkObject.cs` (`internal Guid Id => GameObject.Id;`).
- **No cap constant exists**: repo-wide searches for `MAX_EDICTS`, `MaxEntities`, and "entity limit" return zero hits in the engine source.
- The only 16,384 in the scene layer is an unrelated bit flag, `GameObjectFlags.NoInterpolation = 16384` (`1 << 14`), in `engine/Sandbox.Engine/Scene/GameObject/GameObject.Flags.cs`. Do not mistake a grep hit for a cap.

The practical ceiling on networked-object count in s&box is bandwidth and snapshot cost, not a hardcoded number. Confidence nuance: this is *source-verified* (pinned engine source), not verified by live-spawning 16k+ networked objects; a published-build saturation test remains open for anyone who needs the *felt* ceiling.

The original point stands and is now sharper: the folklore cap was an **entity-count** limit, never a **spatial** one, and in s&box it is not a limit at all. Two different 16,384s float around: the Source-1 *coordinate* half-extent (section 2, a distance in units, historical) and the *edict* cap (section 5, a count of entities, historical). Do not let either masquerade as an s&box sizing rule.

## 6. Practical scaling for runtime-generated terrain (the felt caps)

For a **runtime-generated heightfield/voxel world** (the [runtime terrain meshing guide](/guides/runtime-terrain-meshing) architecture), the binding costs are not the coordinate limits above at all. They are, in shape (verified composition of that guide's measured 26.07.15 numbers, which are NOT restated here):

- **Regeneration CPU scales with cell-count squared** (`WorldSize^2`). This is the felt cap, the one that stalls a boot/rebuild.
- **Triangle budget tracks cell count, not footprint.** A world's tri count is set by how many cells it has, not how many meters it spans.
- **Grain (meters per cell) buys footprint at zero regen/triangle cost.** Coarsening the cell size enlarges the physical world for free; the only thing that grows is the visible facet size. The lever's ceiling is the facet size you can visually tolerate, not performance.

The payoff for this guide's purpose: **the folklore "20k x 20k" world is comfortably reachable by a runtime-generated world in-budget today.** A **1280-cell grid at 0.4 m grain is 512 m per side, about 20.1k units** (1280 x 0.4 m = 512 m; 512 m x 39.37 = ~20,157 u). That is inside the runtime terrain meshing guide's proven density ladder AND nowhere near any measured precision concern (at ~20k units the measured position quantum is about 0.002 u, ~0.05 mm; section 4's table). So "can we even build 20k x 20k?" is answered: yes, and it is not near either the perf ceiling or the precision ceiling.

For the exact cost formulas, the trade table, the proven density ceiling (1280^2), and the gen-time comfort bar, read the [runtime terrain meshing guide](/guides/runtime-terrain-meshing) "Sizing a bigger world" section directly. This guide deliberately does not duplicate those numbers.

## 7. Two things that do NOT scale with world size (replicate-the-seed architecture)

In a deterministic **replicate-the-spec** world (the [networking methods guide](/guides/networking-methods) spec-replication pattern: replicate the generator spec + edit log, each client regenerates its own world locally), two costs stay flat as the world grows:

- **Network cost is world-size-independent.** You ship a small generator spec plus the edit log, not geometry. A 508 m world and a 1 km world cost the same on the wire because clients regenerate locally from the seed; the map never travels.
- **A fixed-size minimap downsample stays fixed.** Downsampling the grid to a constant-resolution minimap texture costs the same regardless of footprint; a bigger world just means each minimap texel covers more meters.

So the sizing decision is a *local CPU/GPU/precision* decision (sections 4 and 6), not a bandwidth one. Bigger worlds do not tax the network in this architecture.

## How these numbers were measured (reproduction notes)

Engine build **26.07.15a**, measured **2026-07-18**, in an open editor in EDIT mode, driven over the editor test harness (the pattern in the [agent-test-harness guide](/guides/agent-test-harness)). Three instruments:

1. **Coordinate-extent probe (section 3).** Create a GameObject; for each probe distance (16,384 / 100,000 / 787,400 / 10,000,000 / -787,400 u along one axis) set its world position, read it back, and assert the readback is finite and exactly equal. All probe values are integers below 2^24 and therefore exactly fp32-representable, so any clamp, wrap, or rejection would surface as a mismatch. Result: accepted and exact at every distance.
2. **Precision-quantum probe (section 4).** For each distance (1/4/8/16/20 km, converted at 39.37 u/m) set the world position to the base value and read it back; then add a doubling epsilon (starting at 1e-5 u, far below any plausible quantum) until the readback changes. The first changed readback minus the base readback is the smallest representable position step at that magnitude. Assert it equals the theoretical fp32 ULP, 2^(floor(log2(base)) - 23). Also spawn a 50 u box collider at each distance and ray-trace vertically through its center: hit-position error vs the analytic surface point was 0 at every distance. Result: every measured quantum equals the fp32 ULP (section 4's table).
3. **Static render probe (section 4's lore check).** Spawn an identical dev-box arrangement near origin, at 8 km, and at 20 km (station coordinates congruent mod 8192 so any world-grid phase matches; camera aimed upward so only skybox and box are in frame; selection cleared; one settle frame discarded), capture 3 consecutive 1280x720 editor-viewport frames per station, and pixel-diff programmatically (per-channel absolute-difference histograms). Result: temporal diffs capped at 5/255 everywhere with no growth by distance; cross-distance diff at 20 km capped at 10/255 with zero pixels above 16/255.

The probes live in the editor test harness as repeatable cases, so every future engine build can re-run them and catch regressions.

Still open, and honestly framed as lore in the text: **moving-camera / published-build** render behavior at distance, physics **resting jitter under live simulation**, skeletal **animation** far from origin, and a live **networked-object saturation** test (section 5 is source-verified instead). None of those is asserted as engine behavior anywhere above.

## Sources (web-sourced and engine-source claims)

- Facepunch/sbox-public engine source (Guid-keyed scene networking, absence of any edict cap): [github.com/Facepunch/sbox-public](https://github.com/Facepunch/sbox-public)
- s&box on the Valve Developer Community (units, precision-from-origin, general engine lineage): [developer.valvesoftware.com/wiki/S&box](https://developer.valvesoftware.com/wiki/S&box)
- Facepunch Forum, "Map max size?" (s&box map extents plus the ~8 km / ~20 km precision thresholds): [forum.facepunch.com/t/map-max-size/246750](https://forum.facepunch.com/t/map-max-size/246750)
- Source SDK, "Map coordinate extents are too large!!!" (the VBSP-era hard wall): [thread one](https://steamcommunity.com/app/211/discussions/0/611702631217140650/) and [thread two](https://steamcommunity.com/app/211/discussions/2/351660338721861297/)
- Mapcore, "Source SDK limitations" (the 16,384 usable / 4,096-from-center coordinate lore): [mapcore.org/topic/20080-source-sdk-limitations](https://www.mapcore.org/topic/20080-source-sdk-limitations/)
- Valve Developer Community, "Entity limit" (the 16,384 edict / server-only entity cap): [developer.valvesoftware.com/wiki/Entity_limit](https://developer.valvesoftware.com/wiki/Entity_limit)
