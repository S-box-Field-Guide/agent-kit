# Tooling & workflow

## Commands that matter

```powershell
# compile-check without opening the editor (fast, catches API misuse)
dotnet build Code\<project>.csproj

# regenerate art (both, in this order)
& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --python tools\gen_models.py
python tools\gen_assets.py
```

- The csproj references `C:\Program Files (x86)\Steam\steamapps\common\sbox\` DLLs
  directly — a green `dotnet build` means the editor will accept it.
- A compile is necessary but not sufficient: runtime API behavior (e.g. interface
  scene scans) can still differ. Playtest or log-verify anything load-bearing.
- After regenerating models, the s&box editor recompiles the changed assets on next
  focus/load — first load is a few seconds slower, that's normal.

## Windows / PowerShell 5.1 traps

- **Never bulk-edit source with `Get-Content`/`Set-Content`**: BOM-less UTF-8 is read
  as ANSI and re-encoding mojibakes every emoji/em-dash (`â€”`, `ðŸ¥š`). Use python, or
  byte-safe .NET:
  ```powershell
  $c = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($f))
  [System.IO.File]::WriteAllBytes($f, [System.Text.Encoding]::UTF8.GetBytes($c))
  ```
- If mojibake already happened: decode file as UTF-8, re-encode chars via cp1252
  (mapping U+0080–U+009F straight to their byte values), decode result as UTF-8.
  A working fixer script pattern is worth keeping around; rebuild it from this note.
- Blender 5.x warns `Material.use_nodes` is deprecated (removal in 6.0) — harmless
  today; when it breaks, set the Principled inputs via the material's node tree directly.

## Python generator conventions

- `tools/gen_models.py` = Blender-only (bpy); `tools/gen_assets.py` = pure python
  (PNG writer + vmdl/vmat emitters + C# catalog). Keep the split — the second runs
  in ~a second and iterates fast.
- Deterministic seeds everywhere (`random.Random(fixed)`) so regeneration is stable
  and saved worlds stay valid.
- Print each model's computed world-space size when generating — eyeball sanity
  (a 3-unit-tall barn or 300-unit chicken jumps out immediately).

## Debugging in-engine

- `Log.Info($"[projname] …")` — tag every line; the console mixes engine noise in.
- Engine noise that is NOT ours (ignore): missing `citizen_clothes`, `sfm` sounds,
  `menu-main.scene` refs, prop gib materials; Vulkan `QueuePresentAndWait` /
  `VK_TIMEOUT` (driver present stall on alt-tab/shader compile).
- Saves live in s&box's data dir via `FileSystem.Data` — to reset a playtest either
  use the in-game New Game flow or delete the save json.
- Build an **admin/debug panel early** (time/weather/items/teleport) — testing a
  seasonal winter mechanic without one means 40 minutes of real time.

## Session workflow that has worked

1. Explore/plan → write generators → run them → write C# in domain batches →
   `dotnet build` after each batch → fix → repeat.
2. After a big feature burst: spawn a fresh-context review agent over `Code/` to
   hunt runtime bugs — it caught a genuinely broken contract-date calculation.
   Verify each finding against the code before fixing (expect ~80% false positives).
3. Record every new gotcha immediately (in your own field-notes source) so it isn't re-learned.
