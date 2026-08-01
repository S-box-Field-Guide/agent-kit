# s&box Skill Pack — index

> Load `_core.md` (always), then the one lane pack for your task. For a bullet's full write-up,
> follow its article link in `coverage.md` — full articles live on the Field Guide website, not
> in this pack. `coverage.md` is the full coverage view and skip-list.

| Lane | Pack file | Covers | Gotchas | Articled |
|---|---|---|--:|--:|
| Getting set up | `getting-set-up.md` | New project skeleton, compile verification. | 0 | 0 |
| Getting art in | `getting-art-in.md` | Blender/AI mesh → in-game, correct scale & facing. | 79 | 31 |
| Rigging & animation | `rigging-animation.md` | Blends, ragdolls, retargeting mocap. | 35 | 23 |
| Writing gameplay | `writing-gameplay.md` (router → sub-files `writing-gameplay--movement-physics.md`, `--world-gen-terrain.md`, `--patterns-lifecycle.md`, `--networking-multiplayer.md`, `--input-camera-ui.md`) | Components, movement, save/load, networking, runtime meshes. | 338 | 81 |
| Building UI | `building-ui.md` | Razor HUD that re-renders. The BuildHash trap. | 80 | 30 |
| Audio | `audio.md` | .sound events by hand, looping, 3D positional. | 11 | 6 |
| Making it perform | `making-it-perform.md` | Triangle census, collider choice, density limits. | 8 | 4 |
| Publishing & shipping | `publishing-shipping.md` | sbox.game store, the whitelist divergence. | 0 | 0 |
| AI-assisted workflow | `ai-assisted-workflow.md` | Coordinating agents to build a game. | 0 | 0 |
| Tooling & environment | `tooling-environment.md` (router → sub-files `tooling-environment--editor-mcp.md`, `--build-compile-whitelist.md`, `--engine-environment.md`, `--assets-blender-external.md`) | Windows/PowerShell/dotnet traps. | 170 | 47 |

Always-load core rules: `_core.md`. Coverage / backlog: `coverage.md`.

## Guides (method syntheses)

Long-form build-order guides for common systems. These are the "how do I architect X" complement to the fix-level bullets above.

| Guide | File | Covers |
|---|---|---|
| Agent-buildable project setup | `guides/agent-buildable-project-setup.md` | Fresh project skeleton an agent can build in |
| Agent test harness | `guides/agent-test-harness.md` | MCP-driven in-editor playtest automation |
| Character-mounted assets | `guides/character-mounted-assets-live-tuning.md` | Mounting models on player rig with live-tuning |
| Decals | `guides/decals.md` | Projection, determinism, and performance for Sandbox.Decal |
| Delta-log save | `guides/delta-log-save.md` | Append-only delta save for large procedural worlds |
| First-person viewmodel | `guides/first-person-viewmodel.md` | Two-view camera split: world model third-person, viewmodel first-person |
| Library packages | `guides/library-packages.md` | Splitting reusable code into an s&box Library package and consuming it from a game |
| Networking methods | `guides/networking-methods.md` | Deterministic spec-replication, host authority |
| P2P peer-hosted servers | `guides/p2p-peer-hosted-servers.md` | Player-hosted multiplayer: lobby, invite codes, join handshake |
| Parkour movement | `guides/parkour-movement.md` | Wall-run, climb, vault on a trace-mover |
| Part-kit assembly | `guides/part-kit-assembly.md` | Modular vehicle damage via part-kit manifests |
| Performance investigation | `guides/performance-investigation.md` | Measure-first harness for "the game feels slow" |
| Ragdoll physics | `guides/ragdoll-physics.md` | Scripted-rig NPC crumple without collapse clips |
| Runtime terrain meshing | `guides/runtime-terrain-meshing.md` | Voxel heightfield meshing, decimation, LOD |
| Vehicle audio | `guides/vehicle-audio.md` | Engine loops, RPM crossfade, slip SFX |
| Vehicle physics | `guides/vehicle-physics.md` | Arcade raycast car on voxel terrain |
| Voice proximity chat | `guides/voice-proximity-chat.md` | Built-in Sandbox.Voice for proximity PTT |
| World scale and coordinate limits | `guides/world-scale-and-coordinate-limits.md` | Units, the 20k folklore, and fp32 precision coarsening from origin |
