# Writing gameplay — patterns & lifecycle

> Topic sub-file of this lane — router: `writing-gameplay.md` (its "Where everything lives"
> table maps every topic). Load `_core.md` first. Bullets below are moved verbatim
> from the lane pack; the sync appends new bullets for these topics here.

- **Custom components in scene JSON**: `__type` is the plain class name when the class
 has no namespace (e.g. `"GameBootstrap"`, `"GolfHole"`). Keep bootstrap-referenced
 classes namespace-free.

- Scene JSON details: positions/rotations are strings (`"x,y,z"`, quat `"x,y,z,w"`),
 every GO/component needs a unique `__guid`, `Tags` are comma-separated. `IsTrigger`
 colliders + `ITriggerListener` for volumes.

## Component lifecycle

- **`OnAwake` fires synchronously inside `Components.Create<T>`**, before the calling
 code's next line runs. Any spawn helper that does
 `var c = go.Components.Create<Foo>; c.SomeProperty = x;` has already run `OnAwake`
 with `SomeProperty` at its default — derive per-instance state (hashes, seeded timers,
 waypoint indices) from `[Property]` values in `OnStart` instead, which runs on the first
 enabled frame, safely after the spawn helper's synchronous property assignments land.

- **Session-reset for STATIC-ONLY facades (no component of their own): ping their
 `ResetForNewSession` from a boot singleton's `OnAwake`, NEVER its `OnStart`.** Statics
 survive Play→Stop→Play in one editor process, so facades like an Sfx loop registry / a
 scene-scan cache / an item-holder set need a once-per-session clear. The hook ordering is
 load-bearing: `OnAwake` runs synchronously at the `Components.Create` line inside
 Bootstrap's own OnStart (i.e. BEFORE Bootstrap's later lines start this session's loops/
 registrations), while the singleton's `OnStart` is deferred to frame 1 — AFTER Bootstrap
 already started them — so a reset there wipes the fresh session's state it was meant to
 protect. Also reset in the right ORDER of ownership: clearing a shared registry (Sfx loop
 dict) that a peer's still-set one-shot flag guards (WandererNpc's `_plazaMurmurStarted`)
 leaves flag and registry disagreeing → the guarded loop never restarts; reset the flag and
 the registry at the same boundary.

- **The editor MCP port is ONE engine-global preference (`config/tools.json McpServerPort`),
 last editor to set it wins, and the editor AUTO-INCREMENTS past a taken port.** With several
 editors open every port is launch-order-dependent — don't pin fixed port numbers, DISCOVER
 them dynamically and identity-probe. Before ANY mutating call, identity-probe the endpoint:
 `editor_status` must name the expected Project AND `search_tools` for a project-defined
 `[McpTool]` prefix must hit — the project name alone can go stale when owners reshuffle ports.
 If the settings page (Editor Settings → MCP Server) shows Enabled checked but "Not running",
 toggling the checkbox off/on restarts the listener.

- **The s&box MCP tool registry is two-layered: `tools/list` exposes only ~7 entry-point
 tools (editor_status, read_console, search_tools, list_toolsets, describe_toolset,
 call_tool, call_tools); every real engine/project tool is invoked THROUGH `call_tool`
 with {name, arguments}.** Transport is stateless HTTP POST (JSON-RPC tools/call, no
 session/initialize needed). Two return-shape facts: an [McpTool] returning a JSON
 string is NOT double-encoded (the string lands verbatim as the text content block —
 one json.loads gives the object), and screenshot tools return an MCP image content
 block (content[0] = {type:"image", data:<base64 png>, mimeType}) — not a JSON field.

- **Edit-mode `scene_trace` is blind to runtime-built ModelColliders** — chunks freshly
 created by an editor-scene regeneration (ModelRenderer + static ModelCollider via
 Model.Builder.AddCollisionMesh) render fine and list in scene_tree, but a scene_trace
 ray straight through them reports Hit=false in edit mode. Don't use edit-mode traces
 as geometry evidence; trust screenshots (or play mode) instead.

- **A root GameObject named `editor_camera` (bare CameraComponent) appears in the open
 scene once the MCP editor-camera machinery runs** — engine-managed live-session
 artifact, NOT in the .scene file, clones into play sessions as a second enabled
 camera. Harmless so far (the real scene Camera wins the render), but expect it in
 scene_tree/find_game_objects output and don't save the scene assuming the tree is
 clean.

- **Verify a mesh-import scale pipeline in-engine with a spawned 1 m REFERENCE CUBE, not
 by eyeballing a lone prop.** `models/dev/box.vmdl` is a 50-unit, center-origin dev cube;
 spawn it at `WorldScale 0.7874` for exactly 1 m (0.7874×50 u = 39.37 u = 1 m) and, since
 it is center-origin, ground its base by placing the object at `z = 0.5 m = 19.685 u`
 (props exported grounded at z=0 sit at z=0). Put the cube and prop at the SAME y (equal
 camera depth) with a LEVEL camera (pitch 0, yaw ±90) and measure the pixel-height ratio —
 perspective and vertical foreshortening then cancel. This confirmed the project's
 `pine_large` renders ~6.1× the cube (target 6.0 m), i.e. the meters-authored Blender OBJ
 → `import_scale = 39.37` path delivers EXACT in-engine metres with no per-prop fudge.
 A far camera makes a small cube unmeasurable (±3 px on a 30 px cube = ±0.6 in the ratio) —
 frame it to fill a good fraction of the shot.

- **A freshly generated `.vmat`/`.vmdl` batch that has NEVER been compiled must be
 `asset_compile`d over the MCP before spawn — but a successful compile returns
 `{"Success":true, "CompiledFile":"…"or""}` where `CompiledFile` is often an EMPTY string
 even on success** (it only fills in when that call actually did the compile vs. finding it
 already up to date). Gate on `Success`, never on a non-empty `CompiledFile`. All 26
 the project starter-prop vmdls + `atlas.vmat` + a flat vmat compiled Success on first
 try with zero material/remap defects (the both-names remap rule + white-tex+g_vColorTint
 flat recipe held).

- **`System.Array.Clone()` is BLOCKED by the s&box whitelist, but the headless `dotnet build`
 does NOT enforce the whitelist — so a `(float[])arr.Clone()` snapshot compiles green offline
 and only fails on the in-editor compile (`SB1000: 'System.Array.Clone()' is not allowed when
 whitelist is enabled`).** M4's RiverPass/RoadPass snapshotted the heightfield with `.Clone()`;
 `dotnet build ... --no-incremental` was clean, then `compile_status` over the MCP showed 2
 SB1000 errors. Fix: a plain loop copy (`var c = new float[n]; for(i) c[i]=src[i];`) or
 `Array.Copy` — both whitelist-safe. LESSON: the headless build is necessary but NOT sufficient
 for whitelist safety; always gate on the editor's `compile_status` (bump mtime -> poll) before
 trusting a runtime pass. Prime suspects the headless build misses: `Array.Clone`, LINQ corners,
 reflection, various `System.*` helpers.

- **Headless `dotnet build` can report 0 errors while the in-editor Razor compiler has
 real `.razor` compile errors — it is not a substitute for `compile_status` for anything
 touching `.razor` files.** A `.razor` file with genuine CS errors built clean via
 `dotnet build` both before AND after the fix — the headless MSBuild path doesn't
 regenerate/validate the Razor-to-C# codegen the live editor's Roslyn compiler does.
 Plain `.cs` files still error correctly; the gap is specifically Razor codegen.

- **Autopilot progress metrics must be state-gated** - sampling "max height gained" across a
 whole routine counts the ballistic kick-off apex as climb progress (gb_pilot_lab run 1 read
 7.2 m on a 4.1 m tower). Gate progress samples on the state that earns them (Climb/WallRun
 only).

- **The editor console buffer (2000 entries) rolls over during long pilot sweeps** - per-attempt
 telemetry floods it and read_console loses the report lines. Grep the DATED log file instead,
 and the live file is sbox-dev-2026-07-11.N.log (highest N), not necessarily sbox-dev.log.

- **`Component.Active` is a real inherited member** — naming a component's own bool `Active` raises
 CS0108 (`hides inherited member`) and, worse, silently shadows the engine's enabled flag; the editor
 in-compile surfaces the warning even when `dotnet build` was clean. Name a domain flag something else
 (`Armed`).

- **`Scene.GetAllComponents<T>()` does NOT return DISABLED components.** A chase camera pre-created
 `Enabled = false` (so orbit is the boot mode) was then UNFINDABLE by a later
 `Scene.GetAllComponents<CharacterCamera>().FirstOrDefault()` — it returned null, the possess-time
 camera swap silently no-op'd, and the camera stayed stuck at the orbit pose. Two fixes: search for an
 ENABLED sibling (the OrbitCamera) and read the disabled one off its GameObject, OR (cleaner) CREATE the
 transient camera on possess and DESTROY it on release (create-on-enter, not pre-create-disabled). A
 disabled component is invisible to the type-search API.

- **The MCP `camera_screenshot` captures the engine's transient `editor_camera` artifact, NOT your
 render Camera, until a component ACTIVELY drives the render Camera's transform.** In an MCP-driven play
 session there are TWO enabled cameras: the scene "Camera" (your OrbitCamera/CharacterCamera) and a
 cloned `editor_camera`. `camera_screenshot` framed the frozen editor_camera (a fixed wide/sky view), so
 in-character-mode chase changes never showed — until the chase cam actually moved the "Camera" GO, after
 which the screenshot tracked it. For RELIABLE agent screenshots of a specific subject regardless of which
 camera wins, drive `set_editor_camera` to the subject and use `editor_camera_screenshot` (100% under your
 control). Verify a camera is really driving by reading the "Camera" GO's WorldPosition via
 `get_game_object` and comparing to the expected pose — a frozen pose means nothing is driving it.

- **Static facades that bridge editor McpTools ↔ play-mode components MUST session-reset across
 Play→Stop→Play.** A command/report bridge (editor tool POSTs a command into a game-assembly static;
 the play component consumes it and writes a report back) carries STALE state across a play restart —
 a leftover `InCharacterMode = true` made the new session's director skip spawning, so the first
 `wb_walk` no-op'd against a null character. Clear the per-session flags (and drop any un-consumed
 command) from the boot singleton's `OnEnabled` (runs synchronously at Create, before any command is
 read). Same family as the Sfx/HideSpot ResetForNewSession lifecycle rule. Also: `System.Threading`
 (`Volatile`/`Interlocked`) is NOT whitelisted in the game assembly — a plain `int` token compare is
 whitelist-safe and torn-read-proof for int on x64, use that for the bridge's command token.

- **Project `[McpTool]`s that take one STRING JSON param are invoked as `{"<paramName>": "<json string>"}`,
 not as the JSON object directly.** `wb_character(string argsJson)` is called with
 `{"argsJson":"{\"op\":\"probe\",\"x\":480}"}` — passing `{"op":"probe",…}` errors "Unknown argument
 'op'". Same shape as `wb_generate(specJson)` / `wb_brush(opsJson)`. The client's stdout on Windows is
 cp1252 and crashes printing a tool description containing a non-ASCII char (e.g. `∈`) — set
 `PYTHONIOENCODING=utf-8`.

- **Python's `open(path, "w")` on Windows silently uses the legacy codepage (cp1252), not
 UTF-8, unless `encoding="utf-8"` is passed explicitly** — it does NOT raise, it just
 mis-encodes any non-ASCII character (an em dash becomes one wrong byte instead of the
 3-byte UTF-8 sequence). Always pass `encoding="utf-8"` on every `open(..., "w")` in
 codegen scripts emitting em dashes, curly quotes, or other non-ASCII punctuation.

- **MCP play-mode iteration: verify `compile_status` AFTER the mtime bump and BEFORE `play_start`, or play runs
 the STALE assembly.** Two clothing-swap screenshot rounds showed the OLD outfit because play_start fired before
 the in-editor compile of the new source finished — the render "not changing" across a code edit is the tell.
 Also do a clean `unpossess`→`possess` for a fresh run report: a stale bridge report (e.g. reached=3/3 from a
 prior session's 3-waypoint route) surfaces on the first status poll and looks like your new command no-op'd.
 And `wb_walk` arrival is HORIZONTAL-only — a slide/descent leg's target must sit PAST the base of the face or
 it "arrives" mid-descent and ends the leg early.

- **Editor-viewport auto-exposure ADAPTS over wall-clock frames, so two screenshots of a BYTE-IDENTICAL
 regenerated world can differ globally by tens of percent — a stale-render false positive.** After
 fixing the double-root overlap, return-to-start grid hashes were byte-identical but return-to-start
 top_down SCREENSHOTS still diffed up to 26% (worst on the sea sweep: sea +6 floods half the map in
 bright water → auto-exposure darkens → returning to sea 0 and shooting immediately catches exposure
 mid-re-adaptation). It is a GLOBAL brightness/tint shift over identical geometry (verified: two shots
 of the same returned world with a ~2.5 s settle diff to 0.000%). Two fixes in the diff harness: (1)
 SETTLE the viewport before a comparison capture; (2) EXPOSURE-NORMALIZE the pixel diff — match B's
 per-channel mean to A's before thresholding, which cancels a uniform tint but preserves a LOCALIZED
 structural difference (a real stale overlapping world is not uniform and survives). Post-normalization
 noise floor across five sweeps: 0.0-0.21%; real structural staleness reads 15-25% (100x). Same family
 as the WbFpsProbe warmup-skip. The grid hash stays the authoritative return-to-start gate; the
 screenshot diff is the coarse structural one.

- **The editor MCP `editor_camera_screenshot` renders through the `editor_camera` GameObject, NOT the
 game "Camera" — so one project camera's Tonemapping/Bloom/exposure components do NOT grade your shots, and
 the editor VIEWPORT's own auto-exposure normalizes overall brightness.** Consequence for a runtime
 lighting grade (the project WbLighting): brightening the sun/ambient/sky uniformly reads as NO change
 (auto-exposure claws it back); only COLOUR BALANCE and directional contrast survive. Verified with an
 "orange sun" diagnostic — the terrain went fully orange, proving the DirectionalLight IS driving the
 edit-mode render, but a mild warm-white sun looked identical to cool-white because exposure normalized
 the brightness. Also: DirectionalLight (LightColor/SkyColor/FogStrength/rotation), SkyBox2D.Tint and
 EnvmapProbe.TintColor CAN all be set at runtime in EDIT mode and take effect (confirmed via
 get_game_object). But you can't lift the scene into a high-key "chalky bright" look this way — the
 blue stock skybox + baked envmap + viewport exposure cap it; a genuinely bright grade needs a paler
 skybox material or viewport-exposure control.

- **Shared multi-agent working tree: `git checkout -b` branches off wherever HEAD currently is, which a
 CONCURRENT agent may have moved out from under you.** In the project a vehicle-milestone session
 committed its WIP to `m98-vehicles` and left that branch checked out; a look-pass session that then ran
 `git checkout -b m95c-look-rounds` (intending "off main") silently branched off `m98-vehicles`, stacking
 its commits on top of 5 unrelated vehicle commits. Detect via `git reflog` (the "checkout: moving from X
 to Y" line names the REAL base) and `git log --oneline main..HEAD`. Recover cleanly with
 `git rebase --onto main <real-base>` when the two commit sets touch DISJOINT files (verify with
 `git diff --name-only main..<base>`): it replays only your commits onto the intended base and leaves the
 concurrent branch untouched. General: before branching in a shared tree, `git rev-parse --abbrev-ref
 HEAD` to confirm the base — do NOT trust a stale earlier `git status`.

- **s&box EDIT-mode EnvmapProbe ambient FLAPS on/off across wall-clock frames, and a single-frame
 camera_screenshot landing MID-flip applies the probe to only SOME screen tiles - rendering equal-spaced
 SCREEN-aligned rectangles that masquerade as chunk-sized material patches.** the project's
 "rectangular apron tint patches": measured with ZERO scene changes, consecutive captures alternate
 between two global states ~19/255 apart (the probe's uniform ~7% ambient lift), dwell ~seconds; a
 mid-flip capture shows ~67 px screen-axis rows, phase-flipped at a tile column. PLAY mode is stable
 (probe ON) - purely a capture-path artifact. Triage screen-space vs world-space artifacts FIRST by edge
 orientation (world/chunk seams project as DIAGONALS at a 45-deg hero yaw; renderer tiles stay
 screen-axis-aligned even in perspective) and by back-to-back no-change captures (flip-flop = temporal
 race, not content). Guard (tools/wb_gamecam.py): burst-capture, keep the BRIGHTEST frame that has a
 pixel-level twin among the burst - a mid-flip tiled frame has no twin, so it can never be saved, and
 brightest = the stable play-mode state. Bonus finding: the scene-stock probe box is +/-512 u (~13 m) -
 ~1% of the diorama; resize it to enclose world + cameras (byte-identical render when the probe is on).

- **`compile_status` returns `{IsBuilding, Compilers:[...]}` — there are NO top-level
 `Success`/`Errors`/`NeedsBuild` fields.** Each entry in `Compilers[]` carries its own
 `{Name, IsBuilding, NeedsBuild, Success, Errors, Warnings, Diagnostics}` (verified live,
 engine 26.07.08e, ~10 compilers incl. `local.<project>` and `local.<project>.editor`).
 A gate that reads flat fields gets `None` and mis-reports "compile not clean". Reduce
 the array: clean = every `Success==true`, no `NeedsBuild`, nothing `IsBuilding`; judge
 YOUR assemblies by the `local.<project>*` entries.

- **The s&box editor's "Mcp Server Enabled" preference does not reliably persist across editor
 restarts (a force-killed editor never flushes it), and it CANNOT be enabled headlessly — no config
 file, no convar, no CLI flag stores it (verified by byte-searching the install + user profile while
 a sibling editor served MCP).** If the editor restarts, the agent harness is DOWN until a human
 toggles Edit → Preferences → MCP Server (port table: the project 7200, one project 7269). Budget
 for this in any round that spans an editor restart: probe `editor_status` FIRST, and if the port is
 dead, surface one line to the owner ("toggle MCP on") instead of burning the session hunting for a
 bypass — a project-side auto-enable hook is possible in principle (set
 `EditorPreferences.McpServerEnabled` from an `[EditorEvent.Frame]` once-guard in the Editor assembly)
 but is a persistence mechanism the owner must explicitly approve first.

## Save / load

- DTO classes + `Json.Serialize`/`Json.Deserialize<T>` + `FileSystem.Data.WriteAllText/ReadAllText/FileExists`.

- Mark runtime-placed structures with a `PlacedBuildable { BuildId }` component;
  save loop reads component state per GameObject, load loop respawns through the
  same factory used for building — one spawn path, no drift.

- Static world stays deterministic (fixed RNG seed) so only deltas need saving
  (e.g. chopped-tree indices, not tree positions).

- Missing JSON fields → C# defaults, so guard restored values (`x <= 0 ? 1f : x`)
  and keep enums append-only. Autosave on the natural checkpoint (sleep).

> _(Section restored 2026-07-13 from the pre-split code-patterns pack.)_

- **A ground-vehicle "top speed" telemetry field computed from 3D rigidbody velocity
  length balloons into free-fall speed** when the car drives off the edge of a finite
  ground collider. A plausible-looking `maxSpeedMs=165` was actually the car plummeting
  off the runway — `speed = Velocity.Length` includes the Y (gravity) axis. Fix: report
  `Velocity with { z = 0 }.Length` for a surface-clamped reading. Better: compute and log
  *both* and flag if they diverge (divergence = the car is airborne or off-world).

- **`OnAwake` fires synchronously inside `Components.Create<T>`**, before the calling code's next line runs. Any spawn helper that does `var c = go.Components.Create<Foo>; c.SomeProperty = x;` has already run `OnAwake` with `SomeProperty` at its default — derive per-instance state (hashes, seeded timers, waypoint indices) from `[Property]` values in `OnStart` instead, which runs on the first enabled frame, safely after the spawn helper's synchronous property assignments land.

- **Session-reset for STATIC-ONLY facades (no component of their own): ping their `ResetForNewSession` from a boot singleton's `OnAwake`, NEVER its `OnStart`.** Statics survive Play→Stop→Play in one editor process, so facades like an Sfx loop registry / a scene-scan cache / an item-holder set need a once-per-session clear. The hook ordering is load-bearing: `OnAwake` runs synchronously at the `Components.Create` line inside Bootstrap's own OnStart (i.e. BEFORE Bootstrap's later lines start this session's loops/ registrations), while the singleton's `OnStart` is deferred to frame 1 — AFTER Bootstrap already started them — so a reset there wipes the fresh session's state it was meant to protect. Also reset in the right ORDER of ownership: clearing a shared registry (Sfx loop dict) that a peer's still-set one-shot flag guards (the visitor NPC component's `_plazaMurmurStarted`) leaves flag and registry disagreeing → the guarded loop never restarts; reset the flag and the registry at the same boundary.

- **Migrating process-global world/session STATE off `static` fields onto a scene-owned `Component` (the prereq for host-authoritative multiplayer): keep ONE `public static T Local` pointer to preserve the editor→play handoff — but do NOT name it `Active`.** The state (grid, spec, world root, registries) moves onto instance fields; readers that said `WorldGen.Grid` now say `WorldSession.Local?.Grid`. The static pointer is NOT the shared-state the audit objected to — under deterministic-spec replication each process has exactly ONE local world, so one pointer per process is correct (same role as `.Instance`). Three load-bearing details verified this milestone ( M12.0): (1) **Never name that member `Active`** — `Component.Active` is the engine's enabled flag, so `static X Active` raises CS0108 (hides inherited member) and, in intermediate edit states, `Active = this` fails as "cannot be assigned — read only"; use `Local` / `Instance` / `Current`. (2) **Set the pointer INSIDE the regenerate/build path** (`Local = this;`), not in `OnEnabled` — that reproduces the old "last-generated-wins" static semantics exactly, incl. the editor→play spec handoff: the edit-scene component instance stays alive across the boundary (same process, no assembly reload), so play-mode boot reads the authored spec off `Local` BEFORE it `ResolveFor(playScene)`-creates the fresh play session. (3) The editor MCP tools and the play-mode boot both resolve the session by SCENE (`Scene.GetAllComponents<T>.FirstOrDefault` or create a holder GO), so edit and play each own the right instance. Gate a pure refactor with the grid-hash: byte-identical before/after proves no gen drift. The leftover `[Sync(FromHost)]` on the spec field is the NEXT milestone — don't half-build replication in the de-static pass.

- **Frozen-world / session-mode enforcement lives in ONE code choke-point, not in hidden UI - put the explicit mode enum on a menu-level component (NOT the world/session state object) and guard the single regenerate method + the edit driver on it.** M12.3 (``): a `static SessionMode Mode` (Authoring/Hosting/Joining/Joined), reset to Authoring in `OnEnabled` (statics leak across Play->Stop->Play), read by everything that must behave differently while a server is live. The D5 lockdown is enforced in CODE: `WorldSession.Regenerate` returns `Error="world is live - stop server to edit"` when `Mode` is Hosting/Joined (the ONE method every boot/UI/MCP regen funnels through, so no hidden path bypasses it), and `BrushController` refuses to arm off-Authoring - UI hiding of the sliders is cosmetic, the guard is the enforcement (audit lesson). The load-bearing subtlety: the CLIENT's join-time regen must be ALLOWED, so the frozen check keys on Hosting/Joined only and the client regenerates while in the transient `Joining` mode (freeze applies once it flips `Joined` on handshake-OK). "Launch Server" does NOT re-run generation - it re-publishes the already-authored spec (`PublishFrozenSpec` sets the `[Sync(FromHost)]` NetSpecJson), so the frozen guard never fights the freeze itself.

- **A cached Component/GameObject reference guarded with `== null` still NREs after the object is DESTROYED — `== null` misses destroyed objects; only `IsValid` catches them. Session teardown is when it bites: a disconnected client tears down its local pawn, and every per-frame consumer holding `Target == null` guards (cameras especially) throws every frame ("Exception when calling 'Update' on ...").** : the player camera component's OnUpdate guarded `Target == null` then read Target.WorldPosition; a stale -joinlocal client whose host dropped NRE'd continuously (red toast in the game window). The same file already used the IsValid convention elsewhere — the trap is one old guard. Fix: `if (!Target.IsValid) Target = ...; if (!Target.IsValid) return;` — audit per-frame consumers of destroyable (especially networked) objects for `== null` guards.

- **A visual component that `Model.Load(ModelPath)`s inside `OnStart` must ALSO reload when `ModelPath` is assigned after create — don't trust "OnStart is deferred past the spawn helper's property writes" alone.** : the network manager's spawn helper created the character visual component and then assigned its `ModelPath` from the roster, while the visual component's default was still the retired Tripo hero rig vmdl. Selecting Duke (Blender) on the home screen still spawned the old 3D asset. Fix: (1) default `ModelPath` to the shipping Blender skin's rigged vmdl; (2) property setter calls `ApplyModel` when the skinned renderer already exists so a late/racey assignment (or a mid-session skin swap) actually swaps the mesh; (3) roster ships Blender skins only — Tripo/Forge hero/cute/scout/blocky stay on disk for zoo/legacy but off select+spawn. Pairs with `g-game-onawake-fires-synchronously-inside-component` (Awake is sync; this is the asset-load half of the same Create→configure pattern).

- **A director that RE-adopts an entity by reading its `static Instance` singleton is TRAPPED the moment that entity's GameObject was DISABLED — because the singleton is claimed in `OnEnabled` and NULLED in `OnDisabled`, so a re-adopt poll that gates on `Instance.IsValid` returns false FOREVER and the entity is never re-driven.** M16 live-regen: the host's "Edit world" un-possess (`ExitCharacter`) sets `_character.GameObject.Enabled = false`; `.OnDisabled` does `if (Instance==this) Instance = null`. When the edit is cancelled/confirmed the D7 auto-possess poll re-fires and calls `EnterCharacterNetworked`, whose first line was `if (!.Instance.IsValid) return false;` — but the singleton is now null, so the host stayed un-possessed in the orbit/generator view with no way back into the game (owner: "I can't get out of edit world… Back-to-play looked dead; Reshape dumped me on the authoring footer"). The mechanism is invisible: nothing errors, the poll just no-ops every tick. **Fix: the director already retains its OWN direct reference to the entity (disabling a GameObject does NOT invalidate a held component ref — `IsValid` is not-destroyed, not enabled), so fall back to it and RE-ENABLE:** `var chr = Instance.IsValid ? Instance : (_character.IsValid ? _character : null); if (!chr.IsValid) return false; chr.GameObject.Enabled = true;` — re-enabling re-fires `OnEnabled`, which re-claims `Instance`. General rule: a singleton claimed/released on the enable boundary is a *presence* signal, not an *identity* store — any code that must re-adopt an entity across a disable/re-enable must hold a direct reference, never rely on the enable-scoped singleton being non-null.

- **An McpTool that declares a single `argsJson` string parameter must have its real args passed as a JSON-ENCODED STRING inside that field — passing the logical args at the top level fails with "Unknown argument 'op' - this tool takes argsJson (string, optional)".** 's `` / `` / `` / `` test tools take one opaque `argsJson` (or `opsJson`/`routeJson`) string and parse it themselves, so `{"op":"launch"}` at the top level is rejected — the correct call is `{"argsJson":"{\"op\":\"launch\"}"}` (a stringified JSON value, double-escaped through the outer JSON). Runbooks that write the shorthand ` {"op":"launch"}` mean *that op inside argsJson*, not a top-level `op` argument. Same wrapper for every string-param harness tool in this project.

- **When two modules share a packed 2-component convention (e.g. a manifest `DoorClearanceM = (x=depth, y=width)`, same axis order as `FootprintM`), a CONSUMER that pairs `.x`/`.y` the opposite way builds silently-wrong geometry that no compile catches.** 's `TownPass` built its door-clearance rect with `.x`→tangent-half-width and `.y`→outward-depth — the transpose of the manifest convention its own `TownAudits` reconstructed. The trap is invisible for near-square values and only bites asymmetric ones. Defence that worked: have the AUDIT reconstruct geometry independently from the MANIFEST convention (not from the producer's internals) — the two then disagree exactly when the producer's axis pairing is wrong, turning a silent bug into a failing audit line. Fix the producer to the single documented convention; don't "fix" the audit to match the bug.

- **A scripted-autopilot maneuver driven by a FEEDBACK controller (position-pursuit weave / yaw-settle) is marginally stable on grip-marginal cars, so it is NOT byte-deterministic like an open-loop maneuver — and adding derivative (yaw-rate) damping to "stabilize" it can make it WORSE.** Two traps bit in the slalom (pure-pursuit `steer = angErr*gain`). (1) DETERMINISM IS PER-ATTRACTOR: the first run after a car/maneuver switch inherits perturbed spawn/physics state (hatch 19.58 s / yaw 165) then converges to a clean attractor on repeat (14.92 s / yaw 36, bit-identical ×2) — both values deterministic, state carried across Play→Stop→Play. A single closed-loop FAIL therefore needs a confirming re-run; gate on the converged attractor or add a spawn-settle phase. (2) A PD term BACKFIRES: a slalom WANTS sustained yaw, so subtracting steer ∝ yaw rate fights the rotation the weave needs and drags the car OUT of a stable basin — the coupe completed cleanly at cruise 15 with plain proportional pursuit, then DNF'd at 15 once a yaw-rate damp term was added. Fix a "car can't hit the band" red by proving it is GRIP-limited (at the failing cruise the coupe topped ~17 m/s while asked for 20 and limit-cycled — no pilot beats that) and re-anchoring the through-gate speed to a measured grip-followable cruise, not by re-tuning the controller.

- **An editor-bridge autopilot command posted BEFORE play mode starts is silently dropped, even though the tool's own response says 'command queued; it runs once play mode starts'.** : posting the route while stopped returned directorAlive:false + the queued-note, then after play_start the director spawned but idled at waypointsTotal=0 for 2+ min — the queue does not survive the play-mode boundary on this build (fresh session, no stale director). Fix: play_start FIRST, wait ~2-3 s for directorAlive:true in the status readback, THEN post the walk — it engages immediately (4/4 waypoints, 0 stuck, 0 fall-throughs, 36.1 m in 23.8 s on the 192-cell golden world). If a bridge readback offers a liveness flag, gate the command on it instead of trusting queue semantics.

- **A new MEASUREMENT mode that must sample kinematics per-tick AND author raw input intents cannot follow the calibration/lab "separate data-class + metric hooks" pattern.** That pattern (Calibration/Lab) only drives movement expressible as existing PilotRoutine ops (Teleport/MoveTo/Jump...) and feeds metrics through narrow hooks; the raw intent seam (SetMoveWorld/SetAnalog/the jump latch/ClearIntents/LookYaw) and the per-tick sampler are PRIVATE instance members of, so a mode measuring apex/stop-distance/top-speed while authoring its own moves has no seam to reach. FIX: add the mode as a `partial class ` in a second file -- it gets full access to the private seam with only ADDITIVE wiring in the main file (own convar + `_wanted`/`_requested` flags, a new `Mode` enum member, one Idle-dispatch arm, one abort-track line, one tick dispatch, auto-clear ONLY your own gate on finish). Mirrors the playground gate (commit 66c6070) but with its OWN `Mode` (like Calibration/LabRating) rather than reusing `Mode.Routines`. Do NOT expose the seam publicly so a separate class can it -- that leaks the input seam and invites a second writer fighting the interpreter. Verified: the physics hypothesis-band harness (``,) built this way compiles 0/0 headless and hotloads clean in the live editor.

- **Gate EVERY airborne-derived telemetry metric (airtime, landing latch, contact-loss %) on first real ground contact, and arm "flight" only after ~0.15 s of continuous air — gating just one of them leaves the rest lying.** gated its off-the-edge detector (`_contactlessS`) on first contact but left `airTicks`/`wasAirborne`/`AirtimeS` ungated: the 0.4 s spawn settle-freeze (wheels report ungrounded before suspension touchdown) produced an IDENTICAL 0.44 s "ramp airtime" for every car — spawn settling consumed the jump's one landing event before the ramp, and landing pitch/settle measured the spawn, not the jump. The smoking gun for this class of bug: a physical metric that should differ per car coming back identical across the roster. The 0.15 s arming window also stops suspension flutter/expansion-joint blips from latching a "landing" mid-runway.

- **A "contact loss %" telemetry metric defined as ticks-with-ALL-wheels-airborne reads 0.0 over washboard/rough-ground sections with raycast wheels — the WHOLE car almost never goes airborne over small ridges, individual wheels do.** wave-2: four cars driven over a 20-ridge washboard (0.12 m ridges @ 1.5 m spacing, 10-15 m/s) all measured full-airborne contactLossPct = 0.0, so every rough-ground band authored as "contact-loss 2-8% / 5-15%..." (per-class bounce character) was unmeasurable. The bands' actual provenance was per-wheel IsGrounded loss. Fix: accumulate a per-wheel metric — per tick sum (ungroundedWheels / wheelCount), gated on first real ground contact like the rest of the airtime family, reported as an average % — and assert THAT for rough-ground tests; keep the full-airborne metric for jump tests where whole-car flight is the point. With the per-wheel metric the kart (short travel, small wheels) measured 3.3% while the long-travel cars still read ~0 — a real per-class bounce signature the full-airborne field cannot see. Rule of thumb: on raycast wheels, any rough-ground band under ~20% MUST be a per-wheel metric; full-airborne only moves on jumps/crests.

- **Re-arming a pilot suite in the SAME play session degrades physics-prop routines run over run — the world is only built at boot, so every rerun inherits the previous run's moved props.** throw_cycle measured 4.8 m (PASS) on a session's first runs, then 1.4 m and 0.8 m FAIL on the 3rd/4th re-arms: each run throws a pit ball somewhere new, and the next run's grab picks up a ball from a drifted spot (nearer walls / the throw zone). The suite is rerun-safe only for routines whose subjects are static or self-spawned+destroyed. Official gate evidence for prop routines needs a FRESH play session (or a world rebuild) per run; mid-session re-arms are fine for iterating non-prop routines.

- **Destroying generated terrain/elements while the piloted character hangs on them strands the body in the void — and the NEXT armed suite insta-fails every routine at time=0.0 before any teleport runs.** : lava_run ends hanging on the net at x≈100 m (off the courtyard slab); `pg_terrain 0` then destroyed the world under it, the body fell below the fall-through floor, and the per-tick invariant (checked BEFORE the routine's first teleport step ticks) failed all 20 routines in ~17 s (one per 0.8 s settle). Fix: `` (the unstuck teleport) between tearing down a generated world and re-arming a suite — reset FIRST, then rebuild.

- **An automated movement test that ACTIVATES a speed multiplier must budget the MULTIPLIED runway, not the baseline one — or the scripted body sprints off the world.** M9-C's `boost_cycle` routine granted a ×1.5 run boost and sprinted 2 s east from x=24 on the 60 m courtyard slab (edges ±30 m): the boosted character covers ~22 m in 2 s (vs ~14 baseline), crossed the x=+30 edge at ~0.9 s, and fell into the void — the suite's fall-through invariant FAILed the routine at pos=(35.1,−16.6,−2.0) while the boost mechanics were fine. Fix: start at the arena's far end and sprint along the LONG axis (south end y=−27, north-bound), sized for boostedSpeed×duration + accel ramp + the baseline pass. General rule: any test arena sized "comfortably" for baseline movement is ~1/multiplier too small once the feature under test is armed; also budget the follow-on phase (the post-expiry baseline re-measure runs from wherever the boosted phase ended).

- ****A regression routine that AUTO-SELECTS its venue from procedural terrain (nearest cliff, tallest patch, etc.) and asserts a KNIFE-EDGE movement outcome (a re-grab / catch with a ~0.1 m margin) will flip deterministically the day a cm-scale terrain PASS shifts the geometry — even a "correct, declared" change.** `ledge_walkoff_coyote` (a pilot routine proving a coyote-window jump re-enables the walk-off catch) picked the nearest-origin cliff patch and reused the drop routine's far aim point (3 m out). That sent the body walking off with metres of outward momentum; the catch tick keeps steering outward through the whole up-and-over jump arc, so by the 0.5 m below-lip gate the body is 2-3 m out — far past the controller's `LedgeReach` (0.45 m) — then free-falls ~2 s and only catches OPPORTUNISTICALLY on whatever voxel micro-ledge sits near the bottom (a near-GROUND catch, live: Air->Hang z=6.38 m vs ground 6.28 m = 0.1 m margin). When TERRA-1 island falloff (a declared, correct terrain pass) lowered that lip ~0.25 m, the catch point dropped THROUGH the floor and the body hit Ground first -> the routine failed 23/24 island-ON while 24/24 island-OFF. Fixes that DON'T work: (a) relaxing the pass predicate (loses the assertion); (b) picking the TALLEST patch for "more clearance" — verified live to be the WRONG lever: the tall patch has the same deep-fall drift and on a different world its face was un-terraced so it caught nothing. What worked: DERIVE the run-up from the measured lip so the body catches HIGH with real margin — a short aim point just past the lip edge (`> LedgeReach`) keeps the body within reach of the FACE, so it latches the cliff-face node lattice ~0.5 m below the lip and ~2 m above ground, on the SAME node in both worlds (a 0.25 m lip shift moves it negligibly). Rule: proc-terrain-derived assertions must select venues WITH margin and derive timing from MEASURED geometry, never blind nearest-origin with a razor-margin outcome; the catch point must clear the low ground by metres, not centimetres. ( AppendLedgeWalkoff, verified seed 42 island ON/OFF, 2026-07-14)**

- ****A "body is below the collision surface => tunnel/fall-through" invariant FALSE-POSITIVES on a wall-climb.** A down-trace from the body's own XY, while it node-climbs a cliff (or hangs in Air just below the lip mid-approach), hits the cliff TOP above the body -- so `bodyZ < surfZ - k` reads as "tunneled below terrain" when the body is legitimately clinging to the face below the lip. A near-identical adjacent cliff passed only by transition timing (the false trip is a knife-edge). Fix: exclude climb legs from the belowSurface sub-check while keeping the absurd-drop (fell far below last-ground) and out-of-world guards LIVE on climb legs -- they still catch a real climb-leg fall without the false trip. General rule: a "below surface" tunnel probe is only meaningful on OPEN ground/air, never against a vertical face the body is meant to hug. (, Roam fall-through invariant, seed 822, 2026-07-14)**

- ****A movement/state-machine test that asserts "a catch/transition ENGAGED" by POLLING the sampled state each fixed tick (`if (State == Climb) pass`) misses a REAL transition that lasts ~1 tick and bounces back — the routine then runs to timeout despite the event having fired.** Distinct from venue selection (g-game-proc-terrain-regression-knife-edge-catch): even with a correct high-margin venue, `ledge_walkoff_coyote` FAILED on seed 47 because the body OSCILLATED catch/release right at the lip (Air<->Climb every ~0.28 s, each grab ~1 tick, ~0.3 m below the lip) — a genuine face regrab, but the per-tick `State == Hang/Climb` poll (further gated behind a 0.5 m below-lip heuristic the marginal catch never satisfied) never coincided with a Climb tick, so the step timed out. The assertion ("the jump re-enabled the catch") is satisfied the INSTANT a catch engages, so latch it on the transition EDGE, not the sampled level: the transition-logging seam already runs every tick before the phase branches, so set a `_caught` bool there on the first post-jump `->Hang/Climb` change and PASS on the latch (honoured BEFORE any positional gate). Rule: assert state-machine events on the transition edge (rising-edge latch), never on a per-tick level poll — a 1-tick physics state that bounces back is invisible to a level poll but is exactly the event you care about. Also bump the timeout for margin, but the latch is the fix. ( TickWalkOffLedge _walkOffCoyoteCaught, verified seeds 47/56/42, 2026-07-14)**

- ****A "return the actor to safety when it's out of bounds" observer whose predicate is a PURE DISTANCE-FROM-CENTER test (no check that the actor is actually IN the hazard) will teleport an actor that is legitimately far away on solid ground — e.g. a second world coexisting elsewhere in the scene.** ' `WaterBoundary` (returns a character lingering past the island's outer ring to shore) flipped its default predicate from `AllDeepWater` (maps the actor to a grid cell, requires a deep WATER cell + submerged feet — off-grid returns false) to `OutsideBoundaryRing` (`distXY > ringM`, radius only). The generated terrain sits ~158 m offset from the world origin while the courtyard stays AT the origin, so any pilot routine that teleported the character to a courtyard venue put it ~158 m outside the island ring -> "washed ashore" mid-routine, silently failing 12 courtyard routines of the terrain suite (they read as fall-through). The radius-only predicate also latently teleports a character standing on DRY land past the ring (benign only while the island fits inside the ring). Two lessons: (1) an out-of-bounds/hazard predicate must confirm the actor is IN the hazard (over water / below the surface), not merely far from a center — distance alone can't tell "swam into the ocean" from "standing in a different world"; (2) gate gameplay OBSERVERS (this, auto-pickup, toast unlocks, auto-teleport) off during pilot/test runs via the pilot-armed flag, exactly like the systems that already do, so a test's teleports never fight a background observer. A default-flip like this needs a live regression pass before merge — headless build stays green while the behavior silently regresses. ( OnUpdate/IsTriggered, 2026-07-14)**

- ****A "body is below the collision surface = fall-through" invariant that down-traces from ABOVE the body to find the surface will FALSE-FIRE when the body legitimately stands on a lower shelf beneath an OVERHANG — the trace hits the overhang ceiling, not the shelf floor.** roam battery, seed-555 run leg: the character ran down a valid corridor onto a lower shelf (grounded at bodyZ~7.5 m moments before and after), but `SurfaceZAt` traced from body+8 m downward and hit an overhang at 15.4 m -> "body 6.8 m below surface" -> false `fall-through` FAIL, 13/14 battery (deterministic, gridHash fe1fafe5710fc190). The existing CLIMB-leg exclusion covered cliff faces but not run-onto-shelf-under-overhang. Fix: a GENUINE tunnel sinks the body below the ground it last stood on, so require the body to also be below `_roamLastGroundZ` by the margin (`here.z < surfZ - m && here.z < lastGroundZ - m`). Adding the `&&` clause can only REDUCE firing and cannot miss a real tunnel (tunnelling is by definition below the floor you were on); an overhang shelf has the body at/above last-ground -> excluded. After: seed-555 4/4, full battery 14/14 clean x2. Rule: any "below the surface above me" check needs a "and below where I last stood" companion, or overhangs read as tunnels. ( fall-through guard, 2026-07-14)**

- **A per-run accumulator guard (budget/cooldown/streak counter) that RESETS on a transient state flicker never actually fires — the reset keeps zeroing it faster than it can fill.** Symptom on a step-up controller: a cumulative "max total rise per consecutive step-up run" budget (added to stop the character elevatoring up a lattice-free voxel cliff by chain-stepping its 0.25 m risers) was in the build, yet telemetry showed 47 chained step-ups and ZERO budget-blocks — 1.78 m of rise in 0.5 s. TWO reset holes, both the same shape: **(1) an over-eager AIRBORNE reset.** The budget cleared on ANY airborne tick, but a sprint up a voxel staircase flickers Ground->Air for 1-2 ticks at every tread lip (a single-tick ground-probe miss over the riser seam), so the budget zeroed every riser. Fix: gate the reset on SUSTAINED air (continuous-air timer >= ~0.2 s), so a real jump/fall resets but a sub-tick flicker does not. Bonus: a jump already hard-clears coyote grace (sets the grounded timer to a large sentinel), so gating on that same timer makes jumps still reset INSTANTLY while flickers don't. **(2) a phantom FLAT-STRIDE reset.** A "walked a flat plateau, clear the budget" reset accrued the INTENDED pre-slide velocity delta each tick — so sprinting straight INTO a wall (the move dead-stopped by collision, realized displacement ~0) still banked a full stride of phantom "flat" distance and cleared the budget while the body was pinned to the face. Fix: accrue REALIZED net-forward displacement (post-collision position delta projected on the move dir, clamped >=0), so a dead-stop and a lateral wall-slide both add ~nothing. General lesson: an accumulator meant to survive a contiguous episode must reset only on a signal that TRULY ends the episode (sustained air, real forward progress) — never on a per-tick proxy (any-air, intended-velocity) that the episode itself trips constantly. Audit every reset path before trusting the guard.

- **A self-siting "grab-held walk off the lip to climb DOWN a cliff" test mis-sites two ways on a treed procedural voxel world — both make it hang/timeout, neither is a movement bug.** ' `climb_down_release` picks the nearest cliff patch, teleports above the lip, then walks off HOLDING GRAB expecting to latch the cliff-face lattice (→ Climb) and descend. At the 2x production world-scale it timed out because (1) a tree `SwingRope` VINE hung within the grab radius of the nearest face, so the grab latched the vine (→ Swing) and the character swung forever; and (2) even on a vine-clear face the walk-off latches the lattice's **TOP** node (that is where the body crosses the lip) and a grab-held forward walk there immediately **mantles over the lip** (top-out) instead of descending — `minClimbZ == grabZ`, i.e. no climb-DOWN happened, which a weak `enteredClimb && Ground` pass check would score as a false green. General lesson: a self-siting movement test that relies on an auto-grab must pick a venue **clear of competing grabbables** (ropes/vines win the grab and change the resulting state) **and** shaped so the intended entry node isn't the one that triggers a different transition (a top-of-face grab top-outs; grab mid-face to actually descend). When the procedural world can't offer such a venue, SKIP with a precise reason rather than emit a venue-shaped FAIL/false-PASS.

- **A state change made INSIDE a subroutine of a state tick is silently stomped when the caller's tick keeps running — the telltale is ENTER telemetry with no matching EXIT.** ' air-clamp rescue entered Climb from within TickAir's clamp call; TickAir then continued to its landing check, which saw "grounded + not rising" (the rescue seats the body on a ground-level base node and zeroes velocity) and wrote State=Ground in the SAME tick — no ExitClimb, no state transition ever observed by loggers or the pilot (live: 17× `ENTER via=buried-runin`, zero EXIT lines, climb never survived one tick). Any escape valve that hands off to another state mid-tick needs the caller to re-check: `if (State != <myState>) return;` right after the call that can rescue. The pre-existing deep-wedge rescue had the same latent hole — it survived only because its historical geometries never had standable ground under the node.

- **A "don't act on stale data" guard placed at the TOP of an escape-valve chain disables the valves that never needed that data — leaving a failure mode with no escape at all.** ' buried-containment chain early-returned when the last UNBURIED position was > 2 s old (correct for the anchor-dependent eject/recover teleports — a stale anchor is a bad destination), but the return also skipped the anchor-FREE stationary escapes (top-out onto the body's own column, lattice-node rescue). Because the air-clamp only banks the anchor on Air ticks, a long grounded stretch always staled it — a body that then slid inside a tall terrain face had NO valve: infinite `SUPPRESSED` telemetry, permanently inside the wall (live: hard-place repro sat 60+ s, zero valve activity). Fix pattern: gate each valve on the data IT needs — the stale-anchor path now runs the stationary escalation (same sustain threshold), skipping only eject/recover. Audit any early return above a multi-valve chain: list which valves actually consume the guarded datum.

- **A streak/window discriminator tuned on ONE interaction cadence structurally never fires for another.** ' buried-mantle escape required 5 ejects each < 0.5 s apart — correct for a PINNED body (~0.3 s eject cadence), but a RUNNING player's bump→eject→re-approach cycle is 0.6–0.7 s, so the streak reset to 1 forever and the sub-capsule riser rubber-banded for as long as the owner kept trying (he quit the session inside the loop). The mechanism's own doc said "a walled ledge re-buries every cycle and the streak climbs" — true only at the cadence it was tuned on. Fix pattern: enumerate the interaction rhythms (pinned, running, jumping) before trusting any cadence-gated accumulator — or replace accumulation with a per-event PROOF (here: sustained burial + a meaningful entry direction ⇒ mantle immediately, no streak; the stationary chain keeps the streak).

- **Custom components in scene JSON**: `__type` is the plain class name when the class has no namespace (e.g. `"Bootstrap"`, `"GolfHole"`). Keep bootstrap-referenced classes namespace-free.

- Scene JSON details: positions/rotations are strings (`"x,y,z"`, quat `"x,y,z,w"`)

- **A `[get; private set;]` static that deliberately survives the editor→play boundary leaks a prior scene's world into a later boot — and any feature that trusts "static == null ⇒ inert" then fires spuriously.** s&box keeps statics across play stop/start (no assembly reload), and world-gen code often relies on this on purpose (e.g. `WorldGen.Grid`/`CurrentSpec` carried for the M7 edit→play handoff). A new water-gated Swim state trusted "no terrain grid ⇒ WaterQuery returns 0 ⇒ swim inert (the waterless courtyard)". But if ANY terrain world was generated earlier in the SAME editor process, `WorldGen.Grid` stays non-null, so the courtyard character maps onto a stale island water cell and enters a phantom Swim state — all land traversal then stalls (every pilot MoveTo/climb step times out; the character stuck in `state=Swim` at Z≈4). It boots clean from a fresh process (statics start null), so it only bites in a long-lived editor or a terrain→courtyard transition — easy to miss headless, and a shared editor makes the pilot batteries fail mysteriously. Fix: don't trust a persisted static as a scene guard; add an explicit `ClearWorld` (null Grid/CurrentSpec/WorldRoot + heightfield/chunk registries) and call it at the top of the non-terrain scene's build. A real terrain boot re-establishes the grid immediately afterward via Regenerate (the terrain convar runs only in play, after that build).

- **A runtime `Scene.LoadFromFile` switch lands a scene HALF-BUILT when its Bootstrap builds heavy world content synchronously in `OnStart`.** `Scene.LoadFromFile(string)` / `Scene.Load(GameResource)` DO switch the running game's active scene at runtime and are whitelist-clean (verified engine 26.07.08e) — `editor_status.ActiveScene` flips and the target scene's own bootstrap `OnStart` runs, so a `[ConVar]` command like ``/`` (`set => Game.ActiveScene.LoadFromFile("scenes/x.scene")`) is a clean ergonomic way to jump into a dev scene without editing `.sbproj StartupScene` + reloading the editor. BUT the target scene's camera/HUD/overlay come up while the heavy world REBUILD its `OnStart` kicks off (in, `MapLabBootstrap` sets `pg_lowpoly_world=1` → `RebuildProductionWorld`) produces **zero output** mid-switch: the prior scene's teardown left the world-gen statics stale (a `TreePass._root` pointing at a destroyed GameObject → `HasTrees==false`), so the lab landed with its overlay markers rendering off stale `TreePass.Placed` data over **no actual forest**, and the pilot (``) SKIP'd `no-live-forest`. Same class: pilots that rely on the playground-boot infrastructure (a spawned pilot character via `TryBootSinglePlayer`) don't engage in a scene-switched lab. Scenes that build their OWN content in `OnStart` (mechanics_lab's box gallery) DO come up fine — the trap is specifically **world-build logic that reads statics established by the ORIGINAL StartupScene boot path**. Two takeaways: (1) `LoadFromFile`/`Scene.Load` are LOCAL-only — they do NOT bring MP peers (engine points MP scene changes at `Game.ChangeScene(SceneLoadOptions)`), so they're for single-player/owner dev tools, not a shipped MP path; (2) if a scene must fully rebuild on a runtime switch, DEFER the build past the scene-load frame (next tick after settle) and/or force-reset the world-gen statics — a synchronous `OnStart` rebuild that assumes a fresh-from-StartupScene static state is the failure mode.

- **When a world model is FP-hidden and replaced by a camera-attached viewmodel, cosmetics that must remain visible in FP need a SEPARATE copy parented into the viewmodel** — driven off the same replicated edge as the world copy (e.g. a networked sequence counter). Never re-tag the world copy visible (it renders at the world hand bone, disconnected from the camera-attached viewmodel). Reuse model-local offsets unchanged; per-frame parent scale keeps it proportional. Keep audio on the every-peer world path so the shot never sounds twice.
