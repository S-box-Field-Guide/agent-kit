# Writing gameplay — input, camera & UI

> Topic sub-file of this lane — router: `writing-gameplay.md` (its "Where everything lives"
> table maps every topic). Load `_core.md` first. Bullets below are moved verbatim
> from the lane pack; the sync appends new bullets for these topics here.

- **Over-world UI (name labels, health/alert bars over a head) is built from MODEL-BASED
 tinted boxes, NOT a WorldPanel razor, in one project.** Two independent places
 (`ZonesBuilder.NameLabel`, `MapExtension.NameLabel`) explicitly chose "dark backing
 slab + bright face-plate" dev-box renderers over a WorldPanel "to avoid razor namespace/
 BuildHash traps" — and there is ZERO working WorldPanel usage in the codebase to copy. The
 guard's daze "stars" cue (`GuardNpc.SpawnStars`) is the same idiom: `models/dev/box.vmdl`
 renderers parented to the character, `renderer.Tint` for color, `LocalScale = sizeMeters *
 M / 50f` (the dev box is a 50u cube). For a FILLABLE bar (alert meter), a back slab +
 a fill slab whose X-scale = fraction, left-anchored, billboarded to `Scene.Camera` each
 frame: to present the wide face, orient the WIDTH (+X) axis along screen-right
 (`Cross(Up, toCam)`) via `Rotation.LookAt(screenRight, Up)` — NOT `LookAt(toCam)` (that
 points +X at the camera, showing the bar edge-on). Cheap, reliable, visible from any angle,
 no razor surface.

- **Full-screen HUD toasts/banners: mirror ScreenFade — a `PanelComponent` with a static
 null-safe `Show` + a per-client `Instance` set in OnEnabled, mounted once in Bootstrap
 on the `ui` GameObject next to ScreenFade/CeremonyScreen.** The static API no-ops when
 `Instance` is null (menu/headless), so callers never guard. Gate a per-player banner on
 `Character.Instance == caught` (the local non-proxy) so only the affected client sees it, same
 as the catch fade. `BuildHash` must cover every field the markup reads (the phase/flag) or
 the panel goes stale.

## Input

- **`Input.UsingController` is a real public bool** (verified by grepping
 `Sandbox.Engine.dll`'s metadata strings for `<UsingController>k__BackingField` next
 to `UseController`/`ignoreController`/`oldUsingController` — a standard auto-property
 backing field, and `dotnet build` resolves `Input.UsingController` with zero errors).
 Use it to gate pad-only feel tweaks (e.g. a bigger look-sensitivity multiplier only
 while on a gamepad) without a per-device AnalogLook split, which s&box does not
 expose. `ControllerLookPitchSpeed`/`ControllerLookYawSpeed` also exist as engine
 ConVars (getter+setter with `ConVarAttribute`) — those are the user's own
 sensitivity settings, not something game code should read/override.

- **Gamepad bumper GamepadCode strings are `"SwitchLeftBumper"`/`"SwitchRightBumper"`**,
 not `"LeftShoulder"`/`"RightShoulder"` — confirmed consistent across all 6 project
 Input.configs on this machine. Menu/back buttons are `"SwitchLeftMenu"`/`"SwitchRightMenu"`. Other
 verified GamepadCode values in use: `"A"`, `"B"`, `"X"`, `"Y"`, `"LeftTrigger"`,
 `"RightTrigger"`, `"LeftJoystickButton"`, `"RightJoystickButton"`, `"DpadNorth"`,
 `"DpadSouth"`, `"DpadEast"`, `"DpadWest"`, `"None"`.

- **New input actions added to `Input.config` don't register until the editor
 restarts** — a headless `dotnet build` succeeding does NOT mean `Input.Pressed("New
 Action")` will fire in a running editor session; it needs a Play/editor restart to
 pick up the new action list.

- **Gamepad triggers DO have a public smooth 0..1 analog read —
 `Input.GetAnalog(InputAnalog.LeftTrigger)` / `InputAnalog.RightTrigger`.** The `InputAnalog`
 enum has explicit per-axis members (`LeftStickX/Y`, `RightStickX/Y`, `LeftTrigger`,
 `RightTrigger`) — there is no `InputAnalog.Move` member. What is digital-only is a *named
 `Input.config` action* bound to a trigger: that reads on/off via `Input.Down/Pressed/Released`,
 no pull value. The analog axis is a SEPARATE surface, read directly off the physical trigger,
 independent of any config-action binding. **Whitelist-VERIFIED** — a real game build of
 `Input.GetAnalog(InputAnalog.RightTrigger)` compiles clean through the `Sandbox.Generator`
 access analyzer. Returns `0` unless `Input.UsingController` (safe to MAX-blend with keyboard),
 and the engine pre-applies a 12.5% deadzone so resting triggers can't creep. Use for variable
 throttle/brake: `throttle = Max(keyboardForward, GetAnalog(RightTrigger))`.

- **`Mouse.Visible = true` is past "obsolete but functional" — migrate to
 `Mouse.Visibility = MouseVisibility.Visible/Hidden`** (engine XML: "Use
 Mouse.Visibility instead"). It raises CS0612 in the fresh in-editor compile, and the
 whole-tree 0/0 gate stays red until migrated; one project already migrated
 (a tool camera/EscapeMenu). Companion play-mode note for cursor-driven tool cameras:
 editor keyboard/mouse input reaches one project only while the game viewport has FOCUS —
 "camera dead in play mode" is usually an unclicked viewport, not an input-API bug
 (verify attachment headlessly via find_game_objects component=<CameraDriver> before
 suspecting code).

- **`TextEntry.OnTextEdited` (an `Action<string>`) needs an EXPLICITLY-TYPED, BLOCK-bodied lambda
 — `t => _field = t` fails two different ways.** An untyped lambda (`OnTextEdited=@(t => _field =
 t)`) fails `CS8917: The delegate type could not be inferred` in the razor codegen (the in-editor
 compiler only — headless `dotnet build` doesn't catch it, see below). Adding an explicit param
 type (`OnTextEdited=@((string t) => _field = t)`) trades that for `CS0029: Cannot implicitly
 convert type 'Func<string,string>' to 'Action<string>'` — an EXPRESSION lambda with an assignment
 BODY gets inferred as returning the assigned value (a `Func`), not `void` (an `Action`), once the
 compiler has enough type info to try. Fix: explicit param type AND a block body so the assignment
 is a statement, not an expression: `OnTextEdited=@((string t) => { _field = t; })`. The other
 engine-source precedent (`CreateGameModal.razor`) already uses this exact explicit-type-plus-block
 shape — `(string x) => { Output.GameSettings[e.Name] = x; }` — so it's the house pattern, not a
 fallback. Also: `TextEntry`'s `Numeric` bool property needs `Numeric=@true` (a real C# expression),
 NOT `Numeric="true"` (a markup string attribute) — the latter fails `CS0029: Cannot implicitly
 convert type 'string' to 'bool'` in the same codegen pass.

- **Whitespace immediately adjacent to a tag/expression boundary in razor markup collapses to
 NOTHING — including `&nbsp;` (U+00A0 still satisfies `char.IsWhiteSpace` in .NET, so the collapse
 logic eats it too).** `chunks <span class="cval">@x</span> more text` renders as `chunks123more`
 — the literal space right before `<span>` and the literal space right after `</span>` both vanish,
 while a space in the MIDDLE of one uninterrupted text run (no tag/expression boundary crossed)
 survives fine. Same root cause bit a plain multi-expression markup line with no elements at all:
 `@_worldSize × @_worldSize` (two adjacent `@`-expressions with literal ` × ` between) also lost
 its spacing. Fixes, in order of preference: (1) collapse multiple `@expr`/literal fragments into
 ONE C# interpolated string — `@($"{_worldSize} × {_worldSize}")` — when no per-fragment styling is
 needed; (2) when a styled inner `<span>` genuinely needs breathing room from its neighbours, use
 CSS `margin` on the span's own class instead of a text-node space (`.cval { margin: 0 3px; }`) —
 box-model spacing doesn't go through the whitespace-collapse pass at all and is the only reliable
 fix once `&nbsp;` has already failed. HTML entities that aren't whitespace (`&middot;` etc.) DO
 decode and render correctly, so entities themselves aren't the problem — only whitespace-class
 characters are collapsed.

- **A NEW `*.razor.scss` created while the editor is already running does NOT get compiled/applied
 until the editor restarts — the panel COMPONENT runs fine, it's only unstyled.** Symptom: a new
 PanelComponent's `OnStart`/`OnTreeBuilt` both fire (code is live, panel IS in the render tree) and
 INLINE styles render (a `<div style="...left:500px...background:red">` shows), but nothing driven by
 the sibling `.razor.scss` applies — so the root's `width:100%`/`height:100%` never take, the root
 auto-sizes to content, and any `right:Npx`-anchored child lands off-screen (measured from a
 zero/narrow root's right edge). Editing/renaming/`@attribute [StyleSheet]`/touch-triggering the scss
 in-session all FAILED to make the running editor pick it up (razor recompiles many times, scss stays
 stale). Same family as "new vmdl/regenerated texture needs an editor kick." DIAGNOSIS RECIPE that
 isolates it in minutes: (1) add `Log.Info` to the panel's `OnStart`+`OnTreeBuilt` — if they fire, the
 code is live and it's NOT a stale-assembly/compile problem; (2) put an INLINE-styled box at `left:Npx`
 (not `right:`) — if it renders, the render pipeline works and the ONLY missing piece is the scss.
 Fix for the deliverable: the scss is correct and applies on the next fresh editor start (like every
 other panel in the project); to make a panel usable IN-session without the scss you'd have to set the
 root style in C# (`Panel.Style.Width = Length.Percent(100)` in OnTreeBuilt) — but children still need
 their own styling, so a restart is the clean answer.

- **A stylesheet with MANY selectors simultaneously declaring `font-size` (and/or
 `letter-spacing`) can corrupt UI TEXT GLYPH RENDERING for the WHOLE PANEL** — text
 draws as solid filled blocks (correct layout width, wrong glyph fill) instead of
 legible characters. A handful of `font-size` declarations is fine; roughly a dozen
 across one panel breaks every styled element. Carry visual hierarchy via
 `font-weight`/`text-transform`/`color` instead; if a panel truly needs per-element
 sizing, add it ONE selector at a time and screenshot-verify before adding the next.

- **Multiple `PanelComponent`s on ONE GameObject under ONE `ScreenPanel` all render** (one project
 Bootstrap mounts 6 on one ScreenPanel). So a second panel that shows nothing is NOT a
 one-ScreenPanel-per-panel wiring limit — don't split it onto its own ScreenPanel chasing that theory
 (it doesn't help). Instrument OnStart/OnTreeBuilt first to split "code not live" from "in tree but
 unstyled/mispositioned."

- **First-person "hide the player" — use the `"viewer"` tag + camera `RenderExcludeTags`, NOT `RenderType`.**
 `RenderType.Off` does NOT hide the model — `ModelRenderer.cs` defines `Off = render WITHOUT shadow` (model
 still draws); only `ShadowsOnly` sets `ExcludeGameLayer` to drop the draw. The correct fix is the engine's
 own PlayerController idiom: camera keeps `"viewer"` in `RenderExcludeTags` (set once), and the body/item GO
 does `Tags.Set("viewer", firstPerson && !IsProxy)`. GameObject tag propagates to children, so clothing items
 spawned by `ClothingContainer.Apply` are automatically hidden — no per-renderer enumeration needed.

- **`Sandbox.Input.EscapePressed` is a real public get/set bool** — read it to detect
  Escape, and set it `false` to consume the press so the engine doesn't route to its own
  pause menu. Verified in the SDK's `Sandbox.Engine.xml` with both `get_EscapePressed` and
  `set_EscapePressed` accessors. Use this for in-game close/back, not an `Input.config`
  bind (editor-reserved keys silently swallow `Input.config` Escape bindings).

- **`Input.config` `KeyboardCode` for punctuation keys is the LITERAL CHARACTER (`"["`,
  `"]"`), not a `KEY_`-enum-derived name.** A wrong name like `"lbracket"` fails silently
  (action never fires, no warning at load or bind time). Check the engine's
  `KeyboardCode` enum or test with `Input.Keyboard.Pressed("char")` to confirm.

- **Visible cursor blocks ALL game mouse input with no raw bypass** — `Input.Down/Pressed` for a button eaten by a pointer-events panel never fires; `Input.Keyboard.Down("mouse2")` reads the same gated store; `Input.AnalogLook`/`Input.MouseDelta` are hard-zeroed. A hold-to-look mode must actually lock the cursor. **Trap:** raw `Mouse.Delta` is NOT gated like `Input.MouseDelta` — a camera consuming `Mouse.Delta` directly keeps spinning under a visible cursor; gate it on your own UI-open state. **Per-frame `Mouse.Visibility` write race:** two components both asserting Visible/Hidden every frame race by update order — publish a static "dragging" flag so other asserters skip their write while it's up.

- **Chase camera reading raw fixed-tick position causes model sawtooth** — the raw field is a 50 Hz staircase; read `chr.WorldPosition` (context-sensitive interpolated getter) instead for smooth per-frame tracking.

- **An `Input.config` action bound to an editor/host-reserved key never fires during in-editor Play — the host captures it first, silently, no error/log.** Confirmed reserved set (grows over builds): `F3`/`F7`/`F8` are `ShortcutType.Window` editor shortcuts (toggle-fullscreen / pause / eject — see `sbox-knowledge/tooling.md` → "Editor hotkeys"); **`F1`/`F2`/`Escape` are also host-stolen in practice** (owner playtest 2026-07-14 on — Help/World/`Esc` never reached game input even though F1/F2 had zero `[Shortcut]` hits in the 26.07.08e tools grep; treat the Shortcut grep as a LOWER bound, not the full capture map). **The capture map also DIFFERS between the editor and the published/standalone client:** `F4` reached in-editor Play for weeks, then was dead in the shipped sbox.game build (owner field report 2026-07-16, telemetry toggle — the client appears to reserve F-keys for its own overlays; not yet re-verified in-client after the rebind, so treat the exact client capture set as unconfirmed). An in-editor Play test is therefore NOT sufficient proof for an F-key bind. **Fix:** bind game/UI hotkeys to plain letters, full stop (vp: Help=`I`, World=`M`, HideHud=`H`, Telemetry=`L` ex-F4). Escape for in-game close = `Input.EscapePressed` + set false to consume (`g-game-input-escapepressed-real-getset-consumable`), not an `Input.config` bind. Verify every new binding in a real in-editor Play session AND once in a published build.

- **A mouse-look camera reads `Input.AnalogLook` = Pitch/Yaw 0 (camera never turns) unless the cursor is LOCKED to the game via `Mouse.Visibility = MouseVisibility.Hidden` — and the DEPRECATED `Mouse.Visible = false` does NOT lock it.** `Input.AnalogLook` (which `ComputeAnalogLook` derives from the mouse delta) only accumulates a delta while the cursor is captured; a free/interactive cursor yields zero. The deprecated `Mouse.Visible` bool is the trap: probed live ( freecam, 26.07.08e), `Mouse.Visible = false` resolves to `MouseVisibility.Auto` with `Mouse.Active = True` (cursor still interactive, NOT locked), so AnalogLook stayed zero and a hold-RMB-to-look freecam did nothing. Only `Mouse.Visibility = MouseVisibility.Hidden` gives `Mouse.Active = False` — the "locked to the game" state AnalogLook needs (engine XML: `MouseVisibility.Hidden` = "locked to the game and cannot interact with UI elements"). **Fix:** drive the cursor with `Mouse.Visibility` (`Hidden` while looking, `Visible`/`Auto` otherwise), never the deprecated `Mouse.Visible`. NOTE this CORRECTS an earlier claim that `MouseVisibility.Hidden` is "byte-identical to `Visible = false`" — it is not; `Visible = false` → `Auto`, not `Hidden`. Probe recipe: a ConCmd that sets each and logs back `Mouse.Visibility`/`Mouse.Active`.

- **`Input.Pressed(...)` edges (gear shift, fire, jump) are FRAME-scoped — reading them inside `OnFixedUpdate` drops or double-fires them, because the fixed step runs zero, one, or several times per rendered frame depending on framerate vs the 50 Hz tick.** The engine sets the "pressed this frame" flag once per frame; a frame with no fixed tick loses the press, a frame with several fires it twice. **Fix:** latch the edge in `OnUpdate` (per-frame) into an instance bool, then CONSUME + clear it in the fixed-step logic — a frame with no fixed tick keeps the latch until the next one, so nothing is lost at any framerate. Level-triggered reads (`Input.Down`, e.g. handbrake/throttle) are fine to read directly in `OnFixedUpdate`; only edges need the latch. Verified live ( sequential manual-shift, 2026-07-15): keyboard E/Q shift-up/down latched in `VehicleController.OnUpdate`, consumed in `ReadInput` (fixed step). Sibling trap when the SAME input seam is also driven by a scripted source (a test pilot / `InputOverride` value-struct that carries the shift bits): edge-detect the COMBINED per-tick request against a `_prev` bool so a source that HOLDS the bit across ticks still shifts exactly once — the latched live path is already a one-tick pulse, so one unified rising-edge detector covers both device and pilot without a branch. **Re-confirmed in a second project ( M14 grapple, 2026-07-16):** the grapple's `Attack1` fire was sampled with `Input.Pressed("Attack1")` inside the item's fixed-tick `Simulate` (via `.OnFixedUpdate → SimulateOwned`) and did NOTHING with a real mouse, while the synthetic-input smoke path worked — the tell that the difference is the frame-scoped edge, not the fire logic. Fix identical: latch press/release in `.OnUpdate` (same place the hotbar keys already sample, which is why THEY worked), consume in the fixed tick. Tidy detail: on the frames the char-input context isn't live (menu open / not possessed), clear the latch so a stale edge can't fire on re-entry. **CORRECTION ( round-3 owner playtest, 2026-07-16):** the frame-side latch ALONE did NOT resolve the grapple — the owner reported it still "not functioning in the slightest," i.e. a SYSTEMATIC 0% failure, not the intermittent drop the frame/fixed edge theory predicts. Two things worth internalizing: (1) a level `Input.Down("Attack1")` read STRAIGHT in the fixed tick is reliable here (the mover already reads `Input.Pressed("Jump")` in `OnFixedUpdate` and jumps never drop), so the "fixed tick can't read the edge" framing is too strong — LEVEL reads are fine fixed-side; only the frame-scoped `Pressed/Released` edges are the hazard, and you can reconstruct the edge fixed-side from your own `_prev` bool. (2) A 100% failure with a WORKING synthetic-input path (which bypasses the device edge) points AWAY from edge-timing and toward the real device input never reaching game code at all (UI consume / binding / gate) — instrument every hop with bounded logs and let a real click name the dead hop, rather than assuming the latch is the fix. The round-3 change kept the frame latch AND added a belt-and-suspenders fixed-side level-`Down` edge OR'd into the context, plus a per-hop liveness log; root cause pending an owner click on the instrumented build. **RESOLVED (2026-07-16, engine 26.07.08e):** the input was NEVER the bug — the per-hop liveness logs (read back from the editor console via the `read_console` MCP tool, since game-code `Log.Info` was not reaching the on-disk log files this session) showed the owner's real clicks advancing EVERY input hop: `[wb] item: primary->ctx CONSUMED sel=Grapple held=True` and `attackDown=True`, with `[wb] grapple: fire` running on every click. The frame/fixed edge plumbing all worked. The real cause was DOWNSTREAM of input: the fire trace was a zero-radius `Scene.Trace.Ray` that misses the voxel terrain collider (`hit=False` every time) — see `g-game-zero-radius-ray-misses-voxel-collider` in `m9-character-trace-mover-on-a-coarse-collision-voxel-world.md`. LESSON that this whole entry validates: hop instrumentation is what finally located it — the decision rule "atkDown advances but fire/hit don't -> trace layer, not input layer" is exactly what the counters revealed. Don't keep re-fixing the layer the logs already cleared.

- **A per-named-action DIGITAL bind resolver DOES exist — `Input.GetButtonOrigin(string action, bool)`, `Input.GetGlyph(string action, InputGlyphSize, bool/GlyphStyle)`, and `Input.GetLocalKeyName(string)` — confirmed present in the installed SDK's own `bin\managed\Sandbox.Engine.xml`.** This complements (doesn't contradict) `g-game-there-public-action-analog-trigger-axis` above, which is specifically about the ANALOG axis having no per-action overload; the plain digital "what key is this action bound to right now" query is a real, documented API. XML doc for `GetButtonOrigin(string, bool)`: *"Returns the name of a key bound to this InputAction... could return `SPACE` if using keyboard or `A Button` when using a controller."* `GetLocalKeyName(string)` is described as converting a button code to "our best guess at what's painted on the physical key cap," and `GetGlyph` returns a controller-vendor-aware glyph texture ("update your UI with this every frame, it's very cheap to call"). **Caveat: existence was confirmed by reading the XML doc comments only — NOT runtime-verified in an editor session** (KeybindLegend HUD panel task, 2026-07-16, had no editor MCP access to check the actual rendered string/glyph for e.g. a mouse-button action). Before wiring a live keybind-legend UI to this instead of a static string table, verify in-editor what `GetButtonOrigin("Attack1")` actually prints for a `mouse1`-bound action (raw SDK examples only cover a keyboard/controller-button action) — if it reads well, it auto-updates across rebinds for free; if not, a static (Action, Key, Label) table stays the safer default.

- **Copying `Input.Down("ActionName")` interaction code between s&box projects is unsafe — action-to-physical-button bindings live in each project's `Input.config` and DIFFER between projects.** Concrete case: binds `Attack1` to mouse1 (LEFT); binds `Attack1` to mouse2 (RIGHT) and `Attack2`/`Grab` to mouse1 (LEFT) — so map-editor interaction code ported from had pick/drag and retype running on INVERTED buttons, a silent live failure no headless build can catch (the code compiles fine; only the button feel is wrong). Fix: route copied interaction code through NAMED action constants (never assume which physical button an action name maps to) and re-derive the action-to-button mapping from the TARGET project's `Input.config` at port time — don't trust memory of "how it worked in project X". Verified: both projects' `Input.config` read side-by-side and the inversion confirmed live.

- **On a STEPPED voxel/terrace world the third-person occlusion trio's "tag-exclude thin structure" leg has no target — the terrace EDGES themselves are the transient occluders, so replace it with transient-sliver rejection + a boom floor.** The documented third-person fix ("ease asymmetrically and tag-exclude thin structure") assumes discrete thin members (beams/ribs) you can tag `camstruct-ignore`. Descending a coarse terraced hill there is nothing thin to tag — every 0.25 m step edge behind the camera is a one-frame occluder, and a snap-to-every-hit boom "bops around close". The terrain-adapted trio: (1) ease the occlusion-limited boom asymmetrically (pull IN fast k~20 but not instant, recover OUT slow k~6) and SNAP on first acquire; (2) TRANSIENT-SLIVER REJECT — a shortening < ~0.5 m appearing from a clear frame must persist a short confirmation window (~3 frames) before it's honored (a big cut / real hill still reacts immediately); (3) FLOOR the boom (~1.2 m at 0.65 scale, but never override a shorter deliberate zoom) and lift the pivot slightly when forced short so you look over the terrain lip. Trace a small SPHERE (0.2 m) from the FOCUS pivot, not a point from the body root (a point trace on stepped terrain flickers worse). Code-verified; feel + `[wb] camboom` variance pending an owner hands-on descent.

- **A third-person camera occlusion pull-in (sphere-trace focus->camera that shortens the boom on a hit) THRASHES the zoom during a BAR giant-swing: the character orbits the bar frame, so the crossbar + support posts re-enter the eye-line every revolution and snap the boom IN then ease OUT = a visible zoom in/out.** ' player camera occlusion trace excludes `player`/`grabpoint`/ `camstruct-ignore`, so a normal swing crossbar (tagged `grabpoint`) is ignored — BUT the playground's `UpgradeBarToSwingbar` DEMOTES the crossbar collider off `grabpoint` (moving the swing point to a separate collider-less anchor), leaving the crossbar + `kit_bar_frame_col*` posts as UNTAGGED structure the trace still hits. Per-frame telemetry: on each `kit_bar_frame_col2` crossing (at anchorD~0.05 m) the boom collapsed 4.74 -> 1.48 m (approachK 22 pull-in) then crept back over ~1 s (recoverK 6) — the owner's "zooming in and out". Fix (tag-INDEPENDENT so it survives the demote, general so it also drops enclosure gym-bar posts): while swinging, IGNORE an occlusion hit whose point sits within a compact radius (1.6 m) of `SwingAnchor` — the pivot apparatus the character spins around, not a wall it swings toward (walls lie a full arc away and still pull in). Gate it on swing state so ground/air/climb occlusion is byte-for-byte unchanged (zoo-safe). Consistent with the existing rafter-jank rule: a thin bar briefly clipping the view beats the boom snapping every revolution. Verified live: after the fix the same col2 crossings log ign=True and the boom holds a smooth 4.0->4.8 m curve; rope-swing + ground-run unaffected.

- **A third-person occlusion pull-in makes the camera JANK when climbing a structure that has a block/ledge/cap on top: as the character nears the top, the sphere-trace focus->camera hits the structure's OWN cap/column right beside the focus and slams the boom toward 0, and that residual tiny boom then carries one state later into the mantle->Air flip as a near-geo(roof) FIRST-PERSON flash.** Player camera telemetry on a tower climb: `clamp=kit_climb_tower_r1_h4_col1 boom=0.75/0.01` during Climb, then `camera fp ENTER reason=near-geo(roof) boom=0.01 state=Air` -> `EXIT boom=3.40` ~0.3 s later = a zoom-in-then-FP-flicker exactly at the top-out. The climb FP-enter-hold multiplier (`CameraClimbFpEnterHoldMul`) doesn't help because the flash fires in AIR (one state after ExitClimb), where the long hold no longer applies. Fix is the CLIMB analogue of the swing occlusion-ignore (`g-game-camera-occlusion-thrashes-swing-anchor`): while in Climb (and for a short ~0.45 s mantle grace after, latched camera-locally so no controller state surface is needed), IGNORE an occlusion hit whose point sits within a compact radius (2.0 m, covers the fattest climb prop + its cap) of the FOCUS -- a structure that close to the chest WHILE climbing it IS the climb surface, never a wall a safe distance away. Killing the boom-slam removes the downstream FP flash for free (boom stays ~climb distance, so near-geo never trips). Gate STRICTLY on climb/mantle state so ground/air/swing is byte-for-byte unchanged (zoo-safe: it HELPS the enclosure north-wall NodeClimb the same way). Verified live: 0 near-geo FP flashes and 0 boom-slam clamps across the full climb suite (11/11, x3); ground/swing unaffected.

- **In play-in-editor, a cursor that flashes over the viewport on mouse clicks can be the EDITOR's own cursor — game-side `Mouse.Visibility` never changed, and no game code will ever "fix" it.** Split-the-stack proof: (1) a game-side state probe (`Mouse.Visibility`/`Mouse.Active` + every UI gate flag) reads Hidden/locked/clean at idle AND a self-triggering anomaly logger gets ZERO hits across a full repro session; (2) input-edge logs show every press/held DELIVERED to the item. Both clean means the flash is editor-shell rendering, cosmetic, absent in a published build. Rule: before hunting a play-in-editor cursor/input bug in game code, run a game-side state probe + input-edge logs; if both are clean, stop — the artifact is the editor, not your code.

- **`GameObject.Tags` inherit to ALL descendants, so a `CameraComponent.RenderExcludeTags` exclusion on a tagged parent culls every CHILD renderer too** — cosmetics (muzzle flash, mist, glow) attached as children of a first-person-hidden mount silently vanish in FP along with the gun body. If a child must stay visible while its parent hides, it cannot live under that parent — use the viewmodel parallel-copy pattern.

- **`Rotation.LookAt(forward)` (single-arg) only special-cases the EXACT-vertical forward — a near-vertical normal is left on an ill-conditioned world-up basis.** `LookAt(forward)` returns `LookAt(forward, Vector3.Left)` only when `forward.WithZ(0).IsNearZeroLength`, else `LookAt(forward, Vector3.Up)`. A steep-but-not-vertical normal (88-degree slope) keeps `up = world-up` almost parallel to forward, making the roll unstable. For a projected decal or surface-aligned object, build an explicit orthonormal frame: choose a reference vector not parallel to the normal, cross-product for tangent and bitangent, then `LookAt(normal, computedUp)`.

- **A per-entity component that reads `Input.Pressed`/`Input.Down` unconditionally in its own `OnUpdate` is reading GLOBAL input state once per INSTANCE — harmless with one entity on screen, but a single keypress fires the action on every non-networked instance at once once there are many.** A vehicle controller component (one per car) read a named action to trigger repair-and-respawn in its own per-frame update, gated only on `IsProxy` (a network-replication check). In single-player/local testing with one car that is exactly correct. In a multi-car arena with several AI-piloted instances of the same component — none of which are network proxies — the SAME keypress fired on every instance independently: one press repaired and teleported an entire multi-car field back to its spawn points, which reads as "half the arena just got fixed for free" rather than an input bug, because nothing in the log points at input at all. **Fix: gate any global input read inside a per-entity component on genuine local ownership (the player's actively-controlled entity), not merely on network-proxy status** — `IsProxy` answers "is this replicated from elsewhere," not "should THIS instance, among several local ones, be the one responding to a keypress." Any per-entity component with an unconditional `Input.*` read is safe only as long as the entity count for that type stays at one; audit it the moment a design calls for more than one on screen at a time.
