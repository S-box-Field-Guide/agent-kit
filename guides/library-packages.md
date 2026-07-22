---
title: "Library packages: extraction and consumption"
slug: library-packages
date: "2026-07-19T11:20:00-04:00"
updated: "2026-07-21T23:50:00-04:00"
lanes:
  - tooling-environment
  - building-ui
tags:
  - library
  - vendoring
  - csproj
  - refactor
summary: >-
  How to split reusable code out of a game into an s&box Library package, and
  how to consume one from a game, without silently losing content, binding the
  wrong types, or shipping divergent assets.
verifiedOn: "26.07.18"
sourceRev: methods/library-packages.md
relatedFixes:
  - razor-tag-resolution-ignores-global-usings
  - library-seam-must-cover-every-side-effect
  - offline-two-assembly-compile-gate
changelog:
  - { date: "2026-07-19", note: "Published" }
  - { date: "2026-07-21", note: "Added versioning & consumer-update model (version-pinned installs, no auto-update, update-time breakage surface)." }
---

How to split reusable code out of a game into an s&box Library package, and how to consume
one from a game, without silently losing content, binding the wrong types, or shipping
divergent assets. Verified on engine 26.07.18 on a real library-inversion flip: a game
consuming Library packages, gated by an offline two-assembly `dotnet build`
(0 warnings 0 errors) plus content diffs.

## Platform facts

- **Libraries are SOURCE-distributed.** A consumed library's C#/razor/assets compile inside
  the consumer's build; there is no prebuilt-binary distribution for game consumption.
- **Consumed libraries land under the project's `Libraries/` folder.**
- **Each library folder must contain exactly ONE library-type `.sbproj` or the editor
  silently skips it.** Discovery scans `Libraries/*` at project load only; a folder with
  zero (the hand-vendored case) or multiple `.sbproj` files never becomes a library
  project, and the game compile fails CS0246 on every library type. Hand-vendored kits
  need a minimal `{"Title", "Type": "library", "Org", "Ident", "Schema": 1}` project file
  added, and a LIVE editor must be closed and reopened to pick it up (hot recompile does
  not rescan). Once discovered, local libraries are auto-referenced; no
  `PackageReferences` entry needed.
- **No library-to-library references.** A library cannot consume another library; anything
  shared across libraries must be duplicated or folded into one.
- **Publishing goes through the editor's Library Manager** (same package pipeline as games,
  library package type).

## Versioning and consumer updates

- **Consumers are version-pinned; there is NO auto-update.** Installing a library records an
  exact revision (`LibrarySystem.Install(fullIdent, VersionId)` in the engine's Library Manager
  source, verified 26.07.15a). A newer published revision only surfaces as an **"Update"** button
  the consumer must press, and a version dropdown lets them install ANY revision including older
  ones — rollback is built in. Publishing a new library revision therefore **cannot silently
  break existing consumers**.
- **Players are insulated one layer further.** Libraries are source-distributed, so the kit code
  compiles INTO the consumer's published game package. A game's players see a kit change only
  after that game's developer updates the library AND republishes the game.
- **The real breaking-change surface is update-time.** When a consumer presses **Update**,
  renamed or removed public API fails THEIR compile, and any hand-edits they made inside the
  library folder are overwritten. Release discipline follows: additive-first API, migration notes
  in the CHANGELOG for anything breaking, and README guidance to customize via **seams** rather
  than by editing kit files.

## Vendored-copy canonicality

When a game vendors a library's source (instead of or in addition to package consumption),
the vendored copy must stay BYTE-IDENTICAL to its canonical upstream. Never fix a
consumption problem by editing vendored files; every technique below exists so the fix can
live on the consumer side:

- **Name collisions:** pin with a `global using` alias in the game's `Assembly.cs`, never a
  rename inside the library. Enclosing-namespace members beat compilation-unit aliases, so
  library files are untouched by the game's aliases.
- **Behavior differences:** wrap the library's seam on the consumer side, never patch the
  library path (see seam inventory below).
- **Asset differences:** override paths on the game side (see byte-identity below).

Verify canonicality mechanically: content-diff the vendored tree against upstream at vendor
time and on every sync (URL + commit of the upstream in the vendor manifest).

## The extraction/consumption checklist

### 1. Split before you delete

A game file that defines a now-library-provided type often ALSO carries game-only content
(a tuned data roster, constants, extension members in the same file). Deleting the file
because "the library provides it" drops that content silently; the compile stays green when
shapes match. Split game-only content into its own file FIRST, then delete only the true
duplicate, and content-diff the deletion against what the library provides (every deleted
hunk must exist in the library).

### 2. Pin every surviving name collision, even when the build is green

If the game keeps a type whose simple name collides with a library type of compatible
shape, both bindings are legal and the compiler warns about nothing; a green build does not
tell you which type your code is using. Add a `global using X = Game.Namespace.X;` alias
for every such name as a matter of policy. The loud variants of this trap (CS0104, CS0234
namespace-vs-class) at least fail; the same-shape variant is silent.

### 3. Inventory the seam's side effects

An extraction seam (a delegate that swaps one behavior, e.g. a body builder) usually
carries only the headline behavior. List EVERY side effect of the replaced code path
(visual mounting, data-driven transforms, perf timing, audit/log lines, registrations) and
reproduce the missing ones in a consumer-side wrapper. Physics note: part colliders shift
the inertia tensor, so assembly differences move telemetry — they are not cosmetic.

### 4. Byte-identity discipline for colliding asset paths

A vendored library shipping assets at the same bare resource path as the game's own copies
is behavior-neutral ONLY if every colliding file is byte-identical (`cmp`/hash the pairs,
including the whole reference chain: a `.sound` and the audio it points at). If any pair
differs, the game must override/re-point its paths. Re-run the sweep on every vendor sync.

### 5. Razor consumers need explicit @using

Razor component TAG resolution ignores `global using`: every `.razor` file rendering
library components needs explicit `@using` lines for those namespaces, and `RZ10012` must
be treated as an error in review (it is a warning that silently renders a plain element).

## The offline two-assembly compile gate

When no editor-generated csproj exists (fresh worktree) or the live editor cannot be
touched, gate the whole stack headlessly:

1. Write a scratch csproj per assembly (library and game), SDK `Microsoft.NET.Sdk.Razor`
   so `.razor` files compile, referencing the editor install's prebuilt `Base Library.dll`
   by absolute path.
2. `<GenerateAssemblyInfo>false</GenerateAssemblyInfo>` plus a FRESH `obj` directory per
   build (dodges `CS0579` duplicate assembly attributes from stale generated info).
3. Build the LIBRARY assembly first; then build the GAME assembly referencing the produced
   kit dll. This mirrors the consumption topology the editor creates.
4. Gate on 0 warnings 0 errors, and treat `RZ10012` as a failure.

**Limits** (same as every headless gate): `dotnet build` compiles no SCSS, enforces no
whitelist, and proves compile-level truth only; binding intent (step 2 above) and seam
completeness (step 3) still need diffs and review. It also CANNOT catch library-discovery
failures: the scratch csproj compiles the library source directly, so a vendored kit
missing its `.sbproj` gates green offline and still fails in the editor (see platform
facts above).
