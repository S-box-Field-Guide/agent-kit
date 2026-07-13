---
title: Part-kit assets — manifest-driven multi-part assembly
slug: part-kit-assembly
date: "2026-07-13"
updated: "2026-07-13"
lanes:
  - getting-art-in
  - writing-gameplay
tags:
  - assets
  - pipeline
  - vehicles
  - assembly
summary: >-
  The higher-order asset layer for kits of parts (vehicles, procedural
  buildings): the generator emits a manifest next to the meshes, code consumes
  ONLY the manifest, pivots sit at joints, collision comes from metadata, and
  assembly is transactional.
sourceRev: asset-pipeline.md#part-kit
relatedFixes:
  - model-no-collision
  - model-imported-wrong-facing
  - scaled-collider-didnt-scale
  - sbox-wont-load-obj-glb
  - obj-export-face-order-nondeterministic
  - sbox-units-are-inches
unverified: false
---

The higher-order layer on the art pipeline for assets that are **kits of parts**
(vehicles from chassis/wheels/doors; procedural buildings) rather than one fused
mesh.

**The contract: the generator emits a `manifest.json` next to the meshes, and
code consumes ONLY the manifest** — never inferred render bounds.

## 1. Pivots at joints

Author each part with its pivot AT its joint: wheels at hub centre, doors on the
hinge line, bumpers at the mount plane, buildings at footprint-centre@ground.
Detach/hinge/spin later = transform math around an origin that is already
correct.

## 2. Manifest records real-world meters

Per part, in real-world meters: the backing vmdl path, a semantic `kind`,
`pivot_semantics`, `rotation_axis_local`, `dims_m`, local bounds, the attach
point in the AUTHORING frame (`attach_author_m`), and a suggested
`mass_fraction` (unused until parts detach and need their own rigidbodies).

For buildings the same idea for placement: footprint, collision height, front
axis, door centre + door-clearance rectangle. Generate a C# catalog from it so
code never parses paths at runtime.

## 3. Kit vmdls are render-only

No physics shapes on the kit meshes. Code composes simple `BoxCollider`s from
`dims_m` / footprint+height at assembly time: box colliders sized from the
manifest are cheaper and cleaner than per-poly hulls, and never drift from the
placement contract. Do NOT infer collision from decorative render bounds and do
NOT add an indiscriminate concave collider — see
[model-no-collision](model-no-collision) and
[scaled-collider-didnt-scale](scaled-collider-didnt-scale).

## 4. Position through ONE tested frame mapping

Position from `attach_author_m` through a single, empirically proven
author→model-local mapping. The instructive failure: a mapping AND yaw that are
both 180° off cancel in POSITION and add in ORIENTATION — every pivot lands
world-correct while every mesh sits spun in place. So the conversion constants
and the facing yaw must always flip together, and **position-correctness alone
proves nothing about frame-correctness** — verify facing with a screenshot + an
asymmetric-feature probe. See
[model-imported-wrong-facing](model-imported-wrong-facing).

## 5. Assembly is transactional

Preload/validate every required model BEFORE creating any GameObject; on any
required-part failure create NOTHING and fall back to the fused/blockout path —
a broken kit must never brick a spawn or ship a half-assembled compound
collider. Distinguish required (structural/collision-bearing) from optional
(cosmetic) kinds. Validate the manifest strictly at load (schema version, finite
length-3 arrays, min ≤ max bounds, exactly the expected wheel/part set) so a
parseable-but-truncated JSON is rejected at `TryLoad`, not thrown at spawn.

## 6. Mirror the validator offline

A dependency-free twin of the C# rules (python or otherwise), run against the
generator's output + malformed fixtures, with a LOCKSTEP comment on both sides —
the generator gets a CI gate without a headless C# test runner.

## 7. Loose JSON under Assets/

Readable via `FileSystem.Mounted` in-editor (`Json.Deserialize` with DTO
property names byte-matching the JSON keys, zero serializer attributes). Whether
loose json ships in a packaged build is a packaging question to re-verify —
dev-host streaming to a joiner does NOT send loose files.

## 8. Animated sub-parts mount on live simulation state

Reuse the existing visual component: put animated channels on an identity-based
"Visual" GO under the physics part, with kit-specific alignment as a static
child below it — the shared visual stays byte-identical for fused and kit paths.

## 9. Version the manifest schema

Normalize old versions at load. Additive optional fields need no bump. Same
append-only discipline as every other spec in the house — and the same spirit as
[delta-log save](/guides/delta-log-save) and
[spec-replication networking](/guides/networking-methods).

Units reminder: author in meters, convert once at the engine boundary —
[sbox-units-are-inches](sbox-units-are-inches).
