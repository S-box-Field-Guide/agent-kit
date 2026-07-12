# UI: Razor panels

## Panel skeleton

```razor
@using Sandbox
@using Sandbox.UI
@namespace MyGame @* ← REQUIRED, see the trap below *@
@inherits PanelComponent

<root>
    @if ( Game is not null && UIState.ThisPanelOpen )
    {
        <div class="panel"> … </div>
    }
</root>

@code {
    GameState Game => GameState.Instance;
    protected override int BuildHash => HashCode.Combine( /* EVERYTHING the markup reads */ );
}
```

Paired `MyPanel.razor.scss` styles it; **the root selector is the class name**
(`MyPanel { … }`). One GameObject hosts `ScreenPanel` + every PanelComponent.

## The two traps (cost us real debugging time)

1. **`@namespace`** — razor classes do NOT land in the global namespace like plain
   .cs files; they get a RootNamespace/folder-derived one. Declare `@namespace X`
   in every .razor and `global using X;` in Assembly.cs, or C# can't find your
   panels and razor resolves Sandbox types over yours.
2. **`BuildHash` is the only re-render trigger.** Any value the markup displays
   but the hash omits = silently frozen UI. Include derived strings too (they're
   cheap) and remember collection contents (`Counts.Values.Sum`), day/date, and
   open/closed flags.

## Modal routing

A static `UIState` with one bool per panel + `AnyModalOpen` aggregating them
(including transient states like a day-summary flag). The game clock and player
input check `AnyModalOpen` → opening any panel pauses the world. Each panel
closes itself on `Input.Pressed("attack2")` in its own `OnUpdate`; toggle-key
ownership lives in ONE place per key (two components both reacting to the same
key press = same-frame open/close races).

## SCSS notes (s&box's dialect)

- Flexbox-ish: `flex-direction`, `justify-content`, `align-items`; everything is
  a flex container by default — set `flex-direction: column` on stacks.
- `position: absolute` + `pointer-events: none` on the HUD root;
  `pointer-events: all` only on clickable children (this also makes the cursor
  usable over them).
- Nesting + `&.modifier` work; `linear-gradient` works (bars, backdrops);
  `transition: all 0.1s ease` + `&:hover` for buttons.
- `text-shadow` for anything drawn over the 3D scene.
- Emoji make perfectly good icons at 20-30px font-size (hotbar, buttons, toasts).

## Event handlers

`onclick=@Close` or `onclick=@( => Do(x))`. Loop-variable capture: copy to a
local (`var idx = slot++;`) before the lambda.

## Patterns that worked

- **HUD** = dashboard block (top-left), toast stack (top-right, self-expiring via
  `TimeSince` + list prune in OnUpdate), prompt + hotbar (bottom-center), hints
  (bottom-right), full-screen modal backdrops inside the same panel.
- **Title screen**: `UIState.StartMenuOpen = true` by default; the game-state
  component waits; menu buttons call `StartNew` / `ContinueGame`. Continue only
  renders when `FileSystem.Data.FileExists(saveFile)`. Destructive New Game gets an
  inline confirm, not a separate modal.
- **Admin/debug panel** (toggle O): buttons that poke singletons directly — set
  time/weather, grant items, spawn, teleport, force event flags. Build it EARLY;
  it pays for itself the first playtest.
- Editing .razor files with shell tools: byte-safe only (see tooling.md — PS 5.1
  mojibake destroys the emoji).
