---
title: "Agent animation authoring: numbers for correctness, screenshots for the read, the owner for taste"
slug: agent-animation-authoring
date: "2026-08-08T14:00:00-04:00"
updated: "2026-08-08T14:00:00-04:00"
lanes:
  - rigging-animation
  - writing-gameplay
tags:
  - animation
  - authoring
  - agents
  - blender
  - workflow
summary: >-
  The division of labor for authoring s&box animation with agents: the owner
  authors hero poses in the Animate studio, agents build the motion around them
  against a numeric definition of done, and the owner taste-gates frames, never
  live sessions. Covers the pose-to-pose synthesis pattern, numeric acceptance,
  and the sequence-time traps that break freeze-at-end logic.
verifiedOn: "26.08.05"
sourceRev: methods/agent-animation-authoring.md
relatedFixes: []
unverified: false
changelog:
  - { date: "2026-08-08", note: "Published" }
---

Do not send an agent to invent organic feel from nothing. This is the division of labor that works: the owner authors the hero moments, agents build the checkable motion around them, and the owner taste-gates the result from frames.

## The division

1. **The owner authors the hero moments** in the Animate studio: end poses and key beats. A pose takes seconds and carries all the taste. The owner exports through a bit-exact Blender bridge, or hands over a reference screenshot.
2. **Agents build the motion around those poses:** the ways in and out, transitions, freezes, retargets, variants, and cleanup. All of it has a checkable definition of done. That definition is the gate between what agents can own and what they cannot.
3. **The owner taste-gates frames, never live sessions.** Agents deliver before, mid, and settled screenshots plus the numeric proof. The owner vetoes or blesses from those.

## The pose-to-pose synthesis that worked

Headless Blender is the workbench. A per-project Blender bridge script knows the skeleton dialects, and each invocation exports one prop.

Build a pose-to-pose move like this:

1. **Take the rig's own standing idle as frame one.** Never start from the bind pose. The game crossfades in from live play, and a bind-pose start visibly dips the arms.
2. **Put the authored pose at the last frame.**
3. **Key only the bones the author posed.** Adding idle to unposed bones invents motion nobody authored.
4. **Let Blender interpolate** the frames between.
5. **Keep the wrap frame on a one-shot.**

## Acceptance is numeric, written before the work

An agent claim without these numbers is a guess. Write the targets first, then measure against them:

- End pose preserved within the bridge's 0.05 degree tolerance.
- Root motion zero: pelvis delta `0.000`.
- Frame one equals the chosen start pose.
- Smooth middle: per-frame deltas with no corners.
- Duration as specified.

Screenshots carry silhouette-level judgment. Capture start, mid, and settle, and put a person or a fist in frame to turn a picture into a measurement. Screenshots do not carry weight, anticipation, or timing feel. That read stays the owner's eye, always.

## Known traps, all measured

- **A sequence's normalized time wraps at the end even with `looping=false`.** So freeze-at-end logic must latch on the wrap. Time going down between two frames of one playback means the sequence arrived. Never test `>= 1` per frame.
- **An authored "clip" may be a static two-key freeze.** Check the first-versus-last frame delta before assuming motion.
- **A frozen crossfade parks half-blended** if the park point lands inside the fade window.
- **Engine frame and Blender frame axis conventions differ per exporter.** The engine frame is the contract.

## Cheap ceiling test for a new motion class

The owner supplies one reference screenshot of the target pose. One agent reproduces it in the Animate studio and returns frames plus bone numbers. That costs one agent run and locates the taste gap exactly.
