# Getting set up — skill pack

> Lane pack. Load `_core.md` first, then this file. Denser than the full articles by design;
> for a matching bullet's full write-up, follow that gotcha's article link in `coverage.md`
> (full articles live on the Field Guide website, not in this pack). Sanitized public
> advice; unverified material is held privately until verified. The sync appends new bullets here.

> **Restored 2026-07-13:** this lane's topic content (below) predates the lane-pack split
> and was restored after an over-eager orphan cleanup; the sync pipeline appends new
> gotcha bullets after it.

## Folder layout (the template every project follows)

```
<project>/
├── <project>.sbproj # project manifest
├── Assets/
│ ├── scenes/*.scene # JSON; startup scene set in sbproj
│ ├── models/…/*.obj + .vmdl
│ └── materials/…/*.png + .vmat
├── Code/
│ ├── Assembly.cs # global usings
│ ├── <project>.csproj # references Steam s&box install
│ └── <domain folders>/*.cs + UI/*.razor(.scss)
├── Editor/ # editor-only assembly (usually untouched)
├── ProjectSettings/
│ ├── Input.config # action bindings
│ └── Collision.config / Platform.config
└── tools/ # python generators (Blender + asset pipeline)
```

## .sbproj essentials

```json
{
  "Title": "MyGame", "Type": "game", "Org": "local", "Ident": "mygame",
  "Schema": 1,
  "Metadata": {
    "MaxPlayers": 64, "MinPlayers": 1, "TickRate": 50,
    "GameNetworkType": "Multiplayer",
    "StartupScene": "scenes/main.scene"
  }
}
```
- `TickRate: 50` = fixed update at 50 Hz (20 ms). Vehicle-grade physics substeps inside that.
- Keep `GameNetworkType: "Multiplayer"` even for single-player (architecture stays open).
- Change `StartupScene` here — it's what Play loads.

## Code/<project>.csproj (generated — know these bits)

- `TargetFramework net10.0`, `RootNamespace Sandbox`, `Nullable disable`.
- References `Sandbox.*.dll` and analyzers out of
  `C:\Program Files (x86)\Steam\steamapps\common\sbox\bin\managed\`.
- **`dotnet build Code/<project>.csproj` verifies compile without the editor.** Do it constantly.
- Razor support comes from `Microsoft.NET.Sdk.Razor` — see ui-razor.md for the namespace trap.

## Assembly.cs

```csharp
global using Sandbox;
global using System;
global using System.Collections.Generic;
global using System.Linq;
global using System.Threading.Tasks;
global using MyGame; // ← whatever @namespace your .razor files declare
```

## Minimal scene + bootstrap pattern (recommended)

Scene JSON contains exactly four GameObjects: **Sun** (`Sandbox.DirectionalLight`),
**Skybox** (`Sandbox.SkyBox2D` + `Sandbox.EnvmapProbe`), **Camera**
(`Sandbox.CameraComponent`, `IsMainCamera: true`), and **Bootstrap** — one custom
component (`"__type": "GameBootstrap"`, plain class name, no namespace).

Bootstrap `OnStart` then builds everything in a deliberate order:

```csharp
protected override void OnStart()
{
    if ( Scene.IsEditor ) return;
    // 1. manager singletons (OnAwake sets .Instance immediately on Create)
    var managers = Scene.CreateObject();
    managers.Components.Create<PowerGrid>();
    // 2. static world 3. player 4. camera/sun component attach
    // 5. UI (one GO: ScreenPanel + every PanelComponent)
    // 6. game-state component last — its OnStart runs after the world exists
}
```

Copy `Assets/scenes/main.scene` as the skeleton; only GUIDs and the
bootstrap `__type` change.

## Input.config

JSON list of `{ Name, GroupName, Title, KeyboardCode, GamepadCode }`. Notes:
- `Input.Pressed/Down/Released("name")` is case-insensitive; underscores must match.
- WASD actions named Forward/Backward/Left/Right feed `Input.AnalogMove` automatically.
- `Input.MouseWheel` is a Vector2; `Mouse.Position` is pixels; `Screen.Width/Height` for math.
- Keep a project-standard set: movement + Run + Jump, Interact (F), Attack1/2 (mouse),
  Slot1-9, plus game-specific (Build, Breaker, Admin…).

## Startup checklist for a brand-new project

1. Copy the template folders; set `Title/Ident/StartupScene` in .sbproj.
2. Write Assembly.cs with the globals + your razor namespace.
3. Drop in the 4-object scene + a Bootstrap component.
4. `dotnet build Code/<proj>.csproj` — green before anything else.
5. Set up `tools/gen_models.py` + `tools/gen_assets.py` from another project's (see asset-pipeline.md).
6. Start every play session by checking the console for `[yourtag]` log lines —
   prefix all `Log.Info` with a project tag.
