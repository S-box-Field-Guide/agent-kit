---
title: "Ragdoll physics — scripted-rig NPC crumple without authored collapse clips"
slug: ragdoll-physics
date: "2026-07-17T09:14:00-04:00"
updated: "2026-07-17T09:14:00-04:00"
lanes:
  - writing-gameplay
  - rigging-animation
tags:
  - ragdoll
  - physics
  - npc
  - modelphysics
  - rigging
summary: >-
  The method for making a procedurally-rigged NPC crumple via engine physics —
  author a physics skeleton in the vmdl, toggle Sandbox.ModelPhysics at runtime,
  and hand bone control back for stand-up. No authored collapse clips needed.
sourceRev: null
relatedFixes: []
unverified: false
---

The method for making a non-citizen NPC crumple, faint, and tumble via engine physics — so
a dazed/knocked-out NPC collapses physically instead of authoring collapse/faint/get-hit
clips for every body plan. The rigged vmdl carries a physics skeleton (capsule per bone +
joint graph); the engine's built-in `Sandbox.ModelPhysics` component turns it into a ragdoll
on demand and writes the simulated bones back onto the same `SkinnedModelRenderer` your
clips normally drive. Author the physics skeleton once in the rig generator and flip one
component on/off at runtime.

## When to use this (vs. authored clips, vs. ModelPhysics on a static prop)

- **Use scripted-rig ragdoll when** an NPC built on a procedural rig lane needs to collapse
  and you don't want to author collapse animations for every body plan. One physics skeleton
  per rig covers daze, knockout, death, blast-shove — all the same toggle.
- **Do not pose bones from C# to fake it.** Per-bone `SetBoneTransform` posing is
  documented-unsound; ragdoll is pure engine physics so you never touch bones by hand.
- **This IS `Sandbox.ModelPhysics`** — the same engine component the citizen ragdoll uses.
  The only difference is that you author the vmdl's physics nodes (from bone lengths)
  instead of inheriting citizen's hand-tuned prefab.

## Architecture: what drives what

```
Rig generator (offline python or tool)
   ▼ splices two nodes into the generated .vmdl
vmdl:  PhysicsShapeList (capsule per bone)  +  PhysicsJointList (joint per bone edge)
   ▼ ModelModifier_ScaleAndMirror scales physics coords WITH the mesh
compiled .vmdl_c
   ▼
RUNTIME — clip path:    SkinnedModelRenderer.Sequence drives the bones (default)
RUNTIME — ragdoll:      Enable Sandbox.ModelPhysics on the SAME GameObject
                        → builds one physics body per bone, simulates them,
                          writes results back onto the renderer's bones
```

The **one-renderer rule** makes it cheap and reversible: `ModelPhysics` and the clip
`Sequence` both write the same `SkinnedModelRenderer` bones. Ragdoll is "enable the
component"; stand-up is "destroy the component" and bone control returns to `Sequence` next
frame. **Exactly one of them may own the bones at a time** — the caller must stop writing
`Sequence.Name` while ragdolled or a per-frame Sequence write fights ModelPhysics' bone
writes.

## Part A — authoring the physics skeleton in the vmdl

### 1. Copy the schema from a working model

The **citizen** model is the canonical ragdoll reference. Two nodes go in the RootNode
children:

- **`PhysicsShapeList`** — children are `PhysicsShapeCapsule`, one per major bone:
  `parent_bone` (bone name), `surface_prop="flesh"`, `collision_tags="solid"`, `radius`,
  `point0`, `point1`. The capsule axis is in the bone's local frame.

- **`PhysicsJointList`** — one constraint per parent→child bone edge that has a shape on
  both ends. `parent_body`/`child_body` are bone names. Elbows and knees use
  `PhysicsJointRevolute` (hinge); everything else uses `PhysicsJointConical` (ball-socket
  cone). `anchor_origin` is the pivot in the parent body's local frame.

**Every joint's parent_body and child_body must have a shape** or the body floats
disconnected — which is why the neck gets its own body: it bridges chest→head, and without
it the head floats.

### 2. The units trap: author physics coords in centimetres

Physics shape coords are in the **same unit as the mesh+bones before the ScaleAndMirror
modifier**. For a metres→cm rig that means **centimetres**, and the vmdl's
`ModelModifier_ScaleAndMirror 0.3937` scales physics shapes cm→inch together with the mesh.
Citizen confirms this: it carries both a 0.3937 ScaleAndMirror and cm-authored physics
(radius `10.0` = a 10 cm pelvis capsule). Author `point0/point1/radius` in cm
(`bone_length_m * 100`) and let the one modifier convert. **Do not pre-scale to inches** —
that makes every capsule 2.5x too big.

### 3. Bone names must survive the compiler (`.` → `_`)

The **model compiler sanitizes `.` → `_` in bone names**. A Blender-mirrored limb bone
`upper_arm.L` compiles to `upper_arm_L` in the skeleton, but the FBX and skin deformers
keep the dot — so static FBX inspection looks fine. Physics KV3 that references
`upper_arm.L` points at a bone that no longer exists post-compile → every limb body floats
disconnected while the torso (pelvis/spine/chest — no dots) crumples fine.

Fix: sanitize `.L`/`.R` → `_L`/`_R` **only** at the string written into
`parent_bone`/`parent_body`/`child_body` in the vmdl. Keep all FBX/armature/skin-weight
authoring on the dot names. Citizen confirms the convention — it names mirrored bones
`arm_upper_L`/`leg_upper_R` with underscores.

**This defect hides in headless builds** — `dotnet build`/model compile reports "Succeeded"
with warnings. Verify in-editor, not headless.

### 4. Proportional constants (no hardcoded human dims)

Radii should be a **fraction of each bone's own length** so the skeleton scales with
proportions. Suggested starting values:

- Torso: pelvis 0.9, spine 0.85, chest 0.95, neck 0.6, head 0.55
- Limbs: upper_arm 0.28, forearm 0.24, thigh 0.34, shin 0.26
- Joint limits: use generous cartoon-ragdoll ranges (looser than citizen's tight mocap
  limits) so the crumple reads big and an exact anchor-axis match isn't required
- Forearm/shin → revolute (hinge), everything else → conical (ball-socket)

## Part B — the runtime toggle

A peer helper component that owns only the ragdoll swap. It takes the
`SkinnedModelRenderer` to drive and the root `Collider` to disable.

### 5. Enter: enable ModelPhysics, then shove

```csharp
var physics = Renderer.GameObject.Components.GetOrCreate<ModelPhysics>();
physics.Renderer      = Renderer;
physics.Model         = Renderer.Model;
physics.Enabled       = true;
physics.MotionEnabled = true;
BodyCollider.Enabled   = false;  // stop the standing box fighting per-bone bodies

foreach (var body in physics.Bodies)
    if (body.Component.IsValid())
        body.Component.ApplyImpulse(impulse);  // world-space
```

Put `ModelPhysics` on the **same GameObject as the renderer**. Disabling the standing
collider matters twice: it stops the capsule fighting the per-bone bodies, and it lets
traces hit the ragdoll bodies instead of a ghost box.

**The animation must pause while ragdolled** — a component that keeps writing
`Sequence.Name` every frame fights the physics bone writes. Renderer properties that are
not bone writes (tint, parented props) stay safe.

### 6. Exit: stand up from where it fell

```csharp
var restPos = firstBody.Component.WorldPosition;
WorldPosition = WorldPosition.WithX(restPos.x).WithY(restPos.y);  // take xy drift, keep z
physics.Destroy();  // bone control returns to Sequence next frame
// restore tint, scale, re-enable collider
```

Snap the NPC root to the ragdoll's rest position in **x/y only** — horizontal drift so it
stands up where it fell, but keep your own z (feet on the ground). Destroying
`ModelPhysics` hands bone control back to `SkinnedModelRenderer` — its `Sequence` drives
the bones again next update.

**Preserve the visual across the swap.** Capture `LocalScale` and `Tint` on enter and
restore on exit. The renderer's `LocalScale` may bake a height-scale that would be lost on
stand-up.

### 7. Lifecycle: don't leak the component

`ModelPhysics` should be created on enter and destroyed on exit (so a re-enter rebuilds
bodies cleanly from the vmdl). Also destroy it if the NPC is torn down mid-ragdoll, so a
physics component never leaks onto a dead GameObject.

## Multiplayer: ragdoll is host-only

In a host-authority NPC model, `Daze()` (and therefore ragdoll enter) runs on the host
only. Proxies reconstruct the dazed state from synced data and show the dazed clip + tint,
never a local physics crumple. Ragdoll is a local physics sim — running it on every peer
would diverge. Treat it as presentation the host authors and proxies approximate, not
replicated physics. Inert in single-player (the guard is `Networking.IsActive &&
!Networking.IsHost`).

## Performance bounds

One `ModelPhysics` ragdoll is ~9–13 rigid bodies + their joints. It's live only between
enter and exit (a few seconds of daze) and is destroyed on stand-up — cost is transient and
proportional to how many NPCs are dazed at once, not crowd size.

## Build order (condensed)

1. Author the two physics nodes by copying citizen's schema; splice at a stable marker
   (don't fork the rig writer). Torso first (no dots — always resolves), then limbs.
2. Fix bone names to the sanitized `_L`/`_R` form at the KV3 string boundary only; verify
   in-editor that a full recompile adds zero new `unknown bone` warnings.
3. Settle units against citizen (cm, one ScaleAndMirror) — capsules the right size.
4. Runtime toggle: enter (GetOrCreate ModelPhysics, enable, disable collider, ApplyImpulse
   to every body), exit (x/y root snap, Destroy, restore tint/scale, re-enable collider),
   OnDestroy cleanup.
5. Consumer wiring: model allowlist, create the peer synchronously, call enter from the
   daze trigger, gate all SetSequence/root writes on `IsRagdolled`.
6. Multiplayer: keep daze/ragdoll host-only; proxies show the clip.
