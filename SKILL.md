---
name: sbox-field-guide
description: >-
  Hard-won s&box (Facepunch sandbox game engine) field notes — verified gotchas and
  fixes we hit while shipping games. Complementary to the official docs. Use this
  skill BEFORE writing or debugging any s&box C# code, ModelDoc/material assets,
  Razor UI, or publishing config. Triggers: s&box, sbox, .sbproj, .vmdl, .vmat,
  Razor PanelComponent, SkinnedModelRenderer, Sandbox.Component, sbox.game publishing,
  "model imports upside down", "UI won't update", "whitelist violation",
  "broke after publish".
---

# s&box Agent Kit — agent skill

You are working in **s&box**, Facepunch's C# game engine. This engine has many traps
that compile clean but fail at runtime, publish, or in-editor. This skill is a
reference library of verified fixes. **Read the relevant doc before working in an area
— it will save you from re-learning a gotcha the hard way.**

> **📌 Agents — this pack is split by lane (2026-07). Update your memory:** load `_core.md`
> **first (always)**, then the **one** `<lane>.md` pack for your task (see `index.md`). There is
> no longer a single combined gotchas file. `coverage.md` shows what's covered vs. the backlog.

## How to use this skill

1. **Always load `_core.md` first** — the handful of cross-cutting rules that cause most
   failures. It's tiny; read it every time.

2. **Then load the one lane pack for your task** (loaded on demand — never read them all).
   See `index.md` for the full lane map and gotcha counts.

   | If you're working on… | Lane pack | Deeper narrative guide |
   |---|---|---|
   | New project / scene / build setup | `getting-set-up.md` | `guides/agent-buildable-project-setup.md` |
   | Blender → s&box models, materials, units, axes | `getting-art-in.md` | `guides/part-kit-assembly.md`, `guides/world-scale-and-coordinate-limits.md` |
   | Rig / animate / retarget | `rigging-animation.md` | `guides/character-mounted-assets-live-tuning.md`, `guides/ragdoll-physics.md` |
   | Gameplay C# — components, movement, save, networking, runtime meshes | `writing-gameplay.md` (router → `writing-gameplay--*.md`) | `guides/networking-methods.md`, `guides/p2p-peer-hosted-servers.md`, `guides/parkour-movement.md`, `guides/delta-log-save.md`, `guides/runtime-terrain-meshing.md`, `guides/decals.md` |
   | Razor UI / HUD | `building-ui.md` | `guides/first-person-viewmodel.md` |
   | Sound events | `audio.md` | `guides/vehicle-audio.md`, `guides/voice-proximity-chat.md` |
   | Perf / collider choice / density | `making-it-perform.md` | `guides/performance-investigation.md` |
   | Publishing to sbox.game | `publishing-shipping.md` | `guides/library-packages.md` |
   | Coordinating agents to build a game | `ai-assisted-workflow.md` | `guides/agent-buildable-project-setup.md`, `guides/agent-test-harness.md` |
   | Blender CLI / python generators / dotnet / encoding traps | `tooling-environment.md` (router → `tooling-environment--*.md`) | — |
   | Arcade vehicles | `writing-gameplay.md` | `guides/vehicle-physics.md`, `guides/vehicle-audio.md`, `guides/part-kit-assembly.md` |

   `index.md` lists every guide file with a one-line description.

3. **`coverage.md`** is the human view of what's covered vs. the backlog. Lane packs are
   scan-first checklists; the deeper narrative guides give worked examples.

4. **Respect the recurring rules** that cause most failures:
   - **Units are inches** (1 m = 39.37 u). Do math in SI, convert at the engine boundary.
   - **`dotnet build` does NOT enforce the s&box whitelist.** A clean build can still be
     rejected at runtime (`Environment.*`, `System.IO`, `Process`, reflection → SB1000).
     Sweep new code for these before claiming it works.
   - **`BuildHash()` is the only razor re-render trigger** — hash everything the markup reads.
   - **Colliders don't all follow `WorldScale`** — Box does, Capsule/Model don't.
   - **New assets/inputs need an editor kick or Play restart** — a headless build won't
     surface them.
   - **"Verified in-editor" ≠ "works after publish"** — the whitelist and loose-resource
     rules diverge at publish time (see `publishing-shipping.md`).

5. **Verify, don't assume.** After changes, `dotnet build` for compile, then confirm
   runtime behavior in the editor (or via the editor MCP if available) — many of these
   traps only show up at runtime. The editor MCP port is not fixed: it is one
   engine-global preference with no auto-increment, so discover the live port rather
   than hardcoding one (`tooling-environment--editor-mcp.md`).

## What this skill is not

Not a general C# or Blender tutorial, and not a substitute for the official Facepunch
API docs — it's complementary field notes from shipping s&box games. Pair it with the
wiki/API docs; load this pack so you don't rediscover the same traps.
