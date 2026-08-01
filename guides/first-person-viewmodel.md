---
title: "First-person viewmodel and the third-person/first-person camera split"
slug: first-person-viewmodel
date: "2026-07-18T11:00:00-04:00"
updated: "2026-07-18T11:00:00-04:00"
lanes:
  - writing-gameplay
  - getting-art-in
tags:
  - camera
  - first-person
  - viewmodel
  - animation
  - rendering
summary: >-
  The method for a CS/Rust-style two-view split off one player rig: third person
  shows the world model, first person hides it and shows a camera-attached viewmodel
  (arms + held item). Covers hysteresis, tag-based per-view exclusion,
  the ShadowRenderType correction, and viewmodel composition.
verifiedOn: "26.07.15a"
sourceRev: methods/first-person-viewmodel-and-camera-views.md
relatedFixes:
  - first-person-hide-all-renderers
  - model-tint-flat-vmat-traps
unverified: false
---

The method for a CS/Rust-style two-view split off **one player rig**: third person (the primary view) shows the **world model** (body + gadget mounts visible to every player), and first person (zoomed fully in) hides it and shows a separate **camera-attached viewmodel** (arms + held item) — local-only, never seen by others. The two never render at once; a boom-distance hysteresis band decides which.

## The engine idiom (copy this pattern)

The engine's own weapon base (`BaseCombatWeapon.ViewModel.cs` in `Sandbox.Engine/Scene/Components/Game/Weapon/`) spawns a viewmodel like so:

```csharp
ViewModel = ViewModelPrefab.Clone(new CloneConfig {
    Parent = GameObject, StartEnabled = false, Transform = Transform.Zero
});
ViewModel.Flags |= GameObjectFlags.NotSaved
    | GameObjectFlags.NotNetworked
    | GameObjectFlags.Absolute;
ViewModel.Tags.Add("firstperson", "viewmodel");
```

The load-bearing decisions:

1. **A viewmodel is a GameObject parented to the camera** — it inherits the camera's world transform every frame. You only set camera-local offsets.
2. **Local-owner + first-person only** — `if (IsProxy || !IsHeld) return;`. Never spawn it on a proxy (it's *your* hands, visible only to you). Not networked; each client makes its own.
3. **Tag it `"viewmodel"` / `"firstperson"`** so other cameras can exclude it via `RenderExcludeTags`.
4. **Per-view exclusion is a camera tag-set** — `CameraComponent` has `RenderTags` (include) and `RenderExcludeTags` (exclude). The FP camera adds `"viewer"` to `RenderExcludeTags` to skip the player's own body. The viewmodel's tags are the same mechanism in reverse.

## Part 1 — the FP/TP crossing (boom hysteresis)

A chase camera zooms a boom arm with the scroll wheel; scrolling fully in crosses into first person. A **hysteresis band** prevents flicker at the boundary:

```csharp
// Enter FP below one distance, leave FP above a larger one
const float FpEnterM = 0.4f;   // boom below this => first person
const float FpExitM  = 0.7f;   // boom above this => back to third person

if (!_firstPerson && _boomM < FpEnterM)
{
    _firstPerson = true;
    character.SetBodyFirstPerson(true);
}
else if (_firstPerson && _boomM > FpExitM)
{
    _firstPerson = false;
    character.SetBodyFirstPerson(false);
}

IsFirstPerson = _firstPerson;   // static bool — the single source of truth
```

`IsFirstPerson` is a `public static bool` polled by every FP-aware system (body-hide, world-item-hide, viewmodel). Reset it to `false` in `OnDisabled` so leaving character mode restores everything.

**Camera law:** in first person, the camera position reads the character's **interpolated render transform**, never the raw fixed-tick feet field — reading a 50 Hz mover staircase in a per-render context sawtooths the view. The viewmodel obeys the same law: sway/bob compose on the **viewmodel's own local transform**, never on the camera directly.

## Part 2 — hiding the world model in FP (tag-based per-view exclusion)

### The ShadowRenderType trap

A common first attempt: set `RenderType = ShadowRenderType.Off` on body renderers to "hide" them in FP. **This does not work.** The engine source defines the enum:

| Value | Model draws? | Casts shadow? |
|---|:---:|:---:|
| `On` | yes | yes |
| `Off` | **yes** | no |
| `ShadowsOnly` | **no** | yes |

`ShadowRenderType.Off` means "render **without** shadow" — it never hides anything. Only `ShadowsOnly` sets `SceneObjectFlags.ExcludeGameLayer`, which drops the visible draw. This single confusion produces two defects: a duplicate world-held item (still rendering at the hand next to the viewmodel) and the body "surging into the viewport when running" (it was always drawn; a run lean pushed it into the frustum).

### The correct mechanism (copy this)

Per-view **tag exclusion** — not a per-renderer flag:

**Camera side** — the FP camera excludes a tag:

```csharp
// On entering character mode:
if (!cam.RenderExcludeTags.Contains("viewer"))
    cam.RenderExcludeTags.Add("viewer");

// On leaving character mode — clean up the shared camera:
cam.RenderExcludeTags.Remove("viewer");
```

**Object side** — tag the thing to hide:

```csharp
// Body + clothing (all renderers under the visual root):
_visual.Tags.Set("viewer", firstPerson && !IsProxy);

// Held world item (the mount root):
_mount.Tags.Set("viewer", firstPerson);
```

Why this is strictly better than `ShadowsOnly`:

- **Tags inherit to descendants.** One tag on the visual root covers every clothing renderer spawned by `ClothingContainer.Apply`, and one on the mount root covers all item children — no enumerate-at-toggle-time.
- **Authoritative per-view culling** — immune to renderer rebuilds, outfit swaps, and interpolation timing.
- **The body keeps its shadow in FP** (exclusion is view-only) — a bonus over the flag approach, which deletes the shadow.
- **Proxies are never tagged** — a proxy is another player's body, always visible in third person. Tags are local (not networked), so each client hides only its own.

## Part 3 — the camera-attached viewmodel

A component that rides the camera GameObject. Created when entering character mode, destroyed when leaving. Structure:

```
Scene.Camera.GameObject
  +-- viewmodel_root       (sway/bob transform, tagged viewmodel/firstperson)
        +-- viewmodel_arms  (SkinnedModelRenderer + CitizenAnimationHelper)
        +-- viewmodel_item  (ModelRenderer of the equipped gadget)
```

**Active gate** (poll every `OnUpdate`): local owner + `IsFirstPerson` + in character mode + not driving. Rebuild the children only on an equip-kind change (not per-frame).

**Bounds-normalizing the item model** prevents near-plane clip and inconsistent scale:

1. Scale the model so its largest `Model.Bounds` dimension reads a target size (e.g. 0.30 m).
2. Offset a child GameObject by `-bounds.Center` so the per-item offset table places the model's visual **center**, not its origin (AI-generated meshes often have off-center origins).
3. Keep the forward offset past the camera's `ZNear` (~0.25 m default) — 0.42 m+ is safe.

Per-item offsets are a camera-local data table (forward, left, up in metres + rotation + scale multiplier), tuned per gadget. **Unverified:** the specific offset values have never been checked on screen. The architecture is proven; the visual tuning needs a live editor session.

## Part 4 — arms rig + holdtype

The citizen addon ships `models/first_person/first_person_arms_preview.vmdl`. Mount a `SkinnedModelRenderer` + `CitizenAnimationHelper` on the arms child, then set `HoldType`/`Handedness` matching the third-person body:

```csharp
_armsRenderer = _arms.Components.Create<SkinnedModelRenderer>();
_armsRenderer.Model = armsModel;
_armsAnim = _arms.Components.Create<CitizenAnimationHelper>();
_armsAnim.Target = _armsRenderer;
_armsAnim.HoldType = holdType;
_armsAnim.Handedness = handedness;
```

Gate the whole arms rig behind a tuning flag. **Unverified:** whether the preview model carries the citizen skeleton/animgraph is unconfirmed, and it may render in bind pose. If it does not, fall back to an **item-only** viewmodel: just the gadget at a natural offset, no arms. Item actions are input-driven and never touch the rig, so gameplay is identical regardless.

## Part 5 — sway + bob

Composed on the **viewmodel root's** local transform, so arms + item move together and the camera is never touched. Look-sway lags the rig opposite a fast mouse turn and eases back; walk-bob is a `sin` cycle scaled by a **smoothed** horizontal speed (raw fixed-tick position deltas jitter at 50 Hz — smooth the speed or the bob amplitude flickers frame-to-frame), plus a tiny always-on idle breathe.

**Unverified:** the sway/bob feel and amplitudes are code-tuned but have never been checked on screen. The math is standard FPS viewmodel motion, so treat the numbers as reasoned starting points.

## Gotchas

- **Near-plane clip:** the viewmodel sits ~0.34 m forward; the default `ZNear` is ~0.25 m. A much closer offset, wide FOV, or large bob can clip. Keep item offsets past `ZNear`.
- **One static source of truth for FP state** — three consumers (body-hide, world-item-hide, viewmodel) all poll `IsFirstPerson`. Never derive FP state independently or they drift.
- **Rebuild on equip, not per frame** — build/teardown children only on a kind change. Per-frame only animates the local transform.
- **Destroy the rig on leaving character mode** — it's parented to the shared camera. Leak it and stray arms linger into orbit/vehicle views.
- **No separate viewmodel FOV in this pattern** — the viewmodel renders at the main camera's FOV. A true separate viewmodel FOV needs a second camera pass; flagged as future polish.
- **Worn gadgets (jetpack, glider)** show arms-only in FP (empty hands). Hand gadgets (grapple, light) show arms + item.
