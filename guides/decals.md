---
title: "Decals: projection, determinism, and performance in s&box"
slug: decals
date: "2026-07-18T15:30:00-04:00"
updated: "2026-07-18T15:30:00-04:00"
lanes:
  - writing-gameplay
  - making-it-perform
tags:
  - decal
  - projection
  - multiplayer
  - skinned-mesh
  - lighting
  - performance
summary: >-
  The practical patterns for Sandbox.Decal: orienting the projection box to a
  hit normal, keeping a decal byte-identical across multiplayer peers, making
  paint follow an animated character, and scaling to thousands of decals
  without a performance cliff, plus the pitfalls that catch each one.
sourceRev: null
relatedFixes:
  - decal-color-lit-albedo-washes-out
  - decal-determinism-across-peers
  - orient-decal-to-hit-normal
  - swept-trace-hitposition-vs-endposition
verifiedOn: "26.07.18"
unverified: false
---

## What decals are, and when to reach for them

A `Sandbox.Decal` component projects a box volume onto whatever surface it lands on
and paints that surface: it blends its silhouette into the surface's own albedo
(weighted by `ColorMix`) and then the result is lit normally as part of the scene,
not drawn as an unlit sticker on top. Reach for it for paint splats, impact marks,
blood, scorch marks, footprints, tags, anything that should read as world-space
decoration stuck to a surface.

It is not limited to static, hand-placed level geometry. Runtime-built meshes are
ordinary `ModelRenderer`s underneath, so a decal projects onto them exactly like it
would onto an authored prop (confirmed live against voxel-terrain chunk renderers on
engine build 26.07.18: paint lands and conforms to stepped and curved chunk faces).
One thing worth planning for up front: rebuilding a runtime chunk mesh (a brush edit,
a voxel remesh) drops any decals that were sitting on the old mesh. For terrain-style
paint that is usually fine, repainting a surface should clear its old paint; if it is
not fine for your case, keep the paint data separately from the `Decal` GameObjects
and respawn them after the rebuild.

## Working patterns

### Orient and size the projection box

The projection axis is local +X (the same axis the gizmo arrow and `GetDecalVolume`
put `Depth` on), so aligning +X to the surface's hit normal makes the box straddle
the surface correctly (verified against engine source on build 26.07.18):

```csharp
var decal = decalGo.Components.Create<Decal>();
decal.WorldRotation = Rotation.LookAt(hitNormal);

decal.Depth = 6f;              // how far the projection reaches along +X (wrap depth)
decal.AttenuationAngle = 0.4f; // 0 = paint every face it touches, 1 = fade out at grazing angles
decal.LifeTime = 0f;           // 0 holds the decal persistent, no native fade
decal.Transient = true;        // hand eviction to DecalGameSystem's own cap instead of yours
```

`Transient = true` lets the engine's `DecalGameSystem` manage eviction under its
`maxdecals` convar (default 1000, protected). If you need a game-dialable cap with
your own fade-on-recycle behaviour, manage a ring buffer yourself instead (see
"Scale to thousands" below) and leave `Transient` off.

### Make a decal render identically on every peer

`Sandbox.Decal` self-seeds with `Random.Shared.Int(10000)` when it is enabled, and
that seed drives its silhouette pick and its `Rotation`, `Scale`, and `ColorTint`
evaluation (verified against engine source on build 26.07.15a). Spawn the same
decal on two peers with the defaults left in place and they render differently. To
get a byte-identical decal everywhere:

```csharp
// 1. A single-element Decals list: you pick the silhouette yourself, not the RNG
decal.Decals = new List<Model> { splatSilhouette };

// 2. Constant curve values, not ranges: a plain float/Color assigns a Constant
//    ParticleFloat/ParticleGradient, whose Evaluate() ignores the random seed
decal.ColorTint = paintColor;  // Color -> Constant ParticleGradient
decal.ColorMix  = 1f;          // float -> Constant ParticleFloat
decal.Rotation  = fixedSpin;   // float -> Constant ParticleFloat
decal.Scale     = fixedScale;  // float -> Constant ParticleFloat
```

Once every evaluated field is a constant, the per-instance random seed has zero
observable effect, so two peers spawning "the same" decal call end up pixel-identical.

### Follow a moving or animated target

A decal's projection volume is fixed in world space, so it cannot track a moving or
animating character by itself: the instant the target moves, the decal keeps
projecting where it was spawned, onto empty air. To paint a moving body, parent the
decal under the character and re-pin its world transform to a bone every frame
(confirmed live on build 26.07.18):

```csharp
// At spawn: pick the nearest bone and store the hit in ITS local frame
decalGo.SetParent(character.GameObject, false);
var bone = skinnedRenderer.GetBoneTransform(nearestBoneName);
var localPos   = bone.PointToLocal(hitPosition);
var localFrame = bone.NormalToLocal(hitNormal);

// Set the world transform once at spawn (frame 0) to avoid a one-frame flash at
// the character root, then re-pin every frame BEFORE render off the current pose
void OnUpdate()
{
    var bt = skinnedRenderer.GetBoneTransform(nearestBoneName);
    decalGo.WorldPosition = bt.PointToWorld(localPos);
    decalGo.WorldRotation = bt.Rotation * FrameFor(localFrame);
}
```

Doing the re-pin before render, off the current bone pose, keeps the paint riding the
torso, limb, or head through the run cycle, on every peer, since bones animate on
proxies the same way gadget bone-mounts do.

### Scale to thousands without a hard cap

`Sandbox.Decal` instances are lightweight scene objects (one box projection each,
frustum-culled, no per-frame allocation while static), so there is no hard engine
ceiling and no crash cliff, just a gradual frame-time sag as count and on-screen
overlap grow. Give a persistent paint or impact system a ring-buffer cap behind a
convar so it is dialable per machine with no recompile:

```csharp
[ConVar] public static int paint_decal_cap { get; set; } = 8192;

void Spawn(Decal decal)
{
    _ring.Add(decal);
    while (_ring.Count > paint_decal_cap)
    {
        var oldest = _ring[0];
        _ring.RemoveAt(0);
        oldest.GameObject.Destroy(); // fade first if you want a softer recycle
    }
}
```

Keep the visual derivation a pure function of replicated inputs, so a peer running a
lower cap still renders the same marks, it just recycles at a lower count. Bench
method: enable a per-frame frame-time census, spam paint into one concentrated
overlapping area (the worst case for fill rate), escalate the cap convar, then back
off to a margin below where the 1-percent lows start to sag. One measured mid-2026
desktop (build 26.07.18): an 8192-decal cap held a locked 60 fps with 1-percent lows
in the mid 50s, while a 16384 cap sagged to a ~56 fps average with lows into the
teens. Treat those as an example of the bench method, not a portable number, your
own ceiling depends on your GPU and how concentrated the paint gets.

## Gotchas

**Pitfall: a pale tint washes out to a barely-there stain.**
A `Sandbox.Decal`'s colour is lit surface albedo, not an unlit overlay: the engine
multiplies `_def.Tint * ColorTint.Evaluate(...)` into the surface's albedo (weighted
by `ColorMix`) and lights the result like any other material (verified against
engine source, `Decal.cs UpdateToDelta`, build 26.07.15a). A light, HUD-tuned colour
goes gray and washed-out under bright sun. Fix: derive a deep, saturated tint from
your source colour (push it away from its own luminance for more saturation, then
multiply value down) while keeping the hue, and keep `ColorMix = 1` for opaque
paint. Full detail: [Decal colour is lit surface albedo](/fix/decal-color-lit-albedo-washes-out).

**Pitfall: two peers roll different decals from the "same" spawn call.**
See "Make a decal render identically on every peer" above: without a single-element
`Decals` list and constant curve values, the per-instance random seed makes the
silhouette, tint, rotation, and scale diverge across clients. Full detail:
[Sandbox.Decal renders differently on each peer](/fix/decal-determinism-across-peers).

**Pitfall: paint on a moving character floats in the air where the hit landed.**
Covered under "Follow a moving or animated target" above: a decal's projection
volume does not track anything by itself. Skip the bone re-pin and the mark stays at
the world point it was spawned, not on the body.

**Pitfall: a shallow projection depth paints skin but not the shirt over it.**
A character's clothing is separate renderers sitting outside the analytic capsule an
impact resolves against, so a `Depth` tuned to reach bare skin ends before the outer
cloth shell: paint shows only where skin peeks through (face, hands, a chest gap)
and the clothed body stays clean. Fix: widen `Depth` enough to span the clothing
shell, deep enough to reach the outer surface but shallow enough not to punch
through a thin limb onto its far side. One measured case (build 26.07.18): 14
engine units left a shirt unpainted, 32 units painted it while side-on limb shots
stayed clean of far-side punch-through. Retune per character and clothing scale,
this is not a universal constant.

**Pitfall: a decal splatted at a projectile's raw hit point glues to whatever it
hit, including mid-torso on a person.**
Seating a decal at the raw trace hit point works for world geometry, but a body hit
puts the mark wherever the capsule was struck, which can float mid-body. For a body
hit, trace straight down from the target's feet instead and lay the mark on the
ground below:

```csharp
var start = target.WorldPosition + Vector3.Up * 0.3f; // clear of the floor: a trace
                                                        // starting exactly at feet
                                                        // height begins inside the
                                                        // floor and self-hits
var tr = Scene.Trace.Ray(start, start + Vector3.Down * 64f)
    .IgnoreGameObject(target.GameObject)
    .Run();
if (tr.Hit)
    SpawnGroundSplat(tr.HitPosition, tr.Normal);
```

**Pitfall: a chunk remesh silently erases the decals sitting on it.**
Rebuilding a runtime chunk mesh (a brush edit, a voxel remesh) drops any decals that
were projected onto the old mesh. For terrain-style paint this is usually the right
behaviour, repainting a surface should clear its old paint; if your case needs the
paint to survive a remesh, keep the paint data separately from the `Decal`
GameObjects and respawn them after the rebuild.
