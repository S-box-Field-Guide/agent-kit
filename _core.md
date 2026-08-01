# s&box Skill Pack — core rules (always load)

> **This is the only always-load file.** It carries the cross-cutting rules that cause most
> failures. Load this first, then load the one lane pack for your task (see `index.md`), then
> follow a bullet's article link in `coverage.md` for the full write-up (full articles live on
> the Field Guide website, not in this pack).
>
> Sanitized public derivative of private field notes — engine-level, reproducible advice only.
> Unverified material is either held back or carries an explicit **Unverified:** label.

## The recurring rules

These cause most failures. Internalize them before anything else.

- **Units are inches** (1 m = 39.37 u). Do design math in SI and convert at exactly one
  engine boundary: `const float M = 39.37f`. Meters/units mixups travel in packs — sweep
  the whole file and assert the full transform, don't fix one call site.
- **`dotnet build` does NOT enforce the s&box whitelist.** A clean build can still be
  rejected at runtime (`Environment.*`, `System.IO`, `Process`, reflection → SB1000).
  Sweep new code for these before claiming it works.
- **`BuildHash()` is the only Razor re-render trigger** — hash everything the markup reads,
  or the panel silently shows stale state.
- **Colliders don't all follow `WorldScale`** — `BoxCollider` does; `CapsuleCollider` and
  `ModelCollider` do NOT. Scaled props get mismatched collision unless you bake scale into
  a vmdl wrapper or put the collider on an unscaled sibling.
- **New assets / inputs need an editor kick or Play restart** — a headless build won't
  surface them.
- **"Verified in-editor" ≠ "works after publish."** The whitelist and loose-resource rules
  diverge at publish time — re-check before shipping to sbox.game.
