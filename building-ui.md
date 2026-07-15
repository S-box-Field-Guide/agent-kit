# Building UI — skill pack

> Lane pack. Load `_core.md` first, then this file. Denser than the full articles by design;
> for a matching bullet's full write-up, follow that gotcha's article link in `coverage.md`
> (full articles live on the Field Guide website, not in this pack). Sanitized public
> advice; unconfirmed details marked `(needs verification)`. The sync appends new bullets here.

## C# & razor

- **`.razor` files do NOT go to the global namespace.** Plain `.cs` classes without a
 namespace do; razor classes get a RootNamespace/folder-derived one. Fix: `@namespace X`
 in every .razor + `global using X;` in Assembly.cs. Symptom: "type Hud not found"
 from C#, or razor resolving the WRONG type (see next).
- **Never name classes after Sandbox built-ins.** A global-namespace `PlayerController`
 compiles, but razor resolves `Sandbox.PlayerController` first and you get baffling
 "no such member" errors. Check the name against the Sandbox API before creating
 player/camera/inventory-ish classes.
- **Interface-based scene scans are unreliable.** `Scene.GetAllComponents<Component>
 .OfType<IMyInterface>` compiled but returned nothing at runtime. Enumerate concrete
 types explicitly (`GetAllComponents<CropPlot>`, etc.) and union them.
- **`BuildHash` is the razor re-render trigger** — hash *everything* the markup reads,
 or the panel silently goes stale. Cheap trick: `HashCode.Combine` nests for >8 values.
- `[Sync]` = owner→proxies; `[Sync(SyncFlags.FromHost)]` = host→all; guard sim code with
 `if (IsProxy) return;`. Networked props are runtime-only, never saved to scenes.
- **`GameObject.NetworkMode` defaults to `Snapshot`** (per-object scene-snapshot
 networking), NOT `Never` — confirmed in `Sandbox.Engine.xml`. A scene-wide singleton
 (world state everyone reads, only the host mutates — chaos meters, day/night clocks,
 run stats) does NOT need `NetworkSpawn`/`NetworkMode.Object`: just let the object's
 `GameObject` build identically on every peer (e.g. from a bootstrap/spawner that
 runs the same at scene load on host and every client, *before* any lobby exists), tag
 the authoritative fields `[Sync(SyncFlags.FromHost)]`, and manually gate every mutation
 with `if (Networking.IsActive && !Networking.IsHost) return;` — the engine does NOT stop
 a non-host from writing a FromHost field locally, it just gets steamrolled by the next
 incoming snapshot, so the manual guard is still load-bearing. This is a different recipe
 from the per-owner-object pattern (`NetworkSpawn(owner)` + `IsProxy` guard) — don't reach
 for `NetworkSpawn` when there's no per-client owner, only one shared host-owned truth.

- `Json.Serialize` / `Json.Deserialize<T>` (Sandbox's) + `FileSystem.Data` for saves —
 missing JSON fields land as defaults, so append-only save evolution is safe. Keep
 enums append-only too (we extended `AnimalKind`/`WaterDeviceKind` safely).
- `Mouse.Visible = true` is obsolete but still functional — fine for cursor-driven games
 until the replacement API is obvious.
- **No runtime clipboard API is reachable from game code.** The only clipboard write API
 in the whole install is `EditorUtility.Clipboard.Copy(string)`
 (`addons/tools/Code/Utility/ClipboardTools.cs`) — editor-only, not referenced by any
 game csproj, and there's no JS/browser interop (`navigator.clipboard`, `execCommand`)
 in the base UI library either. Verified by reflecting every DLL the game csproj
 references (`Assembly.LoadFrom` + catch `ReflectionTypeLoadException` to get a partial
 type list instead of a hard throw on a big engine DLL — a straight `GetTypes` throws)
 AND grepping the full engine source tree for `Clipboard`. Degrade to "select the text
 and copy manually" — don't ship a Copy button that silently no-ops.
- **`TextEntry` (not a raw HTML `<input>`) is the house control for text entry**, and it
 already handles Enter internally: `OnButtonTyped` fires `CreateEvent("onsubmit", Text)`
 on Enter, so razor binds it the same way as `onclick` — `onsubmit=@Method` (plain
 no-arg Action), with live edits via `OnTextEdited(string)` (not a Blazor
 `ChangeEventArgs`). Reaching for standard Blazor `<input onchange=@(e=>...)>` compiles
 (the AspNetCore.Components types are real) but isn't how this engine's own UI works —
 grep `addons/base`/`addons/menu` for a live `onsubmit=`/`TextEntry` usage before
 guessing (e.g. `MainSearchBar.razor`, `ChatPanel.razor`).
- **A client-local screen effect (fullscreen fade/flash) driven from HOST-side game code
 must gate on the LOCAL player identity AND still run its side-effect when no overlay
 exists.** one project's catch→respawn fade: a `ScreenFade : PanelComponent` on the gameplay
 HUD registers a static `Instance` on OnEnabled (cleared on OnDisabled), exposing
 `FadeOutIn(legSeconds, hold, onMidpoint)`. The guard (host authority) calls it on a caught
 character, but the fade must only darken the CAUGHT player's screen — gate the visual on
 `Character.Instance == caughtCharacter` (Instance is the local non-proxy body), while the TELEPORT
 (WorldPosition/Velocity/BreakStance) runs unconditionally so the host moves the authoritative
 body and the transform replicates. TWO null-safety rules make it robust: (1) if
 `ScreenFade.Instance` is null (menu/headless — HUD not mounted), `FadeOutIn` must STILL invoke
 `onMidpoint` immediately (a missing overlay must never swallow the respawn side-effect); (2)
 fire the midpoint callback exactly once (`_midpointFired` latch) at full black, since the
 teleport is where the player-invisible jump happens. The overlay is `pointer-events: none` so
 it never eats input, and re-triggering mid-fade continues from current darkness (don't reset
 alpha to 0). HANDOFF cost: the HUD-owner must add `ui.Components.Create<ScreenFade>` to the
 gameplay HUD GameObject in Bootstrap — until then catch-respawn still teleports (no fade) via
 rule 1.
- **`@ref="_field"` on a bare private field silently never assigns** — only a `CS0649`
 build warning ("field never assigned"), easy to miss in a long log, and the ref stays
 null forever at runtime. Every working `@ref` in the engine's own source binds to an
 auto-property (`Foo { get; set; }`), not a field — use a property.
- **For a razor COLLECTION of stateful child panels, don't `@ref` them — make the child
 self-driving via markup-attribute properties.** A `@foreach` that needs N live child panels
 (character previews, tiles with per-item state) has no clean `@ref` form: `@ref="Method(id)"`
 isn't an assignable target (won't compile), and a per-id field hits the silent-no-assign trap
 above. Fix: give the child component public properties (`ModelPath`, `Selected`, …), set them
 as razor element attributes (`<CharacterPreview ModelPath=@c.Path Selected=@sel />` — razor
 maps attributes to public props, same as `<TextEntry MaxLength=.. />`), and have the child read
 them LIVE in its own `Tick` override. No `@ref`, no owner-side per-frame push loop, and state
 switches (e.g. selected→spin-faster) apply instantly regardless of razor re-render.
- **`ScenePanel` for an in-UI 3D model preview: `World` is settable but `Camera` is GET-ONLY**
 (the ScenePanel owns its own `SceneCamera`). Assigning `Camera = new SceneCamera{...}` (as
 editor Widget code does — there `Camera` is a settable field) fails CS0200 on a `ScenePanel`;
 configure the existing camera IN PLACE (`Camera.World = new SceneWorld; Camera.Position=..;
 Camera.Angles=..; Camera.BackgroundColor = Color.Transparent`). Preview world recipe (verified
 vs the install's `addons/tools/Code/Editor/VisemeEditor/Visemes.cs`, the canonical off-screen
 preview): `new SceneModel(world, model, Transform.Zero)` + `UseAnimGraph = false` +
 `CurrentSequence.Name = "idle"` for direct clip playback + `Update(dt)` each Tick to advance the
 anim; spin by setting `SceneObject.Rotation` each frame; light with 2× `ScenePointLight` + a
 `SceneCubemap(Texture.Load("textures/cubemaps/default.vtex"), BBox…)`. No sibling project used
 ScenePanel before — VisemeEditor is the reference.
- **Never write `@{ }` inside an already-open razor code block** (`@if(...){ }`, `@for(...){ }`,
 etc.) — once inside such a block you're already in C# code context, so a nested `@{ }` is
 invalid and fails `RZ1010: Unexpected "{" after "@" character`. Only use `@{ }` to transition
 IN from markup context. Fix: hoist any needed `@{ var x = ...; }` setup block to BEFORE/outside
 the new wrapping `@if`, or drop the `@` and just use a bare `{ }` once already in code context.
 Hit adding a menu-open visibility gate to an existing panel that had markup starting with
 `@{ ... }`.
- **Sibling `PanelComponent`s on one GameObject have NO implicit z-index/hiding** — DOM/creation
 order in `Bootstrap` is the only separation, so a gameplay HUD panel that should hide behind a
 full-screen menu overlay must actively gate its own render on the menu's `IsOpen`-style static
 flag (`@if (!MenuOpen) { ... }`, with `MenuOpen` folded into `BuildHash` too) — it will NOT
 automatically stay behind the modal just because the modal was created later.

- `Mouse.Visible = true` is obsolete but still functional — fine for cursor-driven games
 until the replacement API is obvious.
- **A freshly-scaffolded project's `Code/Assembly.cs` can be MISSING `global using System;`
 even though `project-setup.md`'s own template includes it — don't assume the stock
 scaffold matches the documented template.** Copying vehicle code (`Math.Clamp`,
 `MathF.Abs`, etc. — used throughout without an explicit `System.` prefix, per house
 convention) into a project whose Assembly.cs only had
 `Sandbox`/`System.Collections.Generic`/`System.Linq` produced 57 `CS0103: The name
 'MathF'/'Math' does not exist in the current context` errors across every vehicle file
 in one build. Fix: always check the destination project's Assembly.cs against
 `project-setup.md`'s template (`Sandbox`, `System`, `System.Collections.Generic`,
 `System.Linq`, `System.Threading.Tasks`, plus the project's own razor namespace) before
 transplanting code from another project, not just after the first compile error.
- **Draggable slider tracks (click-to-jump + drag-to-scrub) on a hand-rolled `PanelComponent`
 slider — the engine's own `SliderControl`/`ColorHueControl` are the reference mechanic.** There
 is no native drag helper you can drop into a `RenderFragment`, but the base library ships the
 exact pattern at `addons/base/code/UI/Controls/SliderControl.razor` (+ `Color/ColorHueControl.cs`):
 value = mouse LOCAL x over the track width, clamped, snapped to step. Verified API for a razor
 `onmousedown`/`onmousemove` handler taking the event: **`MousePanelEvent`** exposes **`.This`**
 (the listener panel — the track), **`.LocalPosition`** (Vector2, PIXELS relative to that panel),
 and the panel's **`.PseudoClass.HasFlag(PseudoClass.Active)`** (true while pressed) and
 **`.Box.Rect.Width`** (local px width) — but there is **NO `.Type`/event-name field**, so to
 branch jump-vs-scrub in ONE shared handler you pass a `bool` per binding (onmousedown→always act,
 onmousemove→act only if Active), not by reading the event type. `frac = Clamp(LocalPosition.x /
 This.Box.Rect.Width, 0, 1)`; snap with `MathF.Round(v/step)*step` (or the engine's
 `float.SnapToGrid(step)`). SCSS: the track needs `pointer-events: all` and a taller (~14px) hit
 area to be grabbable, and set the fill child `pointer-events: none` so events always target the
 track (keeps `LocalPosition` track-relative); drop any `transition: width` on the fill or scrub
 lags. A bare click lands as jump-to-position for free with this design. Zero drag precedent in any
 house project. Note: MCP `editor_camera_screenshot`/`camera_screenshot` can VERIFY the panel
 renders + compiles but CANNOT synthesize a drag — the value-from-position math is a code-read +
 in-hand confirm.
- **scss `@import` of a shared token/mixin file IS supported engine-side, but is NOT compiled by
 `dotnet build` — so a broken import path can't be caught headlessly.** The engine menu addon uses it
 heavily (`@import "/styles/_theme.scss";` virtual root + relative `@import 'vars';` partials, plus
 `$vars` and `@mixin`/`@include`; `@use` has ZERO precedent — stick with `@import`). BUT: no GAME
 project has any `@import`/`$var`/`@font-face` precedent (they all inline `font-family: Poppins,
 sans-serif;` per file), the `/styles/` virtual-root mapping for a game project is unverified, and
 **`dotnet build` only compiles the C#/razor — scss is compiled by the editor/runtime**, so an
 `@import` that fails to resolve produces a broken-looking panel that a headless build reports as GREEN.
 When your only verification is headless, prefer an inline `$token` block copied identically per
 `*.razor.scss` (build-safe, visually proven) over a shared `@import`; reserve `@import` consolidation
 for when you can screenshot-verify.
- **The editor-generated the project `.csproj` is gitignored (`*.csproj`), so a fresh worktree
 checkout has NO csproj to `dotnet build`.** The real one lives only in the editor's working tree with
 reference paths RELATIVE to that location (seven `../` to reach `Program Files`), so it won't resolve
 from a deep temp worktree. To build headlessly in an isolated worktree, write a throwaway
 `Code/<project>.csproj` (itself gitignored, never committed) with the SAME `Microsoft.NET.Sdk.Razor`
 SDK + `<Using .../>` block but ABSOLUTE reference/analyzer/`ProjectReference` paths into the sbox install
 and a scratch `OutputPath` (don't write into the install's `.vs/output` — the live editor may be using
 it). The Razor SDK auto-globs `**/*.cs` + `**/*.razor` under the csproj dir, so it picks up the
 worktree's own sources.
- **Loose `.json` under `Assets/` IS readable at runtime by the GAME assembly:
 `FileSystem.Mounted.ReadAllText("<path relative to Assets>")` + `Json.Deserialize<T>`
 (live-verified in-editor play mode — vehicle part-kit manifest; packaged-build behaviour
 unverified). Zero-attribute binding: name DTO properties byte-for-byte as the JSON's snake_case
 keys (`attach_author_m` is a legal C# identifier) — System.Text.Json matches case-sensitively
 and silently skips unbound JSON fields, so no serializer attributes are needed.
- **A flex-grow `.track` holding a normal-flow `.fill` sized by `width: N%` is UNSTABLE in this
 engine — dragging the fill wider grows the WHOLE TRACK, not just the fill.** The row's layout
 computes the flex-grow item's own content-basis FROM its child first; since the child's width is
 a percentage of that same item, the two feed back into each other and the entire slider balloons
 as the value rises (owner repro: "dragging right makes the whole slider grow wider"). The FIX is
 the engine's own ground-truth pattern, copied verbatim from
 `addons/base/code/UI/Controls/SliderControl.razor(.scss)`: `.track { position: relative; flex-grow: 1; }`
 sizes ONLY against its flex row, and the fill is taken OUT OF FLOW entirely —
 `.fill { position: absolute; left: 0px; height: 100%; }` with `width: N%` — so its percentage can
 never feed back into the track's own size. Verified live via `camera_screenshot` at 0% / 5% / 86%
 fill: constant track width, left-anchored bar at every value. **Do NOT reach for `flex-basis: 0` +
 `overflow: hidden` on the track as an alternative fix** — tried first, compiled fine, but produced
 a lime "diamond/lens" floating near the track's midpoint at EVERY value (including 100%) instead
 of a left-to-N% bar; the `justify-content: center` inherited from the old flow-fill layout (there
 to vertically balance a taller hit-area track) was still being applied to the horizontal axis of
 the now-absolute child, and/or the flex-basis:0 + absolute-child combination broke percentage
 resolution outright — not fully root-caused, just empirically worse. When a redesign restyles an
 existing working widget and something goes visually wrong, diff the STRUCTURE (not just colors)
 against the pre-redesign commit and, if the widget has an engine-shipped equivalent, `find` it
 under the sbox install and copy ITS position/flow pattern — don't invent a new one.
- **`camera_screenshot`'s UI overlay renders at the REAL game-window resolution, not the project's
 requested `width`/`height`.** Requesting a screenshot narrower than the actual editor/game window
 (e.g. 1600×900 while the monitor/window is 2560×1440) silently clips every `right:`/`bottom:`
 anchored absolute-positioned HUD element clean out of the captured frame — they aren't corrupted
 or hidden, they're laid out past the requested canvas edge. Left/top-anchored elements at the same
 time render perfectly fine at any requested size, which makes this look like a real rendering bug
 in the right-anchored panels specifically (it isn't). Fix: request `camera_screenshot` at the same
 resolution as the actual primary monitor/game window (`[System.Windows.Forms.Screen]::PrimaryScreen.Bounds`
 in PowerShell if unknown) before concluding a right/bottom-anchored panel failed to render.
- **`ScreenPanel.ZIndex` controls stacking BETWEEN separate ScreenPanel GameObjects** — set
  it high (e.g. `99999`) to force a full-screen overlay on top of other HUD panels. Each HUD
  component gets its own ScreenPanel GameObject (the "two PanelComponents under one
  ScreenPanel leaves the second unrendered" rule), and paint order between those roots is not
  guaranteed by creation order. The engine's own `SceneTransition` uses `ZIndex = 99999`.
- **To show a loading overlay before a synchronous blocking call, defer the blocking work a
  couple frames.** A razor `onclick` that flips an overlay flag and then immediately runs a
  multi-second synchronous job blocks the main thread before the render pass — the overlay is
  only visible after the freeze (i.e. never). Fix: the click shows the overlay and sets a
  small frame countdown; `OnUpdate` decrements it and runs the blocking work only when it hits
  0, guaranteeing the overlay painted first.
- **CSS `@keyframes` + `animation:` shorthand work in s&box razor SCSS** — a spinner needs no
  per-frame re-render. The engine's own menu addon uses them (`animation: rotation 1s linear
  infinite;` + `@keyframes rotation { … }`). Do NOT drive a loading spinner from a BuildHash
  frame counter; that re-renders the panel every frame. Caveat: SCSS is compiled by the
  editor/runtime, NOT by `dotnet build`, so a keyframes typo is invisible headlessly.