# s&box Agent Kit

**Real s&box gotchas from shipping games** — verified fixes, pipelines, and workarounds we hit while building, written down so you don't have to rediscover them.

A community collection of the miscellaneous stuff that costs you an afternoon. Complementary field notes from developing in s&box — not a replacement for the [official docs](https://sbox.game/dev/doc). Nothing here is official; it's just what we ran into, shared in case it saves someone else the time. Where something is suspected but not confirmed, it's marked `(unverified)`.

> **Heads up:** s&box moves fast. Fixes are stamped against the engine build they were
> verified on where it matters. If an entry is stale, please
> [open an issue](../../issues) — that's how this stays trustworthy.

## Two ways to use this

**Read it.** Start with [`_core.md`](_core.md) — the handful of cross-cutting rules that
cause most failures. Then load the one **lane pack** for your task ([`index.md`](index.md)
has the map). Dip into the topic docs below for the deeper narrative on an area. Prefer a
browsable, human-readable version? The [s&box Field Guide website](https://sboxguide.dev)
is the companion to this pack.

**Give it to your coding agent.** Clone this repo into your agent's skills so it reads
the relevant doc *before* it writes s&box code — see [`SKILL.md`](SKILL.md). The whole
guide is structured so an agent can load just the doc it needs for the task at hand.

```bash
git clone https://github.com/S-box-Field-Guide/agent-kit
# then point your agent's skills at it, or just browse the docs
```

## The docs

| Doc | Covers |
|---|---|
| [_core.md](_core.md) | ⭐ The cross-cutting rules. Load this first, every time. |
| [index.md](index.md) | The lane map — which `<lane>.md` pack to load for your task, with coverage counts. |
| [`<lane>.md`](index.md) | Per-lane gotcha checklists: `getting-set-up`, `getting-art-in`, `rigging-animation`, `writing-gameplay`, `building-ui`, `audio`, `making-it-perform`, `publishing-shipping`, `ai-assisted-workflow`, `tooling-environment`. |
| [guides/](guides) | Long-form method write-ups: project setup, asset + part-kit pipelines, networking, movement, save/load, vehicle physics, and more. |
| [coverage.md](coverage.md) | What's covered vs. the backlog. |

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
