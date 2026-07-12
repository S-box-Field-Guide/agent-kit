# Code patterns

## Component basics

```csharp
[Title("Crop Plot")] [Category("MyGame")] [Icon("grass")]
public sealed class CropPlot : Component
{
    [Property, Group("Tuning")] public float X { get; set; } = 1f; // editor-exposed
    [RequireComponent] public Rigidbody Body { get; set; } // auto-attach
    protected override void OnAwake { } // on Create — set singletons HERE
    protected override void OnStart { } // first enabled frame — children/visuals here
    protected override void OnUpdate { } // per frame: input, visuals
    protected override void OnFixedUpdate { } // 50 Hz: physics, sim
    protected override void OnDestroy { }
}
```

**Runtime creation order matters:** `Components.Create<T>` fires `OnAwake`
immediately, `OnStart` later. So: create manager singletons first (their
`OnAwake` publishes `.Instance`), world next, state-holding components last so
their `OnStart` can see the world.

**Singleton pattern**:
```csharp
public static Foo Instance { get; private set; }
protected override void OnAwake => Instance = this;
protected override void OnDestroy { if (Instance == this) Instance = null; }
```
Everything reads `Foo.Instance` with null-guards; no reference wiring.

## Runtime world-building

Helpers worth copying from `Code/Game/WorldBuilder.cs`:
- `FlatBox` — `models/dev/box.vmdl` (a 50u cube) scaled via `WorldScale = size/50f`,
  `MaterialOverride` for terrain/water/roads. Remember: decal tops above ground top.
- `Prop` — catalog model + bounds-sized static BoxCollider + placement-obstacle registration.
- `Deco` — renderer only (flowers, cattails), no collider/footprint.
- `Wire` — thin box stretched between two points via `Rotation.LookAt(delta.Normal)`.

Placement obstacles as plain data beat physics queries for build-validity:
`record struct Obstacle(GameObject Go, Vector3 Pos, float Radius, bool IsWater)` —
removable by GameObject when a tree is felled, and special flags (water) let
creek-only buildables opt out.

## Interactables

```csharp
public interface IInteractable { string GetPrompt(Character p); void Interact(Character p); }
```
- **Don't scan by interface** (`GetAllComponents<Component>.OfType<I…>` returns
  nothing at runtime). Keep an explicit union: one static method yielding each
  concrete type's `GetAllComponents<T>`. Cache the list on a 0.25 s timer.
- Pick the nearest candidate **whose prompt is non-null** — components can decline
  (a healthy solar panel prompts nothing; a storm-blown one says "re-anchor").
- UX: floating marker over the target (bounds-top + bob + spin) + a `[F] prompt`
  line in the HUD. This mattered a lot for discoverability.

## Movement (kinematic top-down)

- Wish dir = `Rotation.FromYaw(cameraYaw) * new Vector3(Input.AnalogMove.x, .y, 0)`.
- Sphere trace ahead: hit → project wish onto the plane (`wish - n * wish.Dot(n)`),
  re-trace the slide, else stop.
- **Always handle `tr.StartedSolid`** — ignore collision that frame so an overlapped
  player can walk free (see gotchas: permanent-entrapment bug).
- Jump as pure visual/vertical state: track `_height/_verticalSpeed` yourself, keep
  horizontal traces at fixed torso height.
- Feel: squash-and-stretch on land, hip bob while walking, lerp facing at ~12×dt.

## Camera

- **Iso**: `CameraComponent.Orthographic = true`; position =
  `focus - Rotation.From(pitch,yaw,0).Forward * dist`; yaw snaps ±90 with
  `MathX.LerpDegrees`; zoom = lerped `OrthographicHeight`.
  Mouse→ground: manual ortho unproject (offset origin by `Right*nx*orthoWidth`,
  `-Up*ny*orthoHeight`, intersect z=0). No API risk, works everywhere.
- **Chase**: follow flattened heading, exponential smoothing
  `1 - exp(-k*dt)`, orbit on mouse with idle auto-return, FOV widens with speed.

## Save / load

- DTO classes + `Json.Serialize`/`Json.Deserialize<T>` + `FileSystem.Data.WriteAllText/ReadAllText/FileExists`.
- Mark runtime-placed structures with a `PlacedBuildable { BuildId }` component;
  save loop reads component state per GameObject, load loop respawns through the
  same factory used for building — one spawn path, no drift.
- Static world stays deterministic (fixed RNG seed) so only deltas need saving
  (e.g. chopped-tree indices, not tree positions).
- Missing JSON fields → C# defaults, so guard restored values (`x <= 0 ? 1f : x`)
  and keep enums append-only. Autosave on the natural checkpoint (sleep).

## Time / weather driving systems

One clock owner (`GameState`): `TimeOfDay += hoursPerSecond * Time.Delta` in
`OnFixedUpdate`, gated by a global `Paused => UIState.AnyModalOpen`. Everything else
derives: sun rotation/color (DayNightCycle reads the clock), solar watts
(`sin(day-arc) × weather × season`), spawned FX. Daily tick = the transaction
boundary: advance day, roll weather, run each domain's `DailyTick`, bill on
Sundays, autosave.

## Networking

- `Networking.CreateLobby(new LobbyConfig)` in `OnLoad` if `!Networking.IsActive`.
- `Component.INetworkListener.OnActive(Connection)` on host → clone prefab,
  `go.NetworkSpawn(channel)`.
- Owner simulates (`if (IsProxy) return;`), `[Sync]` replicates owner→proxies,
  `[Sync(SyncFlags.FromHost)]` for host-authoritative state, `[Rpc.Broadcast]`
  for events. Host migration and interp come free.

## Heavy work without hitches

- `GameTask.RunInThreadAsync` for parsing/geometry math; main thread only for
  engine objects. `await GameTask.Yield` every N items with a progress property
  a Razor loading screen reads.
- Runtime meshes: `new Mesh(material)` + `CreateVertexBuffer/CreateIndexBuffer` +
  `Model.Builder.AddMesh.AddCollisionMesh.Create`.

## Tuning discipline

All feel-dials in one static class (`VehicleTuning`, `VehicleDefinitions`) — SI units,
commented with observed telemetry. Balance changes never touch logic files.
