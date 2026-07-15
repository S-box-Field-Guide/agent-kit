---
title: "Performance investigation — the measure-first harness"
slug: performance-investigation
date: "2026-07-15T00:45:00-04:00"
updated: "2026-07-15T00:45:00-04:00"
lanes:
  - making-it-perform
  - tooling-environment
tags:
  - performance
  - profiling
  - fps
  - measurement
summary: >-
  A disciplined method for answering "the game feels slow" in an s&box project
  without shipping speculative optimizations — environmental pre-checks,
  measurement tooling, an isolation matrix, and a verdict discipline that
  prevents wasted work.
sourceRev: "cd7f71b6d866"
relatedFixes:
  - editor-embedded-play-capped
  - stale-assembly-hotload
unverified: false
---

How to answer "the game feels slow" in an s&box project WITHOUT shipping speculative optimizations. This method was proven end-to-end: a report of "really low FPS in play mode" led to a compelling hypothesis (per-frame shadow-casting sun rotation over hundreds of casters), but measurement refuted it (locked 60 fps at 6.4x default load). The real cause was an environmental asset-recompile storm that prevented play mode from initializing at all. The fix was clearing the storm, not touching the renderer.

## 0. Environmental pre-checks BEFORE believing any FPS number

A "slow game" report is often not the game. Check, in order:

1. **Is the editor itself healthy?** An asset-recompile storm (console saturated with "On-demand recompile of asset" / dependency churn), a huge working set, or a wedged-but-alive process starves play mode. In one case, play mode never initialized (a frame-counter probe read `frames=0`) while 1600+ orphaned baked assets re-queued forever. Clear the storm first (remove/move stale assets OUT of the watched `Assets/` tree, restart the editor); re-test before profiling anything.
2. **What happened just before the report?** Mass asset operations (bakes, imports, batch compiles) leave the editor grinding for 15-20+ min afterwards. That grind IS the slowness.
3. **Know your ceiling:** windowed editor play mode is DWM/monitor vsync-capped (typically 60 Hz). `fps_max 0` does not lift it. A wall-clock FPS probe can only detect problems that drop BELOW the cap; "60.0 everywhere" means "no problem at this load," not "no cost anywhere."

## 1. Measurement tooling (build once, keep forever)

Build a minimal per-frame sampler and a read-only editor tool to query it:

- **Game assembly:** a tiny per-frame sampler component (frame count + frame-ms ring buffer producing avg / p1-low / p99), publishing through a static bridge pattern (game writes, editor reads, no editor-to-game coupling). Include a `gameLive`/staleness flag so the tool can distinguish "play mode never started" from "0 fps."
- **Editor assembly:** a read-only MCP tool returning JSON: the FPS block PLUS a scene census — renderer counts split by category (terrain/water/props/creatures), shadow-casting renderer count, collider count, light count + how many shadowed directionals, total GameObjects. The census is what turns a number into a diagnosis.
- Gate the tooling like any code: headless build + in-editor compile check. It is additive and read-only, so it can merge to main and stay permanently.

## 2. The isolation matrix (design cells before measuring)

Write a protocol doc FIRST: a table of cells where each cell isolates ONE variable, and a mapping from each ranked hypothesis to the cell pair that confirms/refutes it.

Typical axes:
- Edit vs play mode
- World size variants
- Content style/variant
- Each dynamic system pinned vs running (day/night, weather)
- Population dials at 0 / default / max
- Camera mode

Two disciplines that save time:
- **Run the decisive cell pair FIRST** (the one that settles hypothesis #1), not the whole matrix in order.
- **A maximal "everything on" cell can retire many lighter cells at once**: if the MAX cell holds the vsync cap, every lighter isolate is a foregone pass — record them as skipped-with-reason.

Sample at least 20 seconds per cell; record avg / p1 / p99 + the full scene census per row; commit the filled-in results table into the protocol doc so the numbers are citable later.

## 3. Code recon in parallel (hypotheses, not fixes)

While tooling builds, audit from code with file:line evidence:

- Every `OnUpdate` / `OnFixedUpdate` (flag anything O(world) or O(collection) per frame)
- Shadow-casting flags and whether any shadowed light's transform is written per frame
- Material instance copies (`CreateCopy` per chunk/object breaks batching)
- Collider counts and whether anything moves them
- Translucent overdraw surfaces
- Any per-frame string/JSON work on networked fields

Rank hypotheses: (evidence, expected win, cost/risk, which matrix cells decide). Check the project's own history first — a prior density/budget study may already have proven the static scene fast, which re-aims suspicion at what landed after it.

## 4. The verdict discipline (the part that keeps you honest)

- **No reproduced sub-cap regression means NO fix ships.** Findings that measurement absorbs (e.g., a per-frame sun-rotation write that the frame budget eats) get a READY-TO-APPLY recipe documented in the protocol doc instead — applied only when a real sub-cap case appears (weaker client, uncapped/standalone run, dedicated server).
- If a fix DOES ship: prove the recovery with the same cell pair (before/after), plus a same-pose visual pair when the fix could affect visuals, plus the project's standard determinism/regression gates.
- Bank BOTH outcomes: a refuted plausible hypothesis is knowledge (it stops the next person from "optimizing" it), and the environmental cause is usually the more useful article.
