---
title: Vehicle audio -- engine loops, RPM crossfade, slip SFX
slug: vehicle-audio
date: "2026-07-16"
updated: "2026-07-16T17:00:00-04:00"
lanes:
  - audio
  - writing-gameplay
tags:
  - audio
  - vehicles
  - sound
summary: >-
  The method for vehicle engine audio that doesn't screech: two-layer RPM
  crossfade with narrow pitch bands, code-side looping, slip-driven skid
  feedback, and the persistent ConVar trap that ate two listen tests.
sourceRev: methods/vehicle-audio.md
relatedFixes: []
unverified: false
---

The method for vehicle engine audio that does not screech: two-layer RPM
crossfade with narrow pitch bands, code-side looping, a slip-driven skid
feedback loop, and the persistent ConVar trap.

## Core facts (engine behavior)

- **SoundEvent has no loop flag.** A looping sound is held code-side: keep the
  `SoundHandle`, update `handle.Position` every frame to follow the emitter,
  and re-trigger (`Sound.Play(...)`) the moment `!handle.IsPlaying`. A longer
  source sample makes the re-trigger seam rarer.
- **`Sound.Play` needs the full resource path INCLUDING the `.sound`
  extension** -- `Sound.Play("sounds/engine_idle")` silently fails;
  `Sound.Play("sounds/engine_idle.sound")` works.
- Pipeline: `.mp3` source + a minimal `.sound` event resource next to it; the
  editor's asset watcher compiles both (`.vsnd_c`/`.sound_c`, gitignored).
  128 kbps mono is fine for a positional game loop.
- Free recordings: freesound CC0 **preview MP3s download without OAuth**.
  License hygiene matters in a public repo -- CC0 > CC-BY (+ATTRIBUTION.md) >
  everything else; reject NC/ND and "no redistribution" packs.

## Engine audio that doesn't screech (the two-layer recipe)

**Never pitch one loop across the whole RPM range.** Mapping idle-to-redline
onto pitch 0.8-2.0 doubles frequency at redline -- chipmunk, instantly
rejected. Narrowing to 0.7-1.3 still sounds synthetic. One sample stretched
is one sample stretched.

The recipe:

1. **Two REAL recorded layers** -- a deep idle/low-RPM loop and a
   rev/high-RPM loop, ideally from the same recording session so timbre
   matches across the blend.
2. **Equal-power crossfade by normalized RPM `t`**: low layer fades 1->0
   across t=[0.0, 0.7] (smoothstep), high layer 0->1 across t=[0.3, 1.0],
   then normalize so `lowGain^2 + highGain^2 = 1` -- combined loudness stays
   steady through the overlap.
3. **Each layer pitch-shifts only a NARROW band** around its recorded pitch
   (low 0.9-1.25, high 0.85-1.2). Because each layer's extreme pitch falls
   where that layer is nearly silent, nothing is ever heard far from how it was
   recorded. This constraint is the entire anti-screech mechanism.
4. **Per-class data on the definition**: `EngineSoundEvent` (+ optional
   `EngineSoundEventHigh`; absent = legacy single-loop path) and
   `EnginePitchBase` multiplying the band (truck 0.85 sits deep, kart 1.2
   keeps its whine). One code path serves a whole roster.
5. Volume rides throttle from an idle floor (~0.55, so a coasting vehicle
   stays audible) to full.

## Slip-driven skid loop (traction-loss feedback)

Per-vehicle (not per-wheel) is fine for a first pass. Intensity = max over
grounded wheels of `max(|SlipRatio|, |SlipAngle| / 0.7rad)` -- catches
wheelspin/lockup AND lateral slides/handbrake.

Silent below ~0.40; volume 0->0.9 and pitch 0.90->1.15 ramp to ~1.10;
`handle.Stop(0.12f)` fade on release. Same code-side loop pattern as the
engine sound.

## The trap that ate two listen tests

A **dev-override ConVar left set on a machine persists across sessions and
code reworks** and silently forces the old loop on every vehicle -- code green,
compile green, feature inaudible.

Warn loudly at component start whenever a non-default override is active, and
grep the console for the resolved-event log line BEFORE regenerating assets
when a listen test reports "nothing changed."
