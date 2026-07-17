---
title: Standing up an agent-buildable s&box project
slug: agent-buildable-project-setup
date: "2026-07-13"
updated: "2026-07-13"
lanes:
  - getting-set-up
  - ai-assisted-workflow
tags:
  - setup
  - agent-workflow
  - tooling
summary: >-
  The build order for a fresh s&box project a coding agent can actually work in
  without corrupting itself on day one — skeleton, globals, compile gate, and the
  ownership discipline that keeps parallel agents from clobbering each other.
verifiedOn: "26.07.15a"
sourceRev: seed-2026-07-13
relatedFixes:
  - project-setup-skeleton
  - sbproj-title-ident-startup
  - assembly-cs-globals-setup
  - package-references-clean-start
  - first-play-compile-checklist
  - dotnet-build-misses-razor-errors
  - agent-file-ownership-discipline
  - ai-agents-build-game-in-a-day
unverified: false
---

Most "the agent broke my project" reports on day one aren't gameplay bugs — they're
setup gaps. A coding agent will happily generate a hundred files against a skeleton
that silently won't compile, won't hot-load, or whose `.sbproj` identity keeps
resetting. This guide is the order to stand a project up so an agent (or a team of
them) can build in it safely. Each step links the fix that explains the trap in full.

## 1. Lay the skeleton, not just the folder

Create the project through the editor so the `.sbproj`, `Assets/`, and `Code/`
layout match what the compiler and packager expect — a hand-rolled folder tree
compiles locally and then fails on publish. Get the canonical layout right once.

Traps: see [project-setup-skeleton](project-setup-skeleton) for the folder contract,
and [sbproj-title-ident-startup](sbproj-title-ident-startup) — set the title and
`Ident` before first launch, because changing the ident later orphans everything
keyed to it.

## 2. Pin the compile boundary before any code

s&box compiles your code against a whitelist, and `dotnet build` at the terminal
does **not** enforce the same rules the editor does. Decide your build gate now:
the editor's hot-load is the source of truth, and a green terminal build is not a
green project.

Traps: see [dotnet-build-misses-razor-errors](dotnet-build-misses-razor-errors) —
Razor/`.razor` errors don't surface in a plain `dotnet build`, so an agent that
trusts the CLI exit code will report "done" on a project that won't load. Wire your
[package references clean](package-references-clean-start) before the first sync so
the assembly graph is deterministic.

## 3. Establish globals and services wiring

Set up your assembly-level globals and service access once, at the root, so every
component the agent writes resolves the same way. Ad-hoc `using static` and
scattered singletons are the usual cause of "works in one file, null in the next."

Traps: see [assembly-cs-globals-setup](assembly-cs-globals-setup) for the
`GlobalUsings`/`AssemblyInfo` pattern that keeps globals consistent across files an
agent generates independently.

## 4. Make the compile gate a first-class check

Before the agent writes gameplay, give it a **compile checklist** it runs after every
batch: load the project, confirm the four-object bootstrap scene comes up, and read
the editor's compile output — not the terminal's. This is the single highest-value
loop for agent-driven work: it converts silent breakage into an immediate, local
failure the agent can fix in the same turn.

Traps: see [first-play-compile-checklist](first-play-compile-checklist) for the exact
pre-play sequence.

## 5. Assign file ownership before parallelizing

The moment you run more than one agent, you need an ownership map: which agent owns
which files/systems, and a rule that no agent edits a file it doesn't own without a
handoff. Without this, two agents regenerate the same component from different
assumptions and the last writer wins — silently.

Traps: see [agent-file-ownership-discipline](agent-file-ownership-discipline) for the
ownership-map convention, and [ai-agents-build-game-in-a-day](ai-agents-build-game-in-a-day)
for how the spec/ownership/tuning split holds up across a full build.

## The contract, in one place

- **Skeleton via editor**, ident locked before first launch.
- **Compile truth = editor hot-load**, never the terminal `dotnet build` exit code.
- **Globals wired at the root**, once, so independently-generated files agree.
- **A compile checklist after every batch** — the loop that makes agent work safe.
- **An ownership map before the second agent** — no unowned edits.

Get these five right and an agent can build in the project for days without the
day-one failure modes. Everything past this point is gameplay, and gameplay bugs are
what the [fix layer](/lanes/writing-gameplay) is for.
