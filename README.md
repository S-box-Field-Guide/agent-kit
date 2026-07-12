# s&box Field Guide

**Real s&box gotchas from shipping games** — verified fixes, pipelines, and workarounds we hit while building, written down so you don't have to rediscover them.

A community collection of the miscellaneous stuff that costs you an afternoon. Complementary field notes from developing in s&box — not a replacement for the [official docs](https://sbox.game/dev/doc). Nothing here is official; it's just what we ran into, shared in case it saves someone else the time. Where something is suspected but not confirmed, it's marked `(unverified)`.

> **Heads up:** s&box moves fast. Fixes are stamped against the engine build they were
> verified on where it matters. If an entry is stale, please
> [open an issue](../../issues) — that's how this stays trustworthy.

## Two ways to use this

**Read it.** Start with [`_core.md`](_core.md) — the handful of cross-cutting rules that
cause most failures. Then load the one **lane pack** for your task ([`index.md`](index.md)
has the map). Dip into the topic docs below for the deeper narrative on an area.

**Give it to your coding agent.** Clone this repo into your agent's skills so it reads
the relevant doc *before* it writes s&box code — see [`SKILL.md`](SKILL.md). The whole
guide is structured so an agent can load just the doc it needs for the task at hand.

```bash
git clone https://github.com/S-box-Field-Guide/agent-field-guide
# then point your agent's skills at it, or just browse the docs
```

## The docs

| Doc | Covers |
|---|---|
| [_core.md](_core.md) | ⭐ The cross-cutting rules. Load this first, every time. |
| [index.md](index.md) | The lane map — which `<lane>.md` pack to load for your task, with coverage counts. |
| [`<lane>.md`](index.md) | Per-lane gotcha checklists: `getting-set-up`, `getting-art-in`, `rigging-animation`, `writing-gameplay`, `building-ui`, `audio`, `making-it-perform`, `publishing-shipping`, `ai-assisted-workflow`, `tooling-environment`. |
| [coverage.md](coverage.md) | What's covered vs. the backlog. |
| [project-setup.md](project-setup.md) | `.sbproj` / `.csproj` / folder layout / `Input.config` / scene skeleton / compile verification |
| [asset-pipeline.md](asset-pipeline.md) | Blender headless → OBJ → `.vmdl`/`.vmat`, units, axes, textures, animated parts |
| [ai-assets.md](ai-assets.md) | Getting AI-generated 3D models (Tripo/Meshy/Rodin-style) into s&box, and the fixes they need |
| [code-patterns.md](code-patterns.md) | Components, singletons, runtime world-building, movement, save/load, networking |
| [ui-razor.md](ui-razor.md) | Razor panels, `BuildHash`, scss, modal routing, the namespace trap |
| [publishing.md](publishing.md) | Publishing to sbox.game — org/ident/publish states, store-page quality metric, Play Fund, standalone Steam export, whitelist traps |
| [tooling.md](tooling.md) | Blender CLI, python generators, `dotnet build`, Windows/PowerShell traps |
| [ai-assisted-development.md](ai-assisted-development.md) | Building s&box games with AI coding agents — division of labor, telemetry-driven feel tuning, the verification gaps that bite |

## Scope

This is s&box-specific engine knowledge: the C# game API, the ModelDoc/material
pipeline, Razor UI, the asset compiler, publishing to the platform. It is not a
general C# or Blender tutorial. Pair it with the official
[Facepunch wiki](https://sbox.game/dev/doc) and API docs — this pack is the field
notes from shipping games on top of that baseline.

## Contributing

Found something out of date, or have a trap of your own with a verified fix?
[Open an issue](../../issues). Corrections are folded in with their engine-build
context so the guide stays honest as s&box evolves.

## License

[CC BY 4.0](LICENSE) — use it, adapt it, ship it into your agent's skills; just keep
attribution. Code snippets are provided as-is for you to use freely.
