---
title: Character-mounted assets and live-tuning their placement
slug: character-mounted-assets-live-tuning
date: "2026-07-16T21:05:00-04:00"
updated: "2026-07-19T11:20:00-04:00"
lanes:
  - rigging-animation
  - writing-gameplay
  - building-ui
tags:
  - mounting
  - animation
  - rigging
  - ui
  - convar
summary: >-
  The method for hanging custom models off the player rig -- gadgets,
  backpacks, held items -- with three mount styles off one skeleton,
  and a live slider panel that dumps C#-ready constants for paste-back.
verifiedOn: "26.07.18"
sourceRev: methods/character-mounted-assets-live-tuning.md
relatedFixes:
  - setbonetransform-silently-noop
  - draggable-slider-click-drag
  - ui-frozen-buildhash
  - razor-text-renders-blank-density-modes
  - font-glyph-corruption-cumulative-text-count
  - editor-captures-play-hotkeys
unverified: false
changelog:
  - { date: "2026-07-19", note: "Added projected-decal bone-follow technique for body paint/impacts" }
---

The method for hanging custom models off the player rig -- gadgets, backpacks,
held items -- and dialing each one's placement to final values live in the
running game instead of edit-recompile-relaunch. Three mount styles off one
skeleton, a live override layer consumed at the exact runtime seam the shipped
constants use, and a draggable-slider panel that dumps C#-ready constant lines
for paste-back. What you tune on screen is byte-for-byte what the baked constant
reproduces.

Provenance: shipped and owner-verified live in a voxel-terrain project with six
Tripo-generated traversal gadgets mounted and position-tuned to final values in
one session.

## The single-source-of-truth split

The load-bearing decision is that **mount data lives in a static that BOTH the
runtime renderer AND any edit-mode preview harness read** -- never inline in the
controller. Pull every mount constant out of the controller into a dedicated
mounts static so a preview harness can never diverge from what a player sees in
play. The same split is what makes the live-tune layer a drop-in: the tuner is a
second reader seeded from the first.

```
MountsData (static)      <-- the shipped constants, the BAKE TARGET
      |  seeds
      v
MountTweak (static)      <-- live override layer (TEMP), defaults == MountsData
      |  consumed at the SAME seam
      v
ItemController           <-- FollowHandMount / FollowBackMount read the layer,
                             apply x UnitsPerMetre at the boundary
```

The units-per-metre conversion happens **once**, at the mount SETTER in the
controller -- never in the data static. Author every offset in metres; the
boundary is the single multiply. Two conversions (or zero) is the classic scale
bug.

## The three mount styles

Each item declares a style; the controller anchors the mount differently per
style. The frame that the per-item `offset`/`rotation` live in is DIFFERENT for
each -- this is the thing people get wrong.

```csharp
public enum MountStyle { Hand, Back, Feet }
```

### Hand mount -- skeleton attachment + hand-local correction

The gadget pins to the citizen's right-hand weapon-hold attachment every frame.
Resolve the hand transform by trying **attachment names first, then bone names**,
caching whichever resolves:

```csharp
static readonly string[] HandAttachNames = { "hold_R", "hold_r" };
static readonly string[] HandBoneNames   = { "hand_R", "hand_r" };
// try GetAttachment(name) for each attach name;
// fall back to TryGetBoneTransform(name)
// posM = t.Position / UnitsPerMetre;  rot = t.Rotation;
```

Per-item dials are a **correction applied in the hand's LOCAL frame** on top of
the attachment transform:

```csharp
var worldPosM  = handPosM + handRot * offsetM; // offset is hand-local
mount.WorldPosition = worldPosM * M;           // the ONE x M boundary
mount.WorldRotation = handRot * rotFix.ToRotation();
```

`offsetM` reads as "forward-along-the-grip / into-the-palm" in the hand's own
axes, and `rotFix` (an `Angles(pitch,yaw,roll)`) twists the model against the
palm. These are LOOK calls -- the exact twist is eyeballed against captures.

### Back / bone mount -- follows the animation bob

A back gadget parented rigidly to the character ROOT tracks smooth root motion,
not the animated spine -- the result is "my shoulders bob but the gadget just
slides." Pin the mount to an upper-spine BONE (e.g. `spine_2`) each frame so it
bobs and leans with the run cycle.

Follow only the bone's **position** (which bobs/leans) and keep a clean
**body-aligned rotation** (character facing times the tuned `Angles`) -- this
sidesteps bone-local-axis guesswork entirely:

```csharp
var bodyRot = chr.WorldRotation;                            // yaw-only facing
mount.WorldPosition = (bonePosM + bodyRot * offsetM) * M;  // offset in BODY frame
mount.WorldRotation = bodyRot * rot.ToRotation();
```

`offsetM` here is the vector from the spine bone to where the item sits, in the
body frame (x forward, y left, z up) -- NOT the bone-local frame.

### Projected decals on an animated body (bone-follow variant)

The same bone-follow primitive carries a **projected decal** on an animated body —
paint/impact marks that must ride the moving character, not float where they landed.
A world-space `Sandbox.Decal` cannot follow a moving character (its projection volume
is fixed in world space), so you parent it under the character and re-pin its world
transform to a live bone each frame.

Technique: parent a `Sandbox.Decal` GameObject under the character; at spawn pick the
nearest skeleton bone (`SkinnedModelRenderer.TryGetBoneTransform`) and store the impact
in that bone's LOCAL frame (`bt.PointToLocal(hit)`, build an orthonormal frame from
the normal). Each frame (`OnUpdate`, before render) re-pin
`GameObject.WorldPosition = bt.PointToWorld(localPos)`,
`WorldRotation = bt.Rotation * localFrame` off the CURRENT bone pose. The decal then
re-projects onto the animated skinned mesh live — paint rides the torso/limb/head
through the run cycle, on every peer (bones animate on proxies).

Set the world transform AT spawn (frame-0) so there's no one-frame flash at the
character root. Cap per body + recycle oldest; a fresh `SkinnedModelRenderer` from an
item swap is fine (bone-local coords are rig-invariant; read `.Visual` fresh each
frame).

**Projection Depth** must span the clothing shell: the analytic capsule hit sits inside
the outer cloth renderers, so a shallow Depth paints only bare skin. Tune to reach
the shirt without punching through thin limbs onto the far side.

### Feet / root mount -- rigid child of the character root

The simplest style: parent the mount to the character and set a local
offset/rotation in the ROOT frame:

```csharp
mount.SetParent(chr.GameObject, false);
mount.LocalPosition = offsetM * M;
mount.LocalRotation = rot.ToRotation();
```

### Model-origin discipline (the silent vertical-offset bug)

Assets authored grounded at z=0 (origin at the model's bottom) extend upward
from the mount point. If a gadget is ~0.5 m tall and the mount z is 0.85, the
tops end up flanking the head. Know where your model's origin sits before you
reason about the offset -- half of "it's floating / it's buried" is the model
origin, not the dial.

### The frame-0 bind-pose trap

`GetAttachment` / `TryGetBoneTransform` can return the **bind pose** on the
first frame after a model is created -- the skeleton hasn't been animated yet.
A mount placed once at attach snaps to a T-pose location and then jumps when
the animation first evaluates.

Fix: place immediately at attach AND re-pin every frame in `OnPreRender` (which
runs after the citizen pose is evaluated). The attach-frame placement is
provisional; the per-frame `OnPreRender` re-pin is authoritative. Do the follow
in `OnPreRender`, not `OnUpdate`, so you read the bone/attachment transform for
the pose that will actually render this frame.

## The live-tune override layer + panel

Iterating mount numbers by editing a constant, recompiling, relaunching, and
re-walking to the test spot costs minutes per nudge. The override layer collapses
that to a drag.

### The WYSIWYG / bake-fidelity contract

The override layer is a static, per-item `Tune { PosM, Rot, Scale }`, **seeded
from the shipped constants** on first access:

```csharp
static Tune SeedFor(ItemKind k)
{
    // read CURRENT shipped constants for this item's style into a Tune
    // deep-COPY any array fields so panel edits never mutate the readonly source
    return new Tune { PosM = pos, Rot = rot, Scale = characterScale };
}
```

Because every entry starts equal to the constant, **opening the panel changes
nothing until a value is touched.** And because the controller now reads
`MountTweak.For(kind)` at the EXACT seam it used to read the mounts static --
same follow methods -- what the owner tunes is byte-for-byte what a constant edit
will reproduce. No "the panel looked right but the bake drifted" gap.

### Tabbed panel, hotbar-drives-the-tab

One tab per mountable item; only the active tab's rows render (keeps the live
text-run count low -- see the glyph budget below). The critical UX lesson: **the
hotbar drives the tab, NOT the reverse.** An early version force-equipped the
active tab's item every frame, which fought the player -- every gadget switch
snapped back.

The fix:
- While the panel is open, if the player is HOLDING a gadget, follow the tab to
  the held item
- If the player is holding NOTHING (stowed), equip the tab's item so its mount
  stays visible (WYSIWYG -- you must see the thing you're tuning)
- Clicking a tab also equips that item

Never force-equip against a live player selection.

### Force-showing the tuned item

Some placement is only visible under a runtime state -- e.g. flame nozzles only
show while thrusting. Gate a force-show on `panelOpen && activeTab == kind` and
OR it into the runtime's visibility check, so the effect offset is tunable
without holding the trigger key.

### Dump -- C#-ready constant lines for paste-back

A Dump button prints each item's tuned values as a paste-ready snippet to the
console; a Copy puts one tab's line on the clipboard. Format the dump to mirror
the constant's SIGNATURE exactly (the `Vector3(...)`/`Angles(...)` literals, the
same field names) so paste-back into the mounts static is mechanical. After
baking, the tuned value and the constant are identical by the WYSIWYG contract.

### Editor-only gating + temp-tool discipline

A live-tune panel must not ship:

- **Gate on `Application.IsEditor`.** A published build is never `IsEditor`, so
  the toggle key and convar are both dead on the live game.
- **Mark every piece TEMPORARY with a delete list.** The tweak static and its
  panel both carry a header naming exactly what to strip after bake. The mount
  struct and the constant defaults are permanent; only the panel rows that edit
  them are temporary.

### The static-persistence / convar trap

The panel's open-state is a `[ConVar]`. s&box persists convars across sessions,
so a session can boot with the panel logically open -- which invisibly
force-equips the last active tab's item and makes the hotbar look "stuck." Any
static/convar that gates behavior and survives a play session must be
**force-reset to inert at session start**:

```csharp
protected override void OnStart()
{
    if (MountTweak.PanelOpen)
        Log.Info("[panel] was OPEN at session start (persisted convar) -- forcing closed");
    MountTweak.PanelOpen = false;
}
```

General rule: any persisted static that changes runtime behavior must
default-close on boot, and log when it was found non-default.

## The draggable slider row

Each row is a click-to-jump + drag-to-scrub track with a small +/- beside it
for cm/degree precision. There is no native drag helper; the mechanic is the
engine's own `SliderControl` pattern, hand-rolled (see
[Draggable slider click-drag](/fix/draggable-slider-click-drag)).

The load-bearing SCSS idiom: `.track` with `position: relative` + `.fill` with
`position: absolute` so dragging fills the bar without growing the row.

Razor (one row):

```razor
@foreach (var r in Rows)
{
    var row = r;
    float cur  = MountTweak.Get(Tab, row.field);
    string val = cur.ToString(row.fmt);
    int fillPct = (int)(Frac(cur, row) * 100f);
    <div class="mt-row">
        <div class="mt-rlab"><span>@row.label</span><span>@val</span></div>
        <div class="mt-slider">
            <span class="mt-stp"
                  onclick=@(() => Nudge(row.field, -row.step * StepMult))>-</span>
            <div class="mt-track"
                 onmousedown=@(e => TrackPointer(e, row, true))
                 onmousemove=@(e => TrackPointer(e, row, false))>
                <div class="mt-fill" style="width: @(fillPct)%;"></div>
            </div>
            <span class="mt-stp"
                  onclick=@(() => Nudge(row.field, row.step * StepMult))>+</span>
        </div>
    </div>
}
```

The shared pointer handler routes the absolute drag target back through a
delta-taking `Nudge` mutator, so all clamps live in one place:

```csharp
void TrackPointer(PanelEvent ev, Row row, bool jump)
{
    if (ev is not MousePanelEvent e) return;
    var track = e.This;
    if (track is null) return;
    if (!jump && !track.PseudoClass.HasFlag(PseudoClass.Active)) return;

    float w = track.Box.Rect.Width;
    if (w <= 0f) return;
    float frac   = Math.Clamp(e.LocalPosition.x / w, 0f, 1f);
    float target = row.min + frac * (row.max - row.min);
    if (row.step > 0f)
        target = MathF.Round(target / row.step) * row.step;
    target = Math.Clamp(target, row.min, row.max);
    MountTweak.Nudge(Tab, row.field, target - MountTweak.Get(Tab, row.field));
}
```

### Re-render + Razor traps

- **`BuildHash` must fold every displayed value** (rounded to an int so it
  changes on a nudge), or the on-screen number freezes while the mount moves
  (see [UI frozen BuildHash](/fix/ui-frozen-buildhash)):
  ```csharp
  protected override int BuildHash()
  {
      int h = HashCode.Combine(PanelOpen, (int)Tab, _coarse);
      foreach (var r in Rows)
          h = HashCode.Combine(h, (int)MathF.Round(
              MountTweak.Get(Tab, r.field) * 1000f));
      return h;
  }
  ```
- **Render rows in the component's main `<root>` markup, not a
  `RenderFragment` expression** -- thin flex rows with a gap under-measure
  their height inside a fragment and pile on each other (see
  [Razor fragment flex gap](/fix/razor-fragment-flex-gap-undermeasures-height)).
- **Resolve computed values to a plain local before interpolating**
  (`string val = cur.ToString(...)` then `@val`) -- inline `@Foo()` inside a
  fragment can render blank (see
  [Razor text renders blank](/fix/razor-text-renders-blank-density-modes)).

## The glyph-budget + F-key constraints

Two s&box UI traps bite dev panels hard:

- **Never bind the toggle to an F key.** The editor owns F1-F12 in play mode,
  so a raw `Input.Keyboard.Pressed("F7")` never fires -- silently. Use a letter
  key with a convar fallback so the tool stays reachable if the key collides
  (see [Editor captures play hotkeys](/fix/editor-captures-play-hotkeys)).
- **Font-size glyph corruption is a cumulative text-count budget**, not just a
  per-declaration one. Too many `font-size` declarations and/or high live
  text-run counts corrupts text to solid filled blocks. Keep to a handful of
  grouped sizes (3 is safe), no `letter-spacing`, and render only the active
  tab's rows (see
  [Font glyph corruption](/fix/font-glyph-corruption-cumulative-text-count)).

## Build order

1. Split mount DATA into a static read by both the runtime and any preview
   harness. Author offsets in metres; put the single x-units-per-metre at the
   controller's mount setter.
2. Implement the three follow styles: hand (attachment + hand-local correction),
   bone-follow (spine position + body-aligned rotation), feet (root child).
   Re-pin in `OnPreRender` after pose evaluation.
3. Add the override layer seeded from the constants; move the controller's reads
   to it at the same seam (defaults == constants means no-op until touched).
4. Build the tabbed slider panel; hotbar-drives-tab, force-show the tuned item,
   `BuildHash` folds every value, rows in main markup.
5. Add Dump/Copy that mirror the constant signature. Gate everything on
   `Application.IsEditor`, force-close on boot, and write the delete-list
   header.
6. Tune live; dump; paste back into the constants; delete the temp surface per
   the delete list.
