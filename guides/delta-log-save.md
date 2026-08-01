---
title: Delta-log save for deterministic procedural worlds
slug: delta-log-save
date: "2026-07-13"
updated: "2026-07-13"
lanes:
  - writing-gameplay
tags:
  - save-load
  - determinism
  - procedural
  - networking
summary: >-
  When the world is deterministically generated from a spec, a save is
  {version, spec, edits[]} — never a geometry snapshot. Load = validate →
  regenerate → replay edits. Same format works for save, co-op edit sync, and
  late-join replay.
verifiedOn: "26.07.15a"
sourceRev: code-patterns.md#delta-log
relatedFixes:
  - saveload-without-drift
  - runtime-world-building-helpers
  - owner-simulated-networking
unverified: false
---

When the world is deterministically generated from a spec, a save is
**`{version, spec, edits[]}`** — the generator inputs plus an ORDERED log of
user edits — never a geometry/grid snapshot. Load = validate → regenerate from
spec → replay edits in order. Proven with a round-trip suite: grid hash
byte-identical across save→different-world→load, and pixel-identical
screenshots.

Companion pieces: [saveload-without-drift](https://sboxguide.dev/fix/saveload-without-drift),
[/guides/runtime-terrain-meshing](/guides/runtime-terrain-meshing) (grid as
truth), [/guides/networking-methods](/guides/networking-methods) (spec
replication + late join).

## Record at the single mutation choke point

Every edit path — UI and editor tools — funnels through ONE method. Store the
POST-clamp/normalized params so replay re-clamping is a no-op and file
validation is a plain range check. If two code paths can mutate the world, you
don't have a log — you have a race.

## Validate EVERYTHING before touching the live world

Schema version equality, spec normalization, then every edit (known op, finite
floats, in-range radius, in-bounds cells) — fail on the FIRST bad edit with its
index; a partially-valid log is a rejected load. A save that can't be validated
is a world-destroyer.

## Serialize enums as stable ints

Enum NAMES aren't a guaranteed Json round-trip in this engine; validate with
`Enum.IsDefined` on load. Keep the record's fields append-only — same contract
discipline as the spec itself.

## Suppress recording during replay

A flag reset in `finally`, and restore the log AFTER replay so re-saving
round-trips. Forgetting the suppress flag double-writes every stroke on load.

## Measure replay before building compaction

Replay cost is settle + dirty-remesh per stroke. Real authoring sessions are
often sub-second. Bake-to-snapshot is a future optimization, not a v1 feature —
don't invent compaction until measurement says you need it.

## Why it beats snapshots

Tiny on disk, versionable, and the SAME format works as:

1. **Save/load** for single-player sessions.
2. **Live co-op edit wire protocol** (post frozen-world MVP).
3. **Late-joiner replay stream** — joiner regenerates from spec, then applies
   the edit log.

One format, three jobs. Pair with the content-hash handshake from
[/guides/networking-methods](/guides/networking-methods) Part A so a desynced
replay fails loud instead of walking a wrong world.
