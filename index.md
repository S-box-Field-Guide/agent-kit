# s&box Skill Pack — index

> Load `_core.md` (always), then the one lane pack for your task. For a bullet's full write-up,
> follow its article link in `coverage.md` — full articles live on the Field Guide website, not
> in this pack. `coverage.md` is the full coverage view and skip-list.

| Lane | Pack file | Covers | Gotchas | Articled |
|---|---|---|--:|--:|
| Getting set up | `getting-set-up.md` | New project skeleton, compile verification. | 0 | 0 |
| Getting art in | `getting-art-in.md` | Blender/AI mesh → in-game, correct scale & facing. | 39 | 23 |
| Rigging & animation | `rigging-animation.md` | Blends, ragdolls, retargeting mocap. | 23 | 18 |
| Writing gameplay | `writing-gameplay.md` | Components, movement, save/load, networking, runtime meshes. | 87 | 18 |
| Building UI | `building-ui.md` | Razor HUD that re-renders. The BuildHash trap. | 22 | 11 |
| Audio | `audio.md` | .sound events by hand, looping, 3D positional. | 9 | 4 |
| Making it perform | `making-it-perform.md` | Triangle census, collider choice, density limits. | 4 | 0 |
| Publishing & shipping | `publishing-shipping.md` | sbox.game store, the whitelist divergence. | 0 | 0 |
| AI-assisted workflow | `ai-assisted-workflow.md` | Coordinating agents to build a game. | 0 | 0 |
| Tooling & environment | `tooling-environment.md` | Windows/PowerShell/dotnet traps. | 50 | 18 |

Always-load core rules: `_core.md`. Coverage / backlog: `coverage.md`.

## Guides (method syntheses)

Long-form build-order guides for common systems. These are the "how do I architect X" complement to the fix-level bullets above.

| Guide | File | Covers |
|---|---|---|
| Agent test harness | `guides/agent-test-harness.md` | MCP-driven in-editor playtest automation |
| Runtime terrain meshing | `guides/runtime-terrain-meshing.md` | Voxel heightfield meshing, decimation, LOD |
| Networking methods | `guides/networking-methods.md` | Deterministic spec-replication, host authority |
| Vehicle physics | `guides/vehicle-physics.md` | Arcade raycast car on voxel terrain |
| Parkour movement | `guides/parkour-movement.md` | Wall-run, climb, vault on a trace-mover |
| Part-kit assembly | `guides/part-kit-assembly.md` | Modular vehicle damage via part-kit manifests |
| Delta-log save | `guides/delta-log-save.md` | Append-only delta save for large procedural worlds |
| Voice proximity chat | `guides/voice-proximity-chat.md` | Built-in Sandbox.Voice for proximity PTT |
